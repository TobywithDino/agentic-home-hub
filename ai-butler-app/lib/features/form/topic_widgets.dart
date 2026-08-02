import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:ai_butler_app/core/data/tw_regions.dart';
import 'package:ai_butler_app/design_system/app_spacing.dart';
import 'package:ai_butler_app/design_system/app_typography.dart';
import 'package:ai_butler_app/design_system/theme_extensions.dart';
import 'package:ai_butler_app/domain/models/answer_value.dart';
import 'package:ai_butler_app/domain/models/form_definition.dart';
import 'package:ai_butler_app/domain/models/topic_type.dart';

/// 動態表單題目渲染（Requirement 7）。
///
/// 每種題型一個 build 函式，由 [buildTopicWidget] 依 [TopicType] 分派
/// （design.md「渲染註冊表」）。未支援題型渲染成提示卡並繼續渲染其餘題目
/// （Requirement 7.18）。
class TopicFieldParams {
  const TopicFieldParams({
    required this.topic,
    required this.answer,
    required this.errorMessage,
    required this.onChanged,
    this.anchorKey,
  });

  final FormTopic topic;
  final AnswerValue? answer;
  final String? errorMessage;
  final void Function(AnswerValue? value) onChanged;

  /// AI 管家導覽用的錨點（`TourRunner` 依它定位光圈）。
  ///
  /// 掛在題目最外層的容器上，讓光圈把「題目標題 + 輸入元件 + 錯誤訊息」
  /// 整塊圈起來，使用者才看得懂在講哪一題。非導覽情境傳 null 即可。
  final GlobalKey? anchorKey;
}

Widget buildTopicWidget(BuildContext context, TopicFieldParams params) {
  final topic = params.topic;

  final field = switch (topic.type) {
    TopicType.shortText || TopicType.longText => _TextField(params: params),
    TopicType.singleChoice => _SingleChoiceField(params: params),
    TopicType.multiChoice => _MultiChoiceField(params: params),
    TopicType.region => _RegionField(params: params),
    TopicType.photo => _PhotoField(params: params),
    TopicType.notice => _NoticeField(params: params),
    TopicType.contactWithAddress =>
      _ContactField(params: params, includesAddress: true),
    TopicType.contactWithoutAddress =>
      _ContactField(params: params, includesAddress: false),
    TopicType.date => _DateField(params: params),
    TopicType.unsupported => _UnsupportedField(params: params),
  };

  if (topic.type == TopicType.notice) return field;

  return Padding(
    key: params.anchorKey,
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _TopicHeader(topic: topic),
        const SizedBox(height: AppSpacing.xs),
        field,
        if (params.errorMessage != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            params.errorMessage!,
            style: AppTypography.caption.copyWith(color: context.butler.error),
          ),
        ],
      ],
    ),
  );
}

class _TopicHeader extends StatelessWidget {
  const _TopicHeader({required this.topic});

  final FormTopic topic;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text(topic.title, style: AppTypography.bodyLarge)),
            if (topic.isRequired)
              Semantics(
                label: '必填',
                child: Text('必填',
                    style: AppTypography.caption
                        .copyWith(color: context.butler.error)),
              ),
          ],
        ),
        if (topic.remark.isNotEmpty)
          Text(
            topic.remark,
            style: AppTypography.caption
                .copyWith(color: context.butler.secondaryText),
          ),
      ],
    );
  }
}

class _TextField extends StatefulWidget {
  const _TextField({required this.params});

  final TopicFieldParams params;

  @override
  State<_TextField> createState() => _TextFieldState();
}

class _TextFieldState extends State<_TextField> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final answer = widget.params.answer;
    _controller =
        TextEditingController(text: answer is TextAnswer ? answer.text : '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLong = widget.params.topic.type == TopicType.longText;
    return TextField(
      controller: _controller,
      minLines: isLong ? 4 : 1,
      maxLines: isLong ? null : 1,
      keyboardType: widget.params.topic.isNumberOnly
          ? TextInputType.number
          : TextInputType.text,
      onChanged: (value) => widget.params.onChanged(TextAnswer(value)),
    );
  }
}

class _SingleChoiceField extends StatelessWidget {
  const _SingleChoiceField({required this.params});

