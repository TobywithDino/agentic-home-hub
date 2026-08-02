import 'package:flutter/widgets.dart';

import 'package:ai_butler_app/domain/logic/draft_prefill_mapper.dart';
import 'package:ai_butler_app/domain/models/form_definition.dart';
import 'package:ai_butler_app/domain/models/topic_type.dart';
import 'package:ai_butler_app/features/tour/tour_step.dart';

/// 依表單定義與預填結果，當場生成導覽步驟。
///
/// **刻意不用「服務類型 → 固定步驟」的對照表。** 表單是動態的
/// （`pms_form` 系列決定題目），全 App 只有一個通用填單頁 `/forms/{formId}`，
/// 題目數量與型別隨商家設定而變。寫死藍圖的話每加一張表單就要改前端，
/// 而且題目一改導覽就會指到錯的位置。
///
/// 所以步驟是這樣長出來的：
///   1. 每個「管家已填好」的題目一步，說明它填了什麼、為什麼
///   2. 每個「管家填不了」的題目一步，明確請使用者自己處理
///   3. 最後一步停在送出鈕，`handOff: true` 讓使用者親手按
class TourPlan {
  const TourPlan._();

  // ------------------------------------------------------------------
  // 導航段：每段只有一步，靠使用者點擊目標前進。
  //
  // 這三段的重點不是「填什麼」，而是「下次你自己也找得到路」——
  // 所以文案要講出這個位置在哪、以後怎麼自己來，而不只是「點這裡」。
  // ------------------------------------------------------------------

  /// 首頁 → 服務商列表。
  static List<TourStep> homeLeg({
    required GlobalKey categoryAnchor,
    required String categoryName,
    required VoidCallback onTap,
  }) {
    return <TourStep>[
      TourStep(
        anchorKey: categoryAnchor,
        title: '從首頁開始',
        instruction: '你剛剛跟我說的需求，對應到首頁的「$categoryName」。'
            '以後你也可以直接從這裡進來，不用先跟我說。',
        onTap: onTap,
      ),
    ];
  }

  /// 服務商列表 → 商家詳情。
  static List<TourStep> vendorListLeg({
    required GlobalKey vendorAnchor,
    required String vendorName,
    required VoidCallback onTap,
  }) {
    return <TourStep>[
      TourStep(
        anchorKey: vendorAnchor,
        title: '選服務商',
        instruction: '這裡會列出所有提供這項服務的店家，'
            '「$vendorName」就是我剛剛推薦給你的那一家。'
            '上面的篩選條件可以再縮小範圍。',
        onTap: onTap,
      ),
    ];
  }

  /// 商家詳情 → 填單頁。
  static List<TourStep> vendorDetailLeg({
    required GlobalKey submitAnchor,
    required VoidCallback onTap,
  }) {
    return <TourStep>[
      TourStep(
        anchorKey: submitAnchor,
        title: '開始填單',
        instruction: '這頁可以看服務介紹跟其他人的評價。'
            '確定要約就按這裡開始填諮詢單 —— 我已經幫你把答案準備好了。',
        onTap: onTap,
      ),
    ];
  }

  static List<TourStep> forForm({
    required FormDefinition definition,
    required DraftPrefillResult prefill,
    required Map<int, GlobalKey> topicAnchors,
    required GlobalKey submitAnchor,
  }) {
    final steps = <TourStep>[];

    for (final topic in definition.allTopics) {
      if (!topic.type.collectsAnswer) continue;

      final anchor = topicAnchors[topic.topicId];
      if (anchor == null) continue;

      final filled = prefill.prefill[topic.topicId];
      final unresolvedRaw = prefill.unresolved[topic.topicId];

      if (filled != null) {
        steps.add(TourStep(
          anchorKey: anchor,
          title: topic.title,
          instruction: _filledInstruction(topic, filled.toJson()),
        ));
        continue;
      }

      // 沒填的題目：必填的一定要提，選填的就不要打擾使用者。
      if (unresolvedRaw != null) {
        steps.add(TourStep(
          anchorKey: anchor,
          title: topic.title,
          instruction: _unresolvedInstruction(topic, unresolvedRaw),
        ));
      } else if (topic.isRequired) {
        steps.add(TourStep(
          anchorKey: anchor,
          title: topic.title,
          instruction: _missingInstruction(topic),
        ));
      }
    }

    steps.add(TourStep(
      anchorKey: submitAnchor,
      title: '最後一步',
      instruction: steps.isEmpty
          ? '確認內容沒問題後，按這裡送出。'
          : '確認上面的內容沒問題就按這裡送出。這一步我不幫你按 —— '
              '送出之後就會真的成立，要你自己確認過才算。',
      handOff: true,
    ));

    return List<TourStep>.unmodifiable(steps);
  }

  /// 管家已填好的題目。
  static String _filledInstruction(FormTopic topic, Object? serialized) {
    final shown = _describe(topic, serialized);
    final base = shown.isEmpty
        ? '這題我已經幫你填好了。'
        : '這題我填的是「$shown」。';

    return switch (topic.type) {
      TopicType.singleChoice || TopicType.multiChoice =>
        '$base點一下可以換成別的選項，這裡只會列出這家實際提供的項目。',
      TopicType.date => '$base點一下可以改日期。',
      TopicType.contactWithAddress =>
        '$base這是你帳號裡的聯絡資料，要換人聯絡就改這裡。地址請你自己選一下。',
      TopicType.contactWithoutAddress =>
        '$base這是你帳號裡的聯絡資料，要換人聯絡就改這裡。',
      _ => '$base不對的話直接改。',
    };
  }

  /// 管家有答案但轉不成合法作答值。
  static String _unresolvedInstruction(FormTopic topic, String raw) {
    if (topic.type == TopicType.region) {
      return '你剛剛提到「$raw」，但地區要從選單挑才對得上系統的區碼，'
          '這題麻煩你自己選一下。';
    }
    return '你剛剛提到「$raw」，但它對不上這題的選項，我不敢幫你亂填，'
        '這題請你自己選。';
  }

  /// 管家完全填不了的題目。
  static String _missingInstruction(FormTopic topic) {
    if (topic.type == TopicType.photo) {
      return '照片我沒辦法幫你上傳，這題請你自己加。';
    }
    return '這題我沒有你的資料可以填，麻煩你補一下，它是必填的。';
  }

  /// 把序列化後的作答值講成人話。
  ///
  /// 選項題序列化後是 `{option_id: 41, quantity: 1}`，直接顯示 id 對使用者
  /// 毫無意義，要回頭查 `option_name`。
  static String _describe(FormTopic topic, Object? serialized) {
    if (serialized == null) return '';

    if (topic.type == TopicType.singleChoice && serialized is Map) {
      return topic.optionById(serialized['option_id'] as int? ?? -1)?.optionName ?? '';
    }

    if (topic.type == TopicType.multiChoice && serialized is List) {
      final names = <String>[];
      for (final item in serialized) {
        if (item is! Map) continue;
        final name = topic.optionById(item['option_id'] as int? ?? -1)?.optionName;
        if (name != null) names.add(name);
      }
      return names.join('、');
    }

    if (topic.type.isContact && serialized is Map) {
      final name = serialized['name'] as String? ?? '';
      final mobile = serialized['mobile'] as String? ?? '';
      return [name, mobile].where((s) => s.isNotEmpty).join(' ');
    }

    if (serialized is String) return serialized;
    return '';
  }
}
