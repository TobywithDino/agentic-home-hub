import 'package:flutter/foundation.dart';

/// 作答值模型。每個變體對應 requirements 附錄 C 的一種 `value` 型別。
sealed class AnswerValue {
  const AnswerValue();

  /// 是否視為「已作答」。必填驗證用（Requirement 8.1）。
  bool get isFilled;

  /// 序列化為 JSON 可承載的值（Requirement 9.3-4）。
  Object? toJson();
}

/// 題型 01 / 02：字串。
class TextAnswer extends AnswerValue {
  const TextAnswer(this.text);

  final String text;

  @override
  bool get isFilled => text.trim().isNotEmpty;

  @override
  Object? toJson() => text;

  @override
  bool operator ==(Object other) =>
      other is TextAnswer && other.text == text;

  @override
  int get hashCode => text.hashCode;
}

/// 選項 + 數量。`is_quantity` 為 false 時 quantity 固定為 1。
@immutable
class SelectedOption {
  const SelectedOption({required this.optionId, this.quantity = 1});

  final int optionId;
  final int quantity;

  Map<String, Object?> toJson() => <String, Object?>{
        'option_id': optionId,
        'quantity': quantity,
      };

  SelectedOption copyWith({int? optionId, int? quantity}) => SelectedOption(
        optionId: optionId ?? this.optionId,
        quantity: quantity ?? this.quantity,
      );

  @override
  bool operator ==(Object other) =>
      other is SelectedOption &&
      other.optionId == optionId &&
      other.quantity == quantity;

  @override
  int get hashCode => Object.hash(optionId, quantity);
}

/// 題型 03：單一選項物件。
class OptionAnswer extends AnswerValue {
  const OptionAnswer(this.option);

  final SelectedOption option;

  @override
  bool get isFilled => true;

  @override
  Object? toJson() => option.toJson();

  @override
  bool operator ==(Object other) =>
      other is OptionAnswer && other.option == option;

  @override
  int get hashCode => option.hashCode;
}

/// 題型 04：選項物件陣列。
class OptionListAnswer extends AnswerValue {
  const OptionListAnswer(this.options);

  final List<SelectedOption> options;

  @override
  bool get isFilled => options.isNotEmpty;

  @override
  Object? toJson() =>
      options.map((o) => o.toJson()).toList(growable: false);

  @override
  bool operator ==(Object other) =>
      other is OptionListAnswer && listEquals(other.options, options);

  @override
  int get hashCode => Object.hashAll(options);
}

/// 題型 05：縣市 + 行政區。
class RegionAnswer extends AnswerValue {
  const RegionAnswer({this.countyCode = '', this.districtCode = ''});

  final String countyCode;
  final String districtCode;

  @override
  bool get isFilled => countyCode.isNotEmpty && districtCode.isNotEmpty;

  @override
  Object? toJson() => <String, Object?>{
        'county_code': countyCode,
        'district_code': districtCode,
      };

  RegionAnswer copyWith({String? countyCode, String? districtCode}) =>
      RegionAnswer(
        countyCode: countyCode ?? this.countyCode,
        districtCode: districtCode ?? this.districtCode,
      );

  @override
  bool operator ==(Object other) =>
      other is RegionAnswer &&
      other.countyCode == countyCode &&
      other.districtCode == districtCode;

  @override
  int get hashCode => Object.hash(countyCode, districtCode);
}

/// 題型 06：檔案識別碼陣列。
class MediaAnswer extends AnswerValue {
  const MediaAnswer(this.fileIds);

  final List<String> fileIds;

  @override
  bool get isFilled => fileIds.isNotEmpty;

  @override
  Object? toJson() => List<String>.unmodifiable(fileIds);

  @override
  bool operator ==(Object other) =>
      other is MediaAnswer && listEquals(other.fileIds, fileIds);

  @override
  int get hashCode => Object.hashAll(fileIds);
}

/// 題型 08 / 10：聯絡資料物件。
class ContactAnswer extends AnswerValue {
  const ContactAnswer({
    this.name = '',
    this.mobile = '',
    this.landline = '',
    this.email = '',
    this.countyCode = '',
    this.districtCode = '',
    this.addressDetail = '',
    this.includesAddress = true,
  });

  final String name;
  final String mobile;
  final String landline;
  final String email;
  final String countyCode;
  final String districtCode;
  final String addressDetail;

  /// 對應題型 08（true）與題型 10（false）。
  final bool includesAddress;

  /// 姓名與手機為聯絡的最低要求。
  @override
  bool get isFilled => name.trim().isNotEmpty && mobile.trim().isNotEmpty;

  @override
  Object? toJson() {
    final json = <String, Object?>{
      'name': name,
      'mobile': mobile,
      'landline': landline,
      'email': email,
    };
    if (includesAddress) {
      json['county_code'] = countyCode;
      json['district_code'] = districtCode;
      json['address_detail'] = addressDetail;
    }
    return json;
  }

  ContactAnswer copyWith({
    String? name,
    String? mobile,
    String? landline,
    String? email,
    String? countyCode,
    String? districtCode,
    String? addressDetail,
    bool? includesAddress,
  }) {
    return ContactAnswer(
      name: name ?? this.name,
      mobile: mobile ?? this.mobile,
      landline: landline ?? this.landline,
      email: email ?? this.email,
      countyCode: countyCode ?? this.countyCode,
      districtCode: districtCode ?? this.districtCode,
      addressDetail: addressDetail ?? this.addressDetail,
      includesAddress: includesAddress ?? this.includesAddress,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ContactAnswer &&
      other.name == name &&
      other.mobile == mobile &&
      other.landline == landline &&
      other.email == email &&
      other.countyCode == countyCode &&
      other.districtCode == districtCode &&
      other.addressDetail == addressDetail &&
      other.includesAddress == includesAddress;

  @override
  int get hashCode => Object.hash(
        name,
        mobile,
        landline,
        email,
        countyCode,
        districtCode,
        addressDetail,
        includesAddress,
      );
}

/// 題型 09：`YYYY-MM-DD` 日期字串。
class DateAnswer extends AnswerValue {
  const DateAnswer(this.date);

  final DateTime? date;

  @override
  bool get isFilled => date != null;

  @override
  Object? toJson() {
    final value = date;
    if (value == null) return null;
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  @override
  bool operator ==(Object other) => other is DateAnswer && other.date == date;

  @override
  int get hashCode => date.hashCode;
}