  final TopicFieldParams params;

  @override
  Widget build(BuildContext context) {
    final selected = params.answer is OptionAnswer
        ? (params.answer as OptionAnswer).option.optionId
        : null;
    return Column(
      children: <Widget>[
        for (final option in params.topic.sortedOptions)
          RadioListTile<int>(
            value: option.id,
            groupValue: selected,
            title: Text(_optionLabel(option)),
            subtitle: option.remark.isNotEmpty ? Text(option.remark) : null,
            onChanged: (value) {
              if (value == null) return;
              params.onChanged(OptionAnswer(SelectedOption(optionId: value)));
            },
          ),
      ],
    );
  }
}

class _MultiChoiceField extends StatelessWidget {
  const _MultiChoiceField({required this.params});

  final TopicFieldParams params;

  @override
  Widget build(BuildContext context) {
    final selections = params.answer is OptionListAnswer
        ? (params.answer as OptionListAnswer).options
        : const <SelectedOption>[];
    final selectedIds = selections.map((s) => s.optionId).toSet();

    return Column(
      children: <Widget>[
        for (final option in params.topic.sortedOptions)
          CheckboxListTile(
            value: selectedIds.contains(option.id),
            title: Text(_optionLabel(option)),
            subtitle: option.remark.isNotEmpty ? Text(option.remark) : null,
            onChanged: (checked) {
              final next = List<SelectedOption>.of(selections);
              next.removeWhere((s) => s.optionId == option.id);
              if (checked == true) {
                next.add(SelectedOption(
                    optionId: option.id, quantity: option.effectiveMin));
              }
              params.onChanged(OptionListAnswer(next));
            },
          ),
      ],
    );
  }
}

String _optionLabel(TopicOption option) {
  if (option.unitPrice > 0) {
    return '${option.optionName}（NT\$${option.unitPrice}${option.unit.isNotEmpty ? '/${option.unit}' : ''}）';
  }
  return option.optionName;
}

/// 題型 05：縣市 / 行政區連動下拉選單。
///
/// 資料來自內建的 [TwRegions]（由 `sys_county` / `sys_district` 種子資料產生），
/// 送出的是 **code** 而非名稱，與 `contact_address_county` /
/// `contact_address_district` 欄位一致。
class _RegionField extends StatelessWidget {
  const _RegionField({required this.params});

  final TopicFieldParams params;

  @override
  Widget build(BuildContext context) {
    final answer = params.answer is RegionAnswer
        ? params.answer as RegionAnswer
        : const RegionAnswer();

    // 後端資料若帶了本地清單沒有的 code，視為未選以免 Dropdown 斷言失敗。
    final countyCode = TwRegions.countyName(answer.countyCode) == null
        ? null
        : answer.countyCode;
    final districts = TwRegions.districtsOf(countyCode);
    final districtCode =
        TwRegions.districtName(countyCode, answer.districtCode) == null
            ? null
            : answer.districtCode;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: DropdownButtonFormField<String>(
            value: countyCode,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: '縣市',
              isDense: true,
            ),
            hint: const Text('請選擇'),
            items: <DropdownMenuItem<String>>[
              for (final county in TwRegions.counties)
                DropdownMenuItem<String>(
                  value: county.code,
                  child: Text(county.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) {
              // 換縣市要清掉行政區，否則會留著別的縣市的區碼。
              params.onChanged(RegionAnswer(countyCode: value ?? ''));
            },
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: DropdownButtonFormField<String>(
            value: districtCode,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: '行政區',
              isDense: true,
              enabled: districts.isNotEmpty,
            ),
            hint: Text(countyCode == null ? '先選縣市' : '請選擇'),
            items: <DropdownMenuItem<String>>[
              for (final district in districts)
                DropdownMenuItem<String>(
                  value: district.code,
                  child: Text(district.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: districts.isEmpty
                ? null
                : (value) => params.onChanged(
                      answer.copyWith(
                        countyCode: countyCode ?? '',
                        districtCode: value ?? '',
                      ),
                    ),
          ),
        ),
      ],
    );
  }
}

/// 題型 06：照片上傳。
///
/// 「前端挑選、後端不存檔」的形式：照片只留在裝置上做預覽，送出時只把檔名
/// 寫進 `feedback_content`，不上傳二進位內容（平台的預簽章上傳端點
/// `/media/presign` 仍是 TODO）。
class _PhotoField extends StatefulWidget {
  const _PhotoField({required this.params});

