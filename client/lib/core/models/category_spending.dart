import '../utils/category_utils.dart';

/// Spending aggregated for a single category within a time period.
class CategorySpending {
  final String category;
  final double total;
  final int count;

  const CategorySpending({
    required this.category,
    required this.total,
    required this.count,
  });

  CategoryStyle get style => resolveCategoryStyle(tag: category);

  double shareOf(double grandTotal) {
    if (grandTotal <= 0) return 0;
    return (total / grandTotal) * 100;
  }
}

/// All category spending for one calendar month.
class MonthSpendingSummary {
  final int month;
  final int year;
  final List<CategorySpending> categories;
  final double total;

  const MonthSpendingSummary({
    required this.month,
    required this.year,
    required this.categories,
    required this.total,
  });

  bool get isEmpty => categories.isEmpty;

  CategorySpending? categoryNamed(String category) {
    final normalized = category.toLowerCase();
    for (final item in categories) {
      if (item.category == normalized) return item;
    }
    return null;
  }
}

/// Side-by-side summaries used for month-over-month comparison.
class MonthComparison {
  final MonthSpendingSummary primary;
  final MonthSpendingSummary baseline;

  const MonthComparison({
    required this.primary,
    required this.baseline,
  });

  /// Union of category keys present in either month, sorted by primary total desc.
  List<String> get sharedCategories {
    final totals = <String, double>{};
    for (final item in primary.categories) {
      totals[item.category] = item.total;
    }
    for (final item in baseline.categories) {
      totals.putIfAbsent(item.category, () => 0);
      totals[item.category] = totals[item.category]! + item.total;
    }

    final keys = totals.keys.toList()
      ..sort((a, b) {
        final primaryDiff = (primary.categoryNamed(b)?.total ?? 0) -
            (primary.categoryNamed(a)?.total ?? 0);
        if (primaryDiff != 0) return primaryDiff.sign.toInt();
        return (baseline.categoryNamed(b)?.total ?? 0)
            .compareTo(baseline.categoryNamed(a)?.total ?? 0);
      });
    return keys;
  }

  double deltaForCategory(String category) {
    final current = primary.categoryNamed(category)?.total ?? 0;
    final previous = baseline.categoryNamed(category)?.total ?? 0;
    return current - previous;
  }

  double get totalDelta => primary.total - baseline.total;
}
