import 'package:flutter/material.dart';

import '../core/models/category_spending.dart';
import '../core/utils/categories.dart';
import '../core/utils/currency_utils.dart';

class CategoryBreakdownList extends StatelessWidget {
  final MonthSpendingSummary summary;
  final String? highlightedCategory;
  final MonthComparison? comparison;
  final ValueChanged<String>? onCategoryTap;

  const CategoryBreakdownList({
    super.key,
    required this.summary,
    this.highlightedCategory,
    this.comparison,
    this.onCategoryTap,
  });

  @override
  Widget build(BuildContext context) {
    if (summary.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: summary.categories.map((item) {
        final isHighlighted = highlightedCategory == item.category;
        final share = item.shareOf(summary.total);
        final delta = comparison?.deltaForCategory(item.category);

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: isHighlighted
                ? item.style.color.withValues(alpha: 0.12)
                : const Color(0xFF1E1F30),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: onCategoryTap == null ? null : () => onCategoryTap!(item.category),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isHighlighted
                        ? item.style.color.withValues(alpha: 0.5)
                        : Colors.white.withValues(alpha: 0.05),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: item.style.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Icon(item.style.icon, size: 18, color: item.style.color),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            formatCategoryLabel(item.category),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Text(
                          formatCurrency(item.total),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: share / 100,
                              minHeight: 6,
                              backgroundColor: Colors.white.withValues(alpha: 0.06),
                              color: item.style.color,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${share.toStringAsFixed(1)}%',
                          style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                        ),
                        if (delta != null) ...[
                          const SizedBox(width: 8),
                          _DeltaBadge(delta: delta),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${item.count} transaction${item.count == 1 ? '' : 's'}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _DeltaBadge extends StatelessWidget {
  final double delta;

  const _DeltaBadge({required this.delta});

  @override
  Widget build(BuildContext context) {
    if (delta.abs() < 0.01) {
      return Text(
        '—',
        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
      );
    }

    final increased = delta > 0;
    final color = increased ? const Color(0xFFEF4444) : const Color(0xFF22C55E);
    final icon = increased ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded;
    final prefix = increased ? '+' : '-';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 2),
          Text(
            '$prefix${formatCurrency(delta.abs())}',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}
