import 'package:flutter/material.dart';

import 'package:ai_butler_app/data/mock/mock_seed_data.dart';
import 'package:ai_butler_app/design_system/app_spacing.dart';
import 'package:ai_butler_app/design_system/app_typography.dart';
import 'package:ai_butler_app/domain/models/domain_models.dart';

/// 服務商列表的篩選面板（Requirement 5.7-16）。
///
/// 以 `showModalBottomSheet` 呈現，使用者選好後按「套用」回傳新的 [VendorQuery]。
/// 依 [VendorCapabilities] 決定是否顯示評分/價格/可服務三項篩選。
class VendorFilterPanel extends StatefulWidget {
  const VendorFilterPanel({
    super.key,
    required this.currentQuery,
    required this.capabilities,
  });

  final VendorQuery currentQuery;
  final VendorCapabilities capabilities;

  /// 顯示篩選面板，回傳使用者確認的新 query，或 null（取消）。
  static Future<VendorQuery?> show(
    BuildContext context, {
    required VendorQuery currentQuery,
    required VendorCapabilities capabilities,
  }) {
    return showModalBottomSheet<VendorQuery>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => VendorFilterPanel(
        currentQuery: currentQuery,
        capabilities: capabilities,
      ),
    );
  }

  @override
  State<VendorFilterPanel> createState() => _VendorFilterPanelState();
}

class _VendorFilterPanelState extends State<VendorFilterPanel> {
  late String? _countyCode;
  late String? _districtCode;
  late double? _minRating;
  late bool _availableOnly;
  late List<String> _selectedTags;
  late VendorSortOption _sort;

  @override
  void initState() {
    super.initState();
    _countyCode = widget.currentQuery.countyCode;
    _districtCode = widget.currentQuery.districtCode;
    _minRating = widget.currentQuery.minRating;
    _availableOnly = widget.currentQuery.availableOnly;
    _selectedTags = List<String>.of(widget.currentQuery.selectedTags);
    _sort = widget.currentQuery.sort;
  }

  void _apply() {
    final updated = widget.currentQuery.copyWith(
      countyCode: _countyCode,
      clearCounty: _countyCode == null,
      districtCode: _districtCode,
      clearDistrict: _districtCode == null,
      minRating: _minRating,
      clearMinRating: _minRating == null,
      availableOnly: _availableOnly,
      selectedTags: _selectedTags,
      sort: _sort,
      page: 1, // 套用後回到第一頁（Requirement 5.14）
    );
    Navigator.of(context).pop(updated);
  }

  void _reset() {
    setState(() {
      _countyCode = null;
      _districtCode = null;
      _minRating = null;
      _availableOnly = false;
      _selectedTags = [];
      _sort = VendorSortOption.recommended;
    });
  }

  @override
  Widget build(BuildContext context) {
    final districts = _countyCode == null
        ? const <(String, String)>[]
        : (MockSeedData.districtsByCounty[_countyCode] ??
            const <(String, String)>[]);

    // 可用標籤清單（實際由後端依服務類型提供，此處 mock 固定清單）
    const allTags = <String>[
      '提供女技師',
      '可帶寵物',
      '可指定時段',
      '當日預約',
      '免費估價',
      '24H急修',
      '原廠認證',
      '環保清潔劑',
      '到府服務',
      '免運費',
    ];
    // 只顯示前 6 個最常見的（避免畫面太擠）
    final availableTags = allTags.take(6).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: ListView(
          controller: scrollController,
          children: <Widget>[
            // 標題列
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text('篩選條件', style: AppTypography.title),
                TextButton(onPressed: _reset, child: const Text('重置')),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            // 縣市（Requirement 5.12-13）
            Text('服務地區', style: AppTypography.label),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              children: <Widget>[
                for (final county in MockSeedData.counties)
                  ChoiceChip(
                    label: Text(county.$2),
                    selected: _countyCode == county.$1,
                    onSelected: (selected) {
                      setState(() {
                        _countyCode = selected ? county.$1 : null;
                        _districtCode = null; // 切換縣市時清除行政區
                      });
                    },
                  ),
              ],
            ),

            // 行政區（依所選縣市過濾，Requirement 5.12）
            if (districts.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text('行政區', style: AppTypography.label),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xs,
                children: <Widget>[
                  for (final district in districts)
                    ChoiceChip(
                      label: Text(district.$2),
                      selected: _districtCode == district.$1,
                      onSelected: (selected) {
                        setState(() =>
                            _districtCode = selected ? district.$1 : null);
                      },
                    ),
                ],
              ),
            ],

            // 標籤篩選（如：提供女技師、可帶寵物等）
            const SizedBox(height: AppSpacing.md),
            Text('服務標籤', style: AppTypography.label),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xxs,
              children: <Widget>[
                for (final tag in availableTags)
                  FilterChip(
                    label: Text(tag),
                    selected: _selectedTags.contains(tag),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedTags.add(tag);
                        } else {
                          _selectedTags.remove(tag);
                        }
                      });
                    },
                  ),
              ],
            ),

            // 評分下限（Requirement 5.8：僅在後端提供評分欄位時顯示）
            if (widget.capabilities.hasRating) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Text('最低評分', style: AppTypography.label),
              Slider(
                value: _minRating ?? 0,
                min: 0,
                max: 5,
                divisions: 10,
                label:
                    _minRating == null ? '不限' : _minRating!.toStringAsFixed(1),
                onChanged: (v) =>
                    setState(() => _minRating = v <= 0 ? null : v),
              ),
            ],

            // 僅顯示可服務（Requirement 5.10）
            if (widget.capabilities.hasAvailability) ...<Widget>[
              SwitchListTile(
                title: const Text('僅顯示目前可服務'),
                value: _availableOnly,
                onChanged: (v) => setState(() => _availableOnly = v),
              ),
            ],

            // 排序（Requirement 5.16）
            const SizedBox(height: AppSpacing.md),
            Text('排序方式', style: AppTypography.label),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              children: <Widget>[
                ChoiceChip(
                  label: const Text('推薦'),
                  selected: _sort == VendorSortOption.recommended,
                  onSelected: (_) =>
                      setState(() => _sort = VendorSortOption.recommended),
                ),
                if (widget.capabilities.hasRating)
                  ChoiceChip(
                    label: const Text('評分由高至低'),
                    selected: _sort == VendorSortOption.ratingDesc,
                    onSelected: (_) =>
                        setState(() => _sort = VendorSortOption.ratingDesc),
                  ),
                if (widget.capabilities.hasPriceRange)
                  ChoiceChip(
                    label: const Text('價格由低至高'),
                    selected: _sort == VendorSortOption.priceAsc,
                    onSelected: (_) =>
                        setState(() => _sort = VendorSortOption.priceAsc),
                  ),
              ],
            ),

            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: _apply,
              child: const Text('套用篩選'),
            ),
          ],
        ),
      ),
    );
  }
}
