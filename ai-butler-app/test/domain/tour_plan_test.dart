import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_butler_app/domain/logic/draft_prefill_mapper.dart';
import 'package:ai_butler_app/domain/models/form_definition.dart';
import 'package:ai_butler_app/domain/models/topic_type.dart';
import 'package:ai_butler_app/features/tour/tour_plan.dart';

/// 導覽步驟由表單定義當場生成（不是寫死的藍圖）。
///
/// 最重要的性質：導覽不能騙使用者。管家沒填的題目要明講「請你自己選」，
/// 最後一步一定要是交棒的送出鈕。
void main() {
  FormTopic topic(
    int id,
    TopicType type, {
    String title = '題目',
    bool required = false,
    List<TopicOption> options = const <TopicOption>[],
    int sort = 0,
  }) {
    return FormTopic(
      topicId: id,
      type: type,
      title: title,
      isRequired: required,
      options: options,
      sort: sort,
    );
  }

  FormDefinition definitionOf(List<FormTopic> topics) => FormDefinition(
        formId: 100,
        serviceVendorId: 1,
        serviceId: 10,
        name: '測試表單',
        groups: <FormGroup>[FormGroup(id: 1, name: '群組', topics: topics)],
      );

  Map<int, GlobalKey> anchorsFor(FormDefinition definition) => <int, GlobalKey>{
        for (final t in definition.allTopics) t.topicId: GlobalKey(),
      };

  List<TourStepProbe> plan(
    FormDefinition definition,
    Map<int, String> answers, {
    Map<String, dynamic> payload = const <String, dynamic>{},
  }) {
    final prefill = DraftPrefillMapper.map(
      definition: definition,
      answers: answers,
      payload: payload,
    );
    final steps = TourPlan.forForm(
      definition: definition,
      prefill: prefill,
      topicAnchors: anchorsFor(definition),
      submitAnchor: GlobalKey(),
    );
    return steps
        .map((s) => TourStepProbe(s.title, s.instruction, s.handOff))
        .toList();
  }

  test('最後一步一定是交棒的送出鈕', () {
    final definition = definitionOf(<FormTopic>[topic(1, TopicType.shortText)]);

    final steps = plan(definition, <int, String>{1: '2'});

    expect(steps.last.handOff, isTrue);
    expect(steps.last.title, '最後一步');
    expect(steps.last.instruction, contains('不幫你按'));
    // 只有最後一步是交棒點
    expect(steps.where((s) => s.handOff).length, 1);
  });

  test('已填好的題目會講出實際填了什麼（選項題要顯示名稱不是 id）', () {
    final definition = definitionOf(<FormTopic>[
      topic(1, TopicType.singleChoice, title: '希望時段', options: <TopicOption>[
        const TopicOption(id: 22, optionName: '18:00'),
      ]),
    ]);

    final steps = plan(definition, <int, String>{1: '18:00'});

    expect(steps.first.title, '希望時段');
    expect(steps.first.instruction, contains('18:00'));
    // 絕對不能把 option_id 唸給使用者聽
    expect(steps.first.instruction, isNot(contains('22')));
  });

  test('複選題把多個選項名稱串起來', () {
    final definition = definitionOf(<FormTopic>[
      topic(1, TopicType.multiChoice, title: '清洗類型', options: <TopicOption>[
        const TopicOption(id: 41, optionName: '直立式'),
        const TopicOption(id: 42, optionName: '滾筒式'),
      ]),
    ]);

    final steps = plan(definition, <int, String>{1: '直立式,滾筒式'});

    expect(steps.first.instruction, contains('直立式、滾筒式'));
  });

  test('管家有答案但對不上選項時，明確請使用者自己選', () {
    final definition = definitionOf(<FormTopic>[
      topic(1, TopicType.singleChoice, title: '希望時段', options: <TopicOption>[
        const TopicOption(id: 22, optionName: '18:00'),
      ]),
    ]);

    final steps = plan(definition, <int, String>{1: '19:00'});

    expect(steps.first.instruction, contains('19:00'));
    expect(steps.first.instruction, contains('請你自己選'));
    // 不能說成已經填好
    expect(steps.first.instruction, isNot(contains('我填的是')));
  });

  test('地區題有專屬說明，講清楚為什麼管家填不了', () {
    final definition = definitionOf(<FormTopic>[
      topic(1, TopicType.region, title: '服務地區'),
    ]);

    final steps = plan(definition, <int, String>{1: '台北市 大安區'});

    expect(steps.first.instruction, contains('區碼'));
  });

  test('照片題必填時提醒使用者自己上傳', () {
    final definition = definitionOf(<FormTopic>[
      topic(1, TopicType.photo, title: '現場照片', required: true),
    ]);

    final steps = plan(definition, const <int, String>{});

    expect(steps.first.instruction, contains('沒辦法幫你上傳'));
  });

  test('沒填的選填題不打擾使用者，必填題才提', () {
    final definition = definitionOf(<FormTopic>[
      topic(1, TopicType.shortText, title: '選填備註', sort: 0),
      topic(2, TopicType.shortText, title: '必填人數', required: true, sort: 1),
    ]);

    final steps = plan(definition, const <int, String>{});

    // 選填題被略過，只剩必填題 + 送出鈕
    expect(steps.length, 2);
    expect(steps.first.title, '必填人數');
    expect(steps.last.handOff, isTrue);
  });

  test('備註說明題不產生步驟', () {
    final definition = definitionOf(<FormTopic>[
      topic(1, TopicType.notice, title: '注意事項'),
    ]);

    final steps = plan(definition, const <int, String>{});

    expect(steps.length, 1); // 只有送出鈕
    expect(steps.single.handOff, isTrue);
  });

  test('步驟順序跟表單的 sort 一致', () {
    final definition = definitionOf(<FormTopic>[
      topic(3, TopicType.shortText, title: '第三題', sort: 2),
      topic(1, TopicType.shortText, title: '第一題', sort: 0),
      topic(2, TopicType.shortText, title: '第二題', sort: 1),
    ]);

    final steps = plan(definition, <int, String>{1: 'a', 2: 'b', 3: 'c'});

    expect(
      steps.take(3).map((s) => s.title),
      <String>['第一題', '第二題', '第三題'],
    );
  });

  test('沒有任何錨點時仍然給出送出那一步', () {
    final definition = definitionOf(<FormTopic>[topic(1, TopicType.shortText)]);

    final steps = TourPlan.forForm(
      definition: definition,
      prefill: DraftPrefillMapper.map(
        definition: definition,
        answers: <int, String>{1: 'a'},
      ),
      topicAnchors: const <int, GlobalKey>{}, // 錨點還沒建好
      submitAnchor: GlobalKey(),
    );

    expect(steps.length, 1);
    expect(steps.single.handOff, isTrue);
  });
}

/// 只取測試關心的欄位，避免直接比對 GlobalKey。
class TourStepProbe {
  const TourStepProbe(this.title, this.instruction, this.handOff);

  final String title;
  final String instruction;
  final bool handOff;
}
