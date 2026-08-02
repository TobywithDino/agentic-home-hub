import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_butler_app/design_system/app_spacing.dart';
import 'package:ai_butler_app/design_system/app_typography.dart';
import 'package:ai_butler_app/domain/models/domain_models.dart';
import 'package:ai_butler_app/providers/label_providers.dart';

/// 服務商列表的篩選面板（Requirement 5.7-16）。
///
/// 以 `showModalBottomSheet` 呈現，使用者選好後按「套用」回傳新的 [VendorQuery]。
/// 標籤從 `GET /app-api/labels?service_type=...` 動態載入。
class VendorFilterPanel extends ConsumerStatefulWidget {
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
  ConsumerState<VendorFilterPanel> createState() => _VendorFilterPanelState();
}

class _VendorFilterPanelState extends ConsumerState<VendorFilterPanel> {
  late double? _minRating;
  late bool _availableOnly;
  late List<String> _selectedTags; // 存放 label id 的字串形式
  late VendorSortOption _sort;

  @override
  void initState() {
    super.initState();
    _minRating = widget.currentQuery.minRating;
    _availableOnly = widget.currentQuery.availableOnly;
    _selectedTags = List<String>.of(widget.currentQuery.selectedTags);
    _sort = widget.currentQuery.sort;
  }

  void _apply() {
    final updated = widget.currentQuery.copyWith(
      minRating: _minRating,
      clearMinRating: _minRating == null,
      availableOnly: _availableOnly,
      selectedTags: _selectedTags,
      sort: _sort,
      page: 1,
    );
    Navigator.of(context).pop(updated);
  }

  void _reset() {
    setState(() {
      _minRating = null;
      _availableOnly = false;
      _selectedTags = [];
      _sort = VendorSortOption.recommended;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 依當前服務類型載入標籤
    final serviceType = widget.currentQuery.serviceId?.toString();
    final labelsAsync = ref.watch(labelsProvider(serviceType));

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
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
                const Text('篩選條件', style: AppTypography.title),
                TextButton(onPressed: _reset, child: const Text('重置')),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            // 服務標籤（從 API 動態載入）
            const Text('服務標籤', style: AppTypography.label),
            const SizedBox(height: AppSpacing.xs),
            labelsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Center(
                    child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )),
              ),
              error: (_, __) => const Text('標籤載入失敗'),
              data: (labels) {
                if (labels.isEmpty) {
                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    child: Text(
                      '此服務類型沒有可篩選的標籤',
                      style: AppTypography.caption.copyWith(
                          color: Theme.of(context).colorScheme.outline),
                    ),
                  );
                }
                return Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xxs,
                  children: <Widget>[
                    for (final label in labels)
                      FilterChip(
                        label: Text(label.name),
                        selected: _selectedTags.contains(label.id.toString()),
                        onSelected: (selected) {
                          setState(() {
                            final idStr = label.id.toString();
                            if (selected) {
                              _selectedTags.add(idStr);
                            } else {
                              _selectedTags.remove(idStr);
                            }
                          });
                        },
                      ),
                  ],
                );
              },
            ),

            // 評分下限（僅在後端提供評分欄位時顯示）
            if (widget.capabilities.hasRating) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              const Text('最低評分', style: AppTypography.label),
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

            // 僅顯示可服務
            if (widget.capabilities.hasAvailability)
              SwitchListTile(
                title: const Text('僅顯示目前可服務'),
                value: _availableOnly,
                onChanged: (v) => setState(() => _availableOnly = v),
              ),

            // 排序
            const SizedBox(height: AppSpacing.md),
            const Text('排序方式', style: AppTypography.label),
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