  final TopicFieldParams params;

  @override
  State<_PhotoField> createState() => _PhotoFieldState();
}

class _PhotoFieldState extends State<_PhotoField> {
  final ImagePicker _picker = ImagePicker();
  final List<XFile> _files = <XFile>[];

  int get _maxCount {
    final topic = widget.params.topic;
    // 指定張數優先於上限；都沒設定時給合理上限避免無限選。
    return topic.specifiedMedias ?? topic.maxMedias ?? 9;
  }

  bool get _canAddMore => _files.length < _maxCount;

  Future<void> _pick(ImageSource source) async {
    try {
      if (source == ImageSource.gallery) {
        final picked = await _picker.pickMultiImage();
        if (picked.isNotEmpty) _add(picked);
      } else {
        final shot = await _picker.pickImage(source: ImageSource.camera);
        if (shot != null) _add(<XFile>[shot]);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('無法取得照片：$error')));
    }
  }

  void _add(List<XFile> picked) {
    final room = _maxCount - _files.length;
    if (room <= 0) return;
    setState(() => _files.addAll(picked.take(room)));
    _emit();

    if (picked.length > room && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('最多 $_maxCount 張，已保留前 $room 張')),
      );
    }
  }

  void _remove(int index) {
    setState(() => _files.removeAt(index));
    _emit();
  }

  /// 只回傳檔名——後端不存檔案，記錄名稱即可讓必填驗證與紀錄成立。
  void _emit() {
    widget.params.onChanged(
      MediaAnswer(_files.map((f) => f.name).toList(growable: false)),
    );
  }

  Future<void> _showSourceSheet() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('從相簿選擇'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('立即拍照'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source != null) await _pick(source);
  }

  @override
  Widget build(BuildContext context) {
    final topic = widget.params.topic;
    final hint = topic.specifiedMedias != null
        ? '需上傳 ${topic.specifiedMedias} 張'
        : <String>[
            if (topic.minMedias != null) '最少 ${topic.minMedias} 張',
            if (topic.maxMedias != null) '最多 ${topic.maxMedias} 張',
          ].join('、');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: <Widget>[
            for (int i = 0; i < _files.length; i++)
              _Thumbnail(file: _files[i], onRemove: () => _remove(i)),
            if (_canAddMore)
              InkWell(
                onTap: _showSourceSheet,
                borderRadius: AppRadius.mdAll,
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    border: Border.all(color: context.butler.border),
                    borderRadius: AppRadius.mdAll,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(Icons.add_a_photo_outlined,
                          color: context.butler.secondaryText),
                      const SizedBox(height: 2),
                      Text('新增',
                          style: AppTypography.caption
                              .copyWith(color: context.butler.secondaryText)),
                    ],
                  ),
                ),
              ),
          ],
        ),
        if (hint.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '$hint（已選 ${_files.length} 張）',
            style: AppTypography.caption
                .copyWith(color: context.butler.secondaryText),
          ),
        ],
        Text(
          '照片僅在此裝置預覽，送出時不會上傳檔案內容',
          style: AppTypography.caption
              .copyWith(color: context.butler.secondaryText),
        ),
      ],
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.file, required this.onRemove});

  final XFile file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        ClipRRect(
          borderRadius: AppRadius.mdAll,
          child: Image.file(
            File(file.path),
            width: 84,
            height: 84,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: 84,
              height: 84,
              color: context.butler.surfaceVariant,
              child: const Icon(Icons.broken_image_outlined),
            ),
          ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            shape: const CircleBorder(),
            elevation: 1,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onRemove,
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(Icons.close, size: 16),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NoticeField extends StatelessWidget {
  const _NoticeField({required this.params});

  final TopicFieldParams params;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: context.butler.surfaceVariant,
        borderRadius: AppRadius.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(params.topic.title, style: AppTypography.label),
          if (params.topic.remark.isNotEmpty)
            Text(params.topic.remark, style: AppTypography.caption),
        ],
      ),
    );
  }
}

