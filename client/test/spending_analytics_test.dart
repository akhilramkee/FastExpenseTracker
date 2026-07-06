import 'package:flutter_test/flutter_test.dart';

import 'package:client/core/models/category_spending.dart';
import 'package:client/core/models/transaction_model.dart';
import 'package:client/core/services/spending_analytics_service.dart';

void main() {
  final service = SpendingAnalyticsService();

  TransactionModel tx({
    required String id,
    required double amount,
    required String tag,
  }) {
    final now = DateTime(2026, 3, 15);
    return TransactionModel(
      id: id,
      rawInput: '$amount $tag',
      amount: amount,
      description: tag,
      tag: tag,
      syncStatus: SyncStatus.completed,
      createdAt: now,
      updatedAt: now,
    );
  }

  group('SpendingAnalyticsService', () {
    test('groups transactions by normalized category and sorts by total', () {
      final summary = service.summarizeTransactions(
        month: 3,
        year: 2026,
        transactions: [
          tx(id: '1', amount: 500, tag: 'food'),
          tx(id: '2', amount: 300, tag: 'grocery'),
          tx(id: '3', amount: 200, tag: 'food'),
          tx(id: '4', amount: 100, tag: 'travel'),
        ],
      );

      expect(summary.total, 1100);
      expect(summary.categories.length, 3);
      expect(summary.categories.first.category, 'food');
      expect(summary.categories.first.total, 700);
      expect(summary.categories.first.count, 2);
      expect(summary.categoryNamed('groceries')?.total, 300);
    });

    test('previousMonth rolls back across year boundary', () {
      expect(
        SpendingAnalyticsService.previousMonth(1, 2026),
        (month: 12, year: 2025),
      );
      expect(
        SpendingAnalyticsService.previousMonth(6, 2026),
        (month: 5, year: 2026),
      );
    });

    test('MonthComparison computes category deltas', () {
      final primary = service.summarizeTransactions(
        month: 3,
        year: 2026,
        transactions: [
          tx(id: '1', amount: 400, tag: 'food'),
          tx(id: '2', amount: 100, tag: 'travel'),
        ],
      );
      final compare = service.summarizeTransactions(
        month: 2,
        year: 2026,
        transactions: [
          tx(id: '3', amount: 250, tag: 'food'),
          tx(id: '4', amount: 50, tag: 'subscriptions'),
        ],
      );

      final comparison = MonthComparison(primary: primary, baseline: compare);
      expect(comparison.totalDelta, 200);
      expect(comparison.deltaForCategory('food'), 150);
      expect(comparison.deltaForCategory('subscriptions'), -50);
      expect(comparison.sharedCategories.first, 'food');
    });
  });
}
