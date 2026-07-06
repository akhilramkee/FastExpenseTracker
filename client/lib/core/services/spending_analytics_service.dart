import '../db/database_helper.dart';
import '../models/category_spending.dart';
import '../models/transaction_model.dart';
import '../utils/categories.dart';

class SpendingAnalyticsService {
  final DatabaseHelper _dbHelper;

  SpendingAnalyticsService({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper();

  Future<MonthSpendingSummary> getMonthSummary(int month, int year) async {
    final transactions =
        await _dbHelper.getTransactionsByMonthAndYear(month, year);
    return summarizeTransactions(
      transactions: transactions,
      month: month,
      year: year,
    );
  }

  Future<MonthComparison> compareMonths({
    required int primaryMonth,
    required int primaryYear,
    required int compareMonth,
    required int compareYear,
  }) async {
    final primary = await getMonthSummary(primaryMonth, primaryYear);
    final compare = await getMonthSummary(compareMonth, compareYear);
    return MonthComparison(primary: primary, baseline: compare);
  }

  /// Pure aggregation — easy to unit test without SQLite.
  MonthSpendingSummary summarizeTransactions({
    required List<TransactionModel> transactions,
    required int month,
    required int year,
  }) {
    final totals = <String, double>{};
    final counts = <String, int>{};

    for (final tx in transactions) {
      final category = normalizeCategory(tx.tag);
      totals[category] = (totals[category] ?? 0) + tx.amount;
      counts[category] = (counts[category] ?? 0) + 1;
    }

    final categories = totals.entries
        .map(
          (entry) => CategorySpending(
            category: entry.key,
            total: entry.value,
            count: counts[entry.key] ?? 0,
          ),
        )
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    final grandTotal = categories.fold<double>(0, (sum, item) => sum + item.total);

    return MonthSpendingSummary(
      month: month,
      year: year,
      categories: categories,
      total: grandTotal,
    );
  }

  /// Returns the month immediately before [month]/[year].
  static ({int month, int year}) previousMonth(int month, int year) {
    if (month == 1) {
      return (month: 12, year: year - 1);
    }
    return (month: month - 1, year: year);
  }
}
