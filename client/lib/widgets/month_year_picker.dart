import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Opens a month/year picker dialog. Returns the first day of the chosen month.
Future<DateTime?> showMonthYearPicker(
  BuildContext context, {
  required int initialMonth,
  required int initialYear,
  int firstYear = 2020,
  int? lastYear,
}) {
  final now = DateTime.now();
  final effectiveLastYear = lastYear ?? now.year;

  return showDialog<DateTime>(
    context: context,
    builder: (context) => _MonthYearPickerDialog(
      initialMonth: initialMonth,
      initialYear: initialYear.clamp(firstYear, effectiveLastYear),
      firstYear: firstYear,
      lastYear: effectiveLastYear,
    ),
  );
}

class MonthYearPickerField extends StatelessWidget {
  final int month;
  final int year;
  final ValueChanged<DateTime> onChanged;
  final int firstYear;
  final int? lastYear;

  const MonthYearPickerField({
    super.key,
    required this.month,
    required this.year,
    required this.onChanged,
    this.firstYear = 2020,
    this.lastYear,
  });

  String get _label => DateFormat('MMMM yyyy').format(DateTime(year, month));

  Future<void> _openPicker(BuildContext context) async {
    final picked = await showMonthYearPicker(
      context,
      initialMonth: month,
      initialYear: year,
      firstYear: firstYear,
      lastYear: lastYear,
    );
    if (picked != null) {
      onChanged(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1E1F30),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => _openPicker(context),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              const Icon(Icons.calendar_month_rounded, color: Color(0xFF8B5CF6), size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Period',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500], letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.grey[500]),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthYearPickerDialog extends StatefulWidget {
  final int initialMonth;
  final int initialYear;
  final int firstYear;
  final int lastYear;

  const _MonthYearPickerDialog({
    required this.initialMonth,
    required this.initialYear,
    required this.firstYear,
    required this.lastYear,
  });

  @override
  State<_MonthYearPickerDialog> createState() => _MonthYearPickerDialogState();
}

class _MonthYearPickerDialogState extends State<_MonthYearPickerDialog> {
  late int _month;
  late int _year;

  static const _monthLabels = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  void initState() {
    super.initState();
    _month = widget.initialMonth;
    _year = widget.initialYear;
  }

  void _shiftYear(int delta) {
    setState(() {
      _year = (_year + delta).clamp(widget.firstYear, widget.lastYear);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1F30),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Select period'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: _year > widget.firstYear ? () => _shiftYear(-1) : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Text(
                  '$_year',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  onPressed: _year < widget.lastYear ? () => _shiftYear(1) : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 2.2,
              ),
              itemCount: 12,
              itemBuilder: (context, index) {
                final month = index + 1;
                final selected = month == _month;
                return Material(
                  color: selected
                      ? const Color(0xFF8B5CF6)
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: () => setState(() => _month = month),
                    borderRadius: BorderRadius.circular(12),
                    child: Center(
                      child: Text(
                        _monthLabels[index],
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: selected ? Colors.white : Colors.grey[300],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, DateTime(_year, _month)),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
