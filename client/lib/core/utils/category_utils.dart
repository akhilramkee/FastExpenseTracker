import 'package:flutter/material.dart';

import 'categories.dart';

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
  'groceries': CategoryStyle(icon: Icons.shopping_basket_rounded, color: Color(0xFF22C55E)),
  'food': CategoryStyle(icon: Icons.restaurant_rounded, color: Color(0xFFF97316)),
  'travel': CategoryStyle(icon: Icons.flight_rounded, color: Color(0xFF06B6D4)),
  'transport': CategoryStyle(icon: Icons.directions_car_rounded, color: Color(0xFF3B82F6)),
  'healthcare': CategoryStyle(icon: Icons.medical_services_rounded, color: Color(0xFFEF4444)),
  'subscriptions': CategoryStyle(icon: Icons.subscriptions_rounded, color: Color(0xFF8B5CF6)),
  'gifts': CategoryStyle(icon: Icons.card_giftcard_rounded, color: Color(0xFFEC4899)),
  'charity': CategoryStyle(icon: Icons.volunteer_activism_rounded, color: Color(0xFFF59E0B)),
  'communication': CategoryStyle(icon: Icons.phone_android_rounded, color: Color(0xFF0EA5E9)),
  'utilities': CategoryStyle(icon: Icons.bolt_rounded, color: Color(0xFFEAB308)),
  'entertainment': CategoryStyle(icon: Icons.movie_rounded, color: Color(0xFFA855F7)),
  'shopping': CategoryStyle(icon: Icons.shopping_bag_rounded, color: Color(0xFF14B8A6)),
  'work': CategoryStyle(icon: Icons.work_rounded, color: Color(0xFF6366F1)),
  'education': CategoryStyle(icon: Icons.school_rounded, color: Color(0xFF2563EB)),
  'housing': CategoryStyle(icon: Icons.home_rounded, color: Color(0xFF78716C)),
  'personal': CategoryStyle(icon: Icons.person_rounded, color: Color(0xFF64748B)),
  'fitness': CategoryStyle(icon: Icons.fitness_center_rounded, color: Color(0xFF10B981)),
  'uncategorized': CategoryStyle(icon: Icons.label_outline_rounded, color: Color(0xFF64748B)),
};

const _merchantStyles = <String, CategoryStyle>{
  'zoom': CategoryStyle(icon: Icons.videocam_rounded, color: Color(0xFF2D8CFF)),
  'netflix': CategoryStyle(icon: Icons.live_tv_rounded, color: Color(0xFFE50914)),
  'spotify': CategoryStyle(icon: Icons.music_note_rounded, color: Color(0xFF1DB954)),
  'amazon': CategoryStyle(icon: Icons.local_shipping_rounded, color: Color(0xFFFF9900)),
  'uber': CategoryStyle(icon: Icons.local_taxi_rounded, color: Color(0xFF111827)),
  'lyft': CategoryStyle(icon: Icons.local_taxi_rounded, color: Color(0xFFDD00FF)),
  'rapido': CategoryStyle(icon: Icons.two_wheeler_rounded, color: Color(0xFFFFC107)),
  'redbus': CategoryStyle(icon: Icons.directions_bus_rounded, color: Color(0xFFD32F2F)),
  'irctc': CategoryStyle(icon: Icons.train_rounded, color: Color(0xFF1565C0)),
  'airbnb': CategoryStyle(icon: Icons.house_rounded, color: Color(0xFFFF5A5F)),
  'airtel': CategoryStyle(icon: Icons.sim_card_rounded, color: Color(0xFFE40000)),
  'jio': CategoryStyle(icon: Icons.sim_card_rounded, color: Color(0xFF0A2885)),
  'cursor': CategoryStyle(icon: Icons.code_rounded, color: Color(0xFF8B5CF6)),
  'google': CategoryStyle(icon: Icons.cloud_rounded, color: Color(0xFF4285F4)),
  'apple': CategoryStyle(icon: Icons.phone_iphone_rounded, color: Color(0xFFA2AAAD)),
  'zee5': CategoryStyle(icon: Icons.live_tv_rounded, color: Color(0xFF6C2BD9)),
};

CategoryStyle resolveCategoryStyle({
  required String tag,
  String? merchant,
}) {
  final normalizedTag = normalizeCategory(tag);
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

  return _defaultStyle;
}

String displayCategoryLabel({
  required String tag,
  String? merchant,
}) {
  if (merchant != null && merchant.isNotEmpty && merchant.toLowerCase() != tag.toLowerCase()) {
    return merchant;
  }
  return formatCategoryLabel(tag);
}
