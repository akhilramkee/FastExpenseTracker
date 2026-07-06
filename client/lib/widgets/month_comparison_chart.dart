import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/models/category_spending.dart';
import '../core/utils/categories.dart';
import '../core/utils/category_utils.dart';
import '../core/utils/currency_utils.dart';

/// Grouped horizontal bars — easier to read category labels than vertical bars,
/// and ideal for comparing the same categories across two months.
class MonthComparisonChart extends StatelessWidget {
  final MonthComparison comparison;
  final int maxCategories;

  const MonthComparisonChart({
    super.key,
    required this.comparison,
    this.maxCategories = 6,
  });

  String _monthLabel(MonthSpendingSummary summary) =>
      DateFormat('MMM yy').format(DateTime(summary.year, summary.month));

  @override
  Widget build(BuildContext context) {
    final categories = comparison.sharedCategories.take(maxCategories).toList();
    if (categories.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'Add expenses in both months to compare categories.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[500]),
        ),
      );
    }

    final maxAmount = categories.fold<double>(0, (max, category) {
      final primary = comparison.primary.categoryNamed(category)?.total ?? 0;
      final compare = comparison.baseline.categoryNamed(category)?.total ?? 0;
      return [max, primary, compare].reduce((a, b) => a > b ? a : b);
    });

    final barMax = maxAmount <= 0 ? 1.0 : maxAmount * 1.15;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _LegendDot(
              color: const Color(0xFF8B5CF6),
              label: _monthLabel(comparison.primary),
            ),
            const SizedBox(width: 16),
            _LegendDot(
              color: const Color(0xFF06B6D4),
              label: _monthLabel(comparison.baseline),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...categories.map((category) {
          final primary = comparison.primary.categoryNamed(category);
          final compare = comparison.baseline.categoryNamed(category);
          final style = resolveCategoryStyle(tag: category);
          final primaryTotal = primary?.total ?? 0;
          final compareTotal = compare?.total ?? 0;

          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(style.icon, size: 16, color: style.color),
                    const SizedBox(width: 6),
                    Text(
                      formatCategoryLabel(category),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _ComparisonBarRow(
                  amount: primaryTotal,
                  maxAmount: barMax,
                  color: const Color(0xFF8B5CF6),
                  label: formatCurrency(primaryTotal),
                ),
                const SizedBox(height: 6),
                _ComparisonBarRow(
                  amount: compareTotal,
                  maxAmount: barMax,
                  color: const Color(0xFF06B6D4),
                  label: formatCurrency(compareTotal),
                ),
              ],
            ),
          );
        }),
        Text(
          'Longer bar = more spent. Compare purple (${_monthLabel(comparison.primary)}) vs cyan (${_monthLabel(comparison.baseline)}).',
          style: TextStyle(fontSize: 12, color: Colors.grey[500], height: 1.4),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[300])),
      ],
    );
  }
}

class _ComparisonBarRow extends StatelessWidget {
  final double amount;
  final double maxAmount;
  final Color color;
  final String label;

  const _ComparisonBarRow({
    required this.amount,
    required this.maxAmount,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = maxAmount <= 0 ? 0.0 : (amount / maxAmount).clamp(0.0, 1.0);

    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 10,
              backgroundColor: Colors.white.withValues(alpha: 0.06),
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 72,
          child: Text(
            label,
            textAlign: TextAlign.end,
            style: TextStyle(fontSize: 11, color: Colors.grey[400]),
          ),
        ),
      ],
    );
  }
}

/// Compact grouped bar chart for total month-over-month trend (top-level KPI).
class MonthlyTotalComparisonChart extends StatelessWidget {
  final MonthComparison comparison;

  const MonthlyTotalComparisonChart({super.key, required this.comparison});

  @override
  Widget build(BuildContext context) {
    final primaryLabel =
        DateFormat('MMM yyyy').format(DateTime(comparison.primary.year, comparison.primary.month));
    final compareLabel =
        DateFormat('MMM yyyy').format(DateTime(comparison.baseline.year, comparison.baseline.month));
    final maxTotal = [
      comparison.primary.total,
      comparison.baseline.total,
      1.0,
    ].reduce((a, b) => a > b ? a : b);

    return BarChart(
      BarChartData(
        maxY: maxTotal * 1.2,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.white.withValues(alpha: 0.06),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (value, meta) {
                if (value == 0 || value > maxTotal) {
                  return const SizedBox.shrink();
                }
                return Text(
                  _compactCurrency(value),
                  style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                final label = index == 0 ? compareLabel : primaryLabel;
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 10, color: Colors.grey[400]),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          BarChartGroupData(
            x: 0,
            barRods: [
              BarChartRodData(
                toY: comparison.baseline.total,
                color: const Color(0xFF06B6D4),
                width: 28,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
              ),
            ],
          ),
          BarChartGroupData(
            x: 1,
            barRods: [
              BarChartRodData(
                toY: comparison.primary.total,
                color: const Color(0xFF8B5CF6),
                width: 28,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
              ),
            ],
          ),
        ],
      ),
      duration: const Duration(milliseconds: 300),
    );
  }

  String _compactCurrency(double value) {
    if (value >= 100000) return '₹${(value / 100000).toStringAsFixed(1)}L';
    if (value >= 1000) return '₹${(value / 1000).toStringAsFixed(1)}k';
    return '₹${value.toStringAsFixed(0)}';
  }
}
