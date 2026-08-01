import 'package:flutter/material.dart';

import 'package:ai_butler_app/design_system/app_colors.dart';
import 'package:ai_butler_app/design_system/app_spacing.dart';
import 'package:ai_butler_app/design_system/app_typography.dart';
import 'package:ai_butler_app/domain/models/domain_models.dart';

/// 服務類別圖示對照（附錄 A）。
IconData categoryIcon(String type) {
  return switch (type) {
    '01' => Icons.cleaning_services_outlined,
    '02' => Icons.ac_unit_outlined,
    '03' => Icons.local_shipping_outlined,
    '06' => Icons.restaurant_outlined,
    '09' => Icons.delivery_dining_outlined,
    '10' => Icons.plumbing_outlined,
    '11' => Icons.shopping_bag_outlined,
    _ => Icons.apps_outlined,
  };
}

/// 首頁服務類別磁磚（Requirement 4.7）。
class ServiceCategoryTile extends StatelessWidget {
  const ServiceCategoryTile({
    super.key,
    required this.category,
    required this.onTap,
    this.onLongPress,
  });

  final ServiceCategory category;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.categoryColor(category.type);
    final surface = AppColors.categorySurface(category.type);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: AppRadius.mdAll,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: surface, shape: BoxShape.circle),
            child: Icon(categoryIcon(category.type), color: color, size: 26),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            category.name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption,
          ),
        ],
      ),
    );
  }
}
