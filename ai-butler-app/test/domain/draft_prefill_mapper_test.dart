import 'package:flutter_test/flutter_test.dart';

import 'package:ai_butler_app/domain/logic/draft_prefill_mapper.dart';
import 'package:ai_butler_app/domain/models/answer_value.dart';
import 'package:ai_butler_app/domain/models/form_definition.dart';
import 'package:ai_butler_app/domain/models/topic_type.dart';

/// AI 管家草稿 → 型別化作答值的轉換。
///
/// 這一層的風險在於 agent 端只會給字串，而 App 用 sealed AnswerValue：
/// 單選要 option_id 不是 option_name、日期要 DateTime、地區要區碼。
/// 轉錯會產生「看起來填好了但其實是錯的」單子，比留空更危險，
/// 所以「寧缺勿錯」是這裡最重要的行為，測試也以它為主。
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

  group('文字題', () {
    test('簡答與詳答直接成為 TextAnswer', () {
      final definition = definitionOf(<FormTopic>[
        topic(1, TopicType.shortText),
        topic(2, TopicType.longText),
      ]);

      final result = DraftPrefillMapper.map(
        definition: definition,
        answers: <int, String>{1: '2', 2: '希望下午來'},
      );

      expect(result.prefill[1], const TextAnswer('2'));
      expect(result.prefill[2], const TextAnswer('希望下午來'));
      expect(result.unresolved, isEmpty);
    });

    test('空白答案不算填寫，也不算未解析', () {
      final definition = definitionOf(<FormTopic>[topic(1, TopicType.shortText)]);

      final result = DraftPrefillMapper.map(
        definition: definition,
        answers: <int, String>{1: '   '},
      );

      expect(result.prefill, isEmpty);
      expect(result.unresolved, isEmpty);
    });
  });

  group('單選題', () {
    final options = <TopicOption>[
      const TopicOption(id: 21, optionName: '17:30'),
      const TopicOption(id: 22, optionName: '18:00'),
    ];

    test('用 option_name 對應出 option_id', () {
      final definition = definitionOf(<FormTopic>[
        topic(1, TopicType.singleChoice, options: options),
      ]);

      final result = DraftPrefillMapper.map(
        definition: definition,
        answers: <int, String>{1: '18:00'},
      );

      expect(result.prefill[1], isA<OptionAnswer>());
      expect((result.prefill[1]! as OptionAnswer).option.optionId, 22);
    });

    test('全形冒號與多餘空白仍能對上', () {
      final definition = definitionOf(<FormTopic>[
        topic(1, TopicType.singleChoice, options: options),
      ]);

      final result = DraftPrefillMapper.map(
        definition: definition,
        answers: <int, String>{1: '18：00'},
      );

      expect((result.prefill[1]! as OptionAnswer).option.optionId, 22);
    });

    test('選項不存在時進 unresolved，不硬塞第一個選項', () {
      final definition = definitionOf(<FormTopic>[
        topic(1, TopicType.singleChoice, options: options),
      ]);

      final result = DraftPrefillMapper.map(
        definition: definition,
        answers: <int, String>{1: '19:00'},
      );

      expect(result.prefill, isEmpty);
      expect(result.unresolved[1], '19:00');
    });
  });

  group('複選題', () {
    final options = <TopicOption>[
      const TopicOption(id: 41, optionName: '直立式'),
      const TopicOption(id: 42, optionName: '滾筒式'),
    ];

    test('逗號分隔轉成多個選項', () {
      final definition = definitionOf(<FormTopic>[
        topic(1, TopicType.multiChoice, options: options),
      ]);

      final result = DraftPrefillMapper.map(
        definition: definition,
        answers: <int, String>{1: '直立式,滾筒式'},
      );

      final answer = result.prefill[1]! as OptionListAnswer;
      expect(answer.options.map((o) => o.optionId), <int>[41, 42]);
    });

    test('全形逗號與頓號也接受（模型實測會混用）', () {
      final definition = definitionOf(<FormTopic>[
        topic(1, TopicType.multiChoice, options: options),
      ]);

      final result = DraftPrefillMapper.map(
        definition: definition,
        answers: <int, String>{1: '直立式、滾筒式'},
      );

      expect((result.prefill[1]! as OptionListAnswer).options.length, 2);
    });

    test('只要有一項對不上就整題不填，不做半套', () {
      final definition = definitionOf(<FormTopic>[
        topic(1, TopicType.multiChoice, options: options),
      ]);

      final result = DraftPrefillMapper.map(
        definition: definition,
        answers: <int, String>{1: '直立式,雙槽式'},
      );

      expect(result.prefill, isEmpty);
      expect(result.unresolved[1], '直立式,雙槽式');
    });
  });

  group('日期題', () {
    test('YYYY-MM-DD 轉成 DateAnswer 且不帶時間', () {
      final definition = definitionOf(<FormTopic>[topic(1, TopicType.date)]);

      final result = DraftPrefillMapper.map(
        definition: definition,
        answers: <int, String>{1: '2026-08-05'},
      );

      expect(result.prefill[1], DateAnswer(DateTime(2026, 8, 5)));
    });

    test('格式不對時進 unresolved', () {
      final definition = definitionOf(<FormTopic>[topic(1, TopicType.date)]);

      final result = DraftPrefillMapper.map(
        definition: definition,
        answers: <int, String>{1: '下週五'},
      );

      expect(result.prefill, isEmpty);
      expect(result.unresolved[1], '下週五');
    });
  });

  group('管家填不了的題型', () {
    test('地區題一律不填：管家給名稱，表單要區碼', () {
      final definition = definitionOf(<FormTopic>[topic(1, TopicType.region)]);

      final result = DraftPrefillMapper.map(
        definition: definition,
        answers: <int, String>{1: '台北市 大安區'},
      );

      expect(result.prefill, isEmpty);
      expect(result.unresolved[1], '台北市 大安區');
    });

    test('照片題不填', () {
      final definition = definitionOf(<FormTopic>[topic(1, TopicType.photo)]);

      final result = DraftPrefillMapper.map(
        definition: definition,
        answers: <int, String>{1: 'photo.jpg'},
      );

      expect(result.prefill, isEmpty);
    });

    test('備註說明題不收集作答值', () {
      final definition = definitionOf(<FormTopic>[topic(1, TopicType.notice)]);

      final result = DraftPrefillMapper.map(
        definition: definition,
        answers: <int, String>{1: '任何東西'},
      );

      expect(result.prefill, isEmpty);
      expect(result.unresolved, isEmpty);
    });
  });

  group('聯絡資料題', () {
    test('從 payload 頂層欄位組成，不看逐題答案', () {
      final definition = definitionOf(<FormTopic>[
        topic(1, TopicType.contactWithoutAddress),
      ]);

      final result = DraftPrefillMapper.map(
        definition: definition,
        // 模型寫進該題的答案是自由文字，不該被採用
        answers: <int, String>{1: '王小明 0912345678'},
        payload: <String, dynamic>{
          'contact_name': '王小明',
          'contact_mobile': '0912345678',
          'contact_email': 'a@example.com',
        },
      );

      final contact = result.prefill[1]! as ContactAnswer;
      expect(contact.name, '王小明');
      expect(contact.mobile, '0912345678');
      expect(contact.email, 'a@example.com');
      expect(contact.includesAddress, isFalse);
    });

    test('題型 08 標記為含地址', () {
      final definition = definitionOf(<FormTopic>[
        topic(1, TopicType.contactWithAddress),
      ]);

      final result = DraftPrefillMapper.map(
        definition: definition,
        answers: const <int, String>{},
        payload: <String, dynamic>{
          'contact_name': '王小明',
          'contact_mobile': '0912345678',
        },
      );

      expect((result.prefill[1]! as ContactAnswer).includesAddress, isTrue);
    });

    test('payload 沒有聯絡資訊時不填', () {
      final definition = definitionOf(<FormTopic>[
        topic(1, TopicType.contactWithoutAddress),
      ]);

      final result = DraftPrefillMapper.map(
        definition: definition,
        answers: const <int, String>{},
      );

      expect(result.prefill, isEmpty);
    });
  });

  test('答案的 topic_id 不在表單裡就忽略（模型可能傳舊表單的 id）', () {
    final definition = definitionOf(<FormTopic>[topic(1, TopicType.shortText)]);

    final result = DraftPrefillMapper.map(
      definition: definition,
      answers: <int, String>{1: '有效', 999: '不存在的題目'},
    );

    expect(result.prefill.keys, <int>[1]);
    expect(result.unresolved, isEmpty);
  });
}
