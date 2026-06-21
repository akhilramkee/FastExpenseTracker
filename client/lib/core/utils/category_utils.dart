import 'package:flutter/material.dart';

class CategoryStyle {
  final IconData icon;
  final Color color;

  const CategoryStyle({required this.icon, required this.color});
}

const _defaultStyle = CategoryStyle(
  icon: Icons.receipt_long_rounded,
  color: Color(0xFF94A3B8),
);

const _categoryStyles = <String, CategoryStyle>{
  'food': CategoryStyle(icon: Icons.restaurant_rounded, color: Color(0xFFF97316)),
  'groceries': CategoryStyle(icon: Icons.shopping_basket_rounded, color: Color(0xFF22C55E)),
  'coffee': CategoryStyle(icon: Icons.coffee_rounded, color: Color(0xFF92400E)),
  'dining': CategoryStyle(icon: Icons.restaurant_menu_rounded, color: Color(0xFFEA580C)),
  'transport': CategoryStyle(icon: Icons.directions_car_rounded, color: Color(0xFF3B82F6)),
  'travel': CategoryStyle(icon: Icons.flight_rounded, color: Color(0xFF06B6D4)),
  'subscription': CategoryStyle(icon: Icons.subscriptions_rounded, color: Color(0xFF8B5CF6)),
  'subscriptions': CategoryStyle(icon: Icons.subscriptions_rounded, color: Color(0xFF8B5CF6)),
  'work': CategoryStyle(icon: Icons.work_rounded, color: Color(0xFF6366F1)),
  'entertainment': CategoryStyle(icon: Icons.movie_rounded, color: Color(0xFFEC4899)),
  'shopping': CategoryStyle(icon: Icons.shopping_bag_rounded, color: Color(0xFF14B8A6)),
  'health': CategoryStyle(icon: Icons.favorite_rounded, color: Color(0xFFEF4444)),
  'fitness': CategoryStyle(icon: Icons.fitness_center_rounded, color: Color(0xFF10B981)),
  'utilities': CategoryStyle(icon: Icons.bolt_rounded, color: Color(0xFFEAB308)),
  'rent': CategoryStyle(icon: Icons.home_rounded, color: Color(0xFF78716C)),
  'housing': CategoryStyle(icon: Icons.home_rounded, color: Color(0xFF78716C)),
  'education': CategoryStyle(icon: Icons.school_rounded, color: Color(0xFF2563EB)),
  'night': CategoryStyle(icon: Icons.nightlife_rounded, color: Color(0xFFA855F7)),
  'personal': CategoryStyle(icon: Icons.person_rounded, color: Color(0xFF64748B)),
  'uncategorized': CategoryStyle(icon: Icons.label_outline_rounded, color: Color(0xFF64748B)),
};

const _merchantStyles = <String, CategoryStyle>{
  'zoom': CategoryStyle(icon: Icons.videocam_rounded, color: Color(0xFF2D8CFF)),
  'netflix': CategoryStyle(icon: Icons.live_tv_rounded, color: Color(0xFFE50914)),
  'spotify': CategoryStyle(icon: Icons.music_note_rounded, color: Color(0xFF1DB954)),
  'amazon': CategoryStyle(icon: Icons.local_shipping_rounded, color: Color(0xFFFF9900)),
  'uber': CategoryStyle(icon: Icons.local_taxi_rounded, color: Color(0xFF000000)),
  'lyft': CategoryStyle(icon: Icons.local_taxi_rounded, color: Color(0xFFDD00FF)),
  'apple': CategoryStyle(icon: Icons.phone_iphone_rounded, color: Color(0xFFA2AAAD)),
  'google': CategoryStyle(icon: Icons.cloud_rounded, color: Color(0xFF4285F4)),
};

CategoryStyle resolveCategoryStyle({
  required String tag,
  String? merchant,
}) {
  final normalizedTag = tag.toLowerCase().trim();
  if (_categoryStyles.containsKey(normalizedTag)) {
    return _categoryStyles[normalizedTag]!;
  }

  if (merchant != null) {
    final normalizedMerchant = merchant.toLowerCase().trim();
    if (_merchantStyles.containsKey(normalizedMerchant)) {
      return _merchantStyles[normalizedMerchant]!;
    }
    for (final entry in _merchantStyles.entries) {
      if (normalizedMerchant.contains(entry.key)) {
        return entry.value;
      }
    }
  }

  for (final entry in _categoryStyles.entries) {
    if (normalizedTag.contains(entry.key)) {
      return entry.value;
    }
  }

  return _defaultStyle;
}

String displayCategoryLabel({
  required String tag,
  String? merchant,
}) {
  if (merchant != null && merchant.isNotEmpty && merchant.toLowerCase() != tag.toLowerCase()) {
    return merchant;
  }
  return tag;
}
