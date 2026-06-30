import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/models/transaction_model.dart';
import '../core/services/expense_entry_service.dart';
import '../core/utils/currency_utils.dart';

Future<TransactionModel?> showQuickAddSheet(
  BuildContext context, {
  String initialText = '',
  ExpenseEntryService? expenseEntryService,
}) {
  return showModalBottomSheet<TransactionModel>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1E1F30),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => _QuickAddSheet(
      initialText: initialText,
      expenseEntryService: expenseEntryService ?? ExpenseEntryService(),
    ),
  );
}

class _QuickAddSheet extends StatefulWidget {
  final String initialText;
  final ExpenseEntryService expenseEntryService;

  const _QuickAddSheet({
    required this.initialText,
    required this.expenseEntryService,
  });

  @override
  State<_QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends State<_QuickAddSheet> {
  late final TextEditingController _controller;
  String _livePreviewText =
      'Type something like: 06/20 Rs. 45.90 dinner @night #food (date optional, defaults to today)';
  double _parsedAmount = 0.0;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _controller.addListener(_updateLivePreview);
    _updateLivePreview();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _updateLivePreview() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() {
        _livePreviewText =
            'Type something like: 06/20 Rs. 45.90 dinner @night #food (date optional, defaults to today)';
        _parsedAmount = 0.0;
      });
      return;
    }

    final parsed = TransactionModel.parse(text);
    final dateLabel = DateFormat('MMM d, yyyy').format(parsed.createdAt);
    setState(() {
      _parsedAmount = parsed.amount;
      _livePreviewText =
          'Preview — $dateLabel • Amount: ${formatCurrency(parsed.amount)}  •  Tag: #${parsed.tag}';
    });
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSaving) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final saved = await widget.expenseEntryService.addFromText(text);
      if (!mounted) return;
      Navigator.pop(context, saved);
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Add Expense',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                onPressed: _isSaving ? null : () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            autofocus: true,
            enabled: !_isSaving,
            decoration: InputDecoration(
              hintText: 'Add expense (e.g. 06/20 45.90 dinner @night #food)',
              hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.arrow_forward_rounded),
                onPressed: _isSaving ? null : _save,
                color: const Color(0xFF06B6D4),
              ),
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 12),
          Text(
            _livePreviewText,
            style: TextStyle(
              fontSize: 12,
              color: _parsedAmount > 0 ? const Color(0xFF06B6D4) : Colors.grey[400],
              fontWeight: _parsedAmount > 0 ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _isSaving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