class _ContactField extends StatefulWidget {
  const _ContactField({required this.params, required this.includesAddress});

  final TopicFieldParams params;
  final bool includesAddress;

  @override
  State<_ContactField> createState() => _ContactFieldState();
}

class _ContactFieldState extends State<_ContactField> {
  // controller 必須存活在 State：先前寫在 build() 裡每次重繪都會重建，
  // 造成游標跳回開頭、輸入內容錯亂（手機欄最明顯）。
  late final TextEditingController _name;
  late final TextEditingController _mobile;
  late final TextEditingController _email;
  late final TextEditingController _address;

  ContactAnswer get _answer {
    final value = widget.params.answer;
    return value is ContactAnswer
        ? value
        : ContactAnswer(includesAddress: widget.includesAddress);
  }

  @override
  void initState() {
    super.initState();
    final answer = _answer;
    _name = TextEditingController(text: answer.name);
    _mobile = TextEditingController(text: answer.mobile);
    _email = TextEditingController(text: answer.email);
    _address = TextEditingController(text: answer.addressDetail);
  }

  @override
  void dispose() {
    _name.dispose();
    _mobile.dispose();
    _email.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_ContactField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部（例如草稿還原）改了答案才同步，且只在值真的不同時才覆寫，
    // 否則會在使用者打字途中重設游標。
    final answer = _answer;
    _syncIfChanged(_name, answer.name);
    _syncIfChanged(_mobile, answer.mobile);
    _syncIfChanged(_email, answer.email);
    _syncIfChanged(_address, answer.addressDetail);
  }

  void _syncIfChanged(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _update(ContactAnswer next) => widget.params.onChanged(next);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: '姓名'),
          textInputAction: TextInputAction.next,
          onChanged: (v) => _update(_answer.copyWith(name: v)),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _mobile,
          // 刻意用一般鍵盤：數字鍵盤在部分機型上會干擾輸入，
          // 格式仍由 FormValidator 檢查（09 開頭共 10 位）。
          keyboardType: TextInputType.text,
          decoration: const InputDecoration(
            labelText: '手機',
            hintText: '09 開頭共 10 位數字',
          ),
          textInputAction: TextInputAction.next,
          onChanged: (v) => _update(_answer.copyWith(mobile: v)),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _email,
          keyboardType: TextInputType.text,
          decoration: const InputDecoration(labelText: 'Email'),
          textInputAction: TextInputAction.next,
          onChanged: (v) => _update(_answer.copyWith(email: v)),
        ),
        if (widget.includesAddress) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: _address,
            decoration: const InputDecoration(labelText: '詳細地址'),
            textInputAction: TextInputAction.done,
            onChanged: (v) => _update(_answer.copyWith(addressDetail: v)),
          ),
        ],
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.params});

  final TopicFieldParams params;

  @override
  Widget build(BuildContext context) {
    final answer = params.answer is DateAnswer
        ? params.answer as DateAnswer
        : const DateAnswer(null);
    final label = answer.date == null
        ? '請選擇日期'
        : '${answer.date!.year}-${answer.date!.month.toString().padLeft(2, '0')}-${answer.date!.day.toString().padLeft(2, '0')}';

    return OutlinedButton.icon(
      icon: const Icon(Icons.calendar_today_outlined),
      label: Text(label),
      onPressed: () async {
        final now = DateTime.now();
        final start =
            now.add(Duration(days: params.topic.startDateOffsetDays ?? 0));
        final end =
            now.add(Duration(days: params.topic.endDateOffsetDays ?? 30));
        final picked = await showDatePicker(
          context: context,
          initialDate: start,
          firstDate: start,
          lastDate: end.isBefore(start) ? start : end,
        );
        if (picked != null) params.onChanged(DateAnswer(picked));
      },
    );
  }
}

class _UnsupportedField extends StatelessWidget {
  const _UnsupportedField({required this.params});

  final TopicFieldParams params;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: context.butler.warningSurface,
        borderRadius: AppRadius.mdAll,
      ),
      child: Text('此題型尚未支援',
          style: AppTypography.caption.copyWith(color: context.butler.warning)),
    );
  }
}
