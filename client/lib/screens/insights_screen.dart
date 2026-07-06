import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/db/database_helper.dart';
import '../core/models/category_spending.dart';
import '../core/services/spending_analytics_service.dart';
import '../core/utils/currency_utils.dart';
import '../widgets/category_breakdown_list.dart';
import '../widgets/category_donut_chart.dart';
import '../widgets/month_comparison_chart.dart';
import '../widgets/month_year_picker.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  final SpendingAnalyticsService _analytics = SpendingAnalyticsService();
  final DatabaseHelper _dbHelper = DatabaseHelper();

  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;
  int _compareMonth = DateTime.now().month == 1 ? 12 : DateTime.now().month - 1;
  int _compareYear =
      DateTime.now().month == 1 ? DateTime.now().year - 1 : DateTime.now().year;

  bool _compareEnabled = false;
  bool _isLoading = true;
  MonthSpendingSummary? _summary;
  MonthComparison? _comparison;
  String? _highlightedCategory;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final latest = await _dbHelper.getLatestTransactionDate();
    if (latest != null && _summary == null) {
      _selectedMonth = latest.month;
      _selectedYear = latest.year;
      final previous = SpendingAnalyticsService.previousMonth(
        _selectedMonth,
        _selectedYear,
      );
      _compareMonth = previous.month;
      _compareYear = previous.year;
    }

    final summary = await _analytics.getMonthSummary(_selectedMonth, _selectedYear);
    MonthComparison? comparison;
    if (_compareEnabled) {
      comparison = await _analytics.compareMonths(
        primaryMonth: _selectedMonth,
        primaryYear: _selectedYear,
        compareMonth: _compareMonth,
        compareYear: _compareYear,
      );
    }

    if (!mounted) return;
    setState(() {
      _summary = summary;
      _comparison = comparison;
      _isLoading = false;
      if (_highlightedCategory != null &&
          summary.categoryNamed(_highlightedCategory!) == null) {
        _highlightedCategory = null;
      }
    });
  }

  Future<void> _onPrimaryPeriodChanged(DateTime period) async {
    setState(() {
      _selectedMonth = period.month;
      _selectedYear = period.year;
      _highlightedCategory = null;
    });
    await _loadData();
  }

  Future<void> _onComparePeriodChanged(DateTime period) async {
    setState(() {
      _compareMonth = period.month;
      _compareYear = period.year;
    });
    await _loadData();
  }

  void _toggleCompare(bool enabled) {
    if (enabled) {
      final previous = SpendingAnalyticsService.previousMonth(
        _selectedMonth,
        _selectedYear,
      );
      _compareMonth = previous.month;
      _compareYear = previous.year;
    }
    setState(() => _compareEnabled = enabled);
    _loadData();
  }

  void _usePreviousMonth() {
    final previous = SpendingAnalyticsService.previousMonth(
      _selectedMonth,
      _selectedYear,
    );
    setState(() {
      _compareMonth = previous.month;
      _compareYear = previous.year;
    });
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _summary == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final summary = _summary;
    final comparison = _comparison;
    final periodLabel = DateFormat('MMMM yyyy')
        .format(DateTime(_selectedYear, _selectedMonth));

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Spending Insights',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'See how your spending splits by category and compare across months.',
                        style: TextStyle(fontSize: 14, color: Colors.grey[400], height: 1.4),
                      ),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 20)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: MonthYearPickerField(
                    month: _selectedMonth,
                    year: _selectedYear,
                    onChanged: _onPrimaryPeriodChanged,
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              if (summary != null && !summary.isEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _SectionCard(
                      title: 'Where your money went',
                      subtitle: 'Category split for $periodLabel',
                      child: CategoryDonutChart(
                        summary: summary,
                        selectedCategory: _highlightedCategory,
                        onCategorySelected: (category) {
                          setState(() => _highlightedCategory = category);
                        },
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
              ],
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _SectionCard(
                    title: 'Compare months',
                    subtitle: 'See if you spent more or less in each category',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Enable month comparison'),
                          subtitle: Text(
                            _compareEnabled
                                ? 'Showing changes vs ${DateFormat('MMMM yyyy').format(DateTime(_compareYear, _compareMonth))}'
                                : 'Turn on to compare with another month',
                            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                          ),
                          value: _compareEnabled,
                          activeThumbColor: const Color(0xFF8B5CF6),
                          onChanged: _toggleCompare,
                        ),
                        if (_compareEnabled) ...[
                          const SizedBox(height: 8),
                          MonthYearPickerField(
                            month: _compareMonth,
                            year: _compareYear,
                            onChanged: _onComparePeriodChanged,
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: _usePreviousMonth,
                              icon: const Icon(Icons.history_rounded, size: 18),
                              label: const Text('Use previous month'),
                            ),
                          ),
                          if (comparison != null) ...[
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 180,
                              child: MonthlyTotalComparisonChart(comparison: comparison),
                            ),
                            const SizedBox(height: 8),
                            _TotalDeltaBanner(comparison: comparison),
                            const SizedBox(height: 16),
                            MonthComparisonChart(comparison: comparison),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _SectionCard(
                    title: 'Category breakdown',
                    subtitle: summary?.isEmpty == true
                        ? 'No expenses recorded for $periodLabel'
                        : 'Ranked list with share of total spending',
                    child: summary == null || summary.isEmpty
                        ? _EmptyMonthState(periodLabel: periodLabel)
                        : CategoryBreakdownList(
                            summary: summary,
                            comparison: comparison,
                            highlightedCategory: _highlightedCategory,
                            onCategoryTap: (category) {
                              setState(() {
                                _highlightedCategory =
                                    _highlightedCategory == category ? null : category;
                              });
                            },
                          ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1F30),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(fontSize: 13, color: Colors.grey[500]),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _TotalDeltaBanner extends StatelessWidget {
  final MonthComparison comparison;

  const _TotalDeltaBanner({required this.comparison});

  @override
  Widget build(BuildContext context) {
    final delta = comparison.totalDelta;
    final increased = delta > 0;
    final decreased = delta < 0;
    final color = increased
        ? const Color(0xFFEF4444)
        : decreased
            ? const Color(0xFF22C55E)
            : Colors.grey;

    String message;
    if (delta.abs() < 0.01) {
      message = 'Total spending stayed the same between these months.';
    } else if (increased) {
      message =
          'You spent ${formatCurrency(delta.abs())} more this month than the comparison month.';
    } else {
      message =
          'You spent ${formatCurrency(delta.abs())} less this month than the comparison month.';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            increased
                ? Icons.trending_up_rounded
                : decreased
                    ? Icons.trending_down_rounded
                    : Icons.trending_flat_rounded,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, color: Colors.grey[300], height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyMonthState extends StatelessWidget {
  final String periodLabel;

  const _EmptyMonthState({required this.periodLabel});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(Icons.pie_chart_outline_rounded, size: 56, color: Colors.grey[700]),
          const SizedBox(height: 12),
          Text(
            'No expenses for $periodLabel',
            style: TextStyle(color: Colors.grey[500], fontSize: 15),
          ),
          const SizedBox(height: 6),
          Text(
            'Add transactions on the Home tab to see your spending split here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
        ],
      ),
    );
  }
}
