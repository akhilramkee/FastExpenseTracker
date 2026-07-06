import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/models/category_spending.dart';
import '../core/utils/currency_utils.dart';

/// Donut chart for part-to-whole category splits — the most intuitive chart
/// for beginners asking "where did my money go?"
class CategoryDonutChart extends StatefulWidget {
  final MonthSpendingSummary summary;
  final ValueChanged<String?>? onCategorySelected;
  final String? selectedCategory;

  const CategoryDonutChart({
    super.key,
    required this.summary,
    this.onCategorySelected,
    this.selectedCategory,
  });

  @override
  State<CategoryDonutChart> createState() => _CategoryDonutChartState();
}

class _CategoryDonutChartState extends State<CategoryDonutChart> {
  int? _touchedIndex;

  @override
  Widget build(BuildContext context) {
    if (widget.summary.isEmpty) {
      return SizedBox(
        height: 220,
        child: Center(
          child: Text(
            'No spending data for this month',
            style: TextStyle(color: Colors.grey[500]),
          ),
        ),
      );
    }

    final categories = widget.summary.categories;
    final total = widget.summary.total;

    return Column(
      children: [
        SizedBox(
          height: 220,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 62,
                  startDegreeOffset: -90,
                  pieTouchData: PieTouchData(
                    touchCallback: (event, response) {
                      if (!event.isInterestedForInteractions ||
                          response == null ||
                          response.touchedSection == null) {
                        setState(() => _touchedIndex = null);
                        widget.onCategorySelected?.call(null);
                        return;
                      }
                      final index = response.touchedSection!.touchedSectionIndex;
                      setState(() => _touchedIndex = index);
                      widget.onCategorySelected?.call(categories[index].category);
                    },
                  ),
                  sections: List.generate(categories.length, (index) {
                    final item = categories[index];
                    final isSelected = widget.selectedCategory == item.category;
                    final isTouched = _touchedIndex == index;
                    final emphasized = isSelected || isTouched;
                    final share = item.shareOf(total);

                    return PieChartSectionData(
                      value: item.total,
                      color: item.style.color,
                      radius: emphasized ? 58 : 50,
                      showTitle: emphasized && share >= 8,
                      title: emphasized ? '${share.toStringAsFixed(0)}%' : '',
                      titleStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      borderSide: emphasized
                          ? const BorderSide(color: Colors.white, width: 2)
                          : BorderSide(color: Colors.black.withValues(alpha: 0.2)),
                    );
                  }),
                ),
                duration: const Duration(milliseconds: 250),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'TOTAL',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: Colors.grey[400],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatCurrency(total),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Each colored slice is a category. Bigger slice = more of your spending.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.grey[500], height: 1.4),
        ),
      ],
    );
  }
}
