import 'package:uuid/uuid.dart';

import '../utils/currency_utils.dart';
import '../utils/categories.dart';

enum SyncStatus { pending, processing, completed, failed }

class _DateExtraction {
  final DateTime? date;
  final String remaining;

  const _DateExtraction({this.date, required this.remaining});
}

class TransactionModel {
  final String id;
  final String rawInput;
  final double amount;
  final String description;
  final String tag;
  final String? merchant;
  final String? displayLabel;
  final double? aiConfidence;
  final bool isRecurring;
  final SyncStatus syncStatus;
  final DateTime createdAt;
  final DateTime updatedAt;

  TransactionModel({
    required this.id,
    required this.rawInput,
    required this.amount,
    required this.description,
    required this.tag,
    this.merchant,
    this.displayLabel,
    this.aiConfidence,
    this.isRecurring = false,
    this.syncStatus = SyncStatus.pending,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  String get displayTitle {
    final label = displayLabel;
    if (label != null && label.isNotEmpty) {
      return sanitizeDisplayText(label);
    }
    return description;
  }

  static final RegExp _pipeSpecialTokenPattern = RegExp(r'<\|[^|>]+\|>', caseSensitive: false);
  static final RegExp _angleSpecialTokenPattern = RegExp(
    r'</?(?:pad|s|unk|bos|eos|im_start|im_end)\b[^>]*>',
    caseSensitive: false,
  );

  static String sanitizeDisplayText(String value) {
    var text = stripTokenizerArtifacts(value);
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String stripTokenizerArtifacts(String value) {
    var text = value.replaceAll(_pipeSpecialTokenPattern, '');
    text = text.replaceAll(_angleSpecialTokenPattern, '');
    return text;
  }

  static TransactionModel parse(String input, {DateTime? defaultDate}) {
    final cleanInput = input.trim();
    final dateExtraction = _extractDate(cleanInput);
    final parseText = dateExtraction.remaining;

    final amountRegex = RegExp(r'\d+(\.\d{1,2})?');
    final amountMatches = amountRegex.allMatches(parseText).toList();
    final amountMatch = amountMatches.isNotEmpty ? amountMatches.last : null;
    final amount = amountMatch != null ? double.parse(amountMatch.group(0)!) : 0.0;

    final tagRegex = RegExp(r'[#@](\w+)');
    final tagMatch = tagRegex.firstMatch(parseText);
    final tag = tagMatch != null ? normalizeCategory(tagMatch.group(1)) : 'uncategorized';

    String description = parseText;
    if (amountMatch != null) {
      description = '${parseText.substring(0, amountMatch.start)}${parseText.substring(amountMatch.end)}';
    }
    description = description
        .replaceAll(tagMatch?.group(0) ?? '', '')
        .replaceAll(currencyMarkerPattern, '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (description.isEmpty) {
      description = "Expense under $tag";
    }

    final transactionDate = dateExtraction.date != null
        ? _withCurrentTime(dateExtraction.date!)
        : (defaultDate ?? DateTime.now());

    return TransactionModel(
      id: const Uuid().v4(),
      rawInput: cleanInput,
      amount: amount,
      description: description,
      tag: tag,
      syncStatus: SyncStatus.pending,
      createdAt: transactionDate,
    );
  }

  static _DateExtraction _extractDate(String input) {
    var text = input.trim();
    final lower = text.toLowerCase();

    if (lower.startsWith('today')) {
      final remaining = text.length > 5 ? text.substring(5).trim() : '';
      return _DateExtraction(date: _dateOnly(DateTime.now()), remaining: remaining);
    }

    if (lower.startsWith('yesterday')) {
      final remaining = text.length > 9 ? text.substring(9).trim() : '';
      return _DateExtraction(
        date: _dateOnly(DateTime.now().subtract(const Duration(days: 1))),
        remaining: remaining,
      );
    }

    final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:\b|\s)');
    var match = iso.firstMatch(text);
    if (match != null) {
      final date = _safeDate(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
      );
      if (date != null) {
        return _DateExtraction(date: date, remaining: text.substring(match.end).trim());
      }
    }

    final slash = RegExp(r'^(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?(?:\b|\s)');
    match = slash.firstMatch(text);
    if (match != null) {
      final date = _parseMonthDayYear(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        match.group(3),
      );
      if (date != null) {
        return _DateExtraction(date: date, remaining: text.substring(match.end).trim());
      }
    }

    final dashed = RegExp(r'^(\d{1,2})-(\d{1,2})(?:-(\d{2,4}))?(?:\b|\s)');
    match = dashed.firstMatch(text);
    if (match != null) {
      final date = _parseMonthDayYear(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        match.group(3),
      );
      if (date != null) {
        return _DateExtraction(date: date, remaining: text.substring(match.end).trim());
      }
    }

    return _DateExtraction(remaining: text);
  }

  static DateTime? _parseMonthDayYear(int month, int day, String? yearText) {
    final year = yearText == null
        ? DateTime.now().year
        : (yearText.length == 2 ? 2000 + int.parse(yearText) : int.parse(yearText));
    return _safeDate(year, month, day);
  }

  static DateTime? _safeDate(int year, int month, int day) {
    try {
      return DateTime(year, month, day);
    } catch (_) {
      return null;
    }
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static DateTime _withCurrentTime(DateTime date) {
    final now = DateTime.now();
    return DateTime(date.year, date.month, date.day, now.hour, now.minute, now.second);
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'raw_input': rawInput,
      'amount': amount,
      'description': description,
      'tag': tag,
      'merchant': merchant,
      'display_label': displayLabel,
      'ai_confidence': aiConfidence,
      'is_recurring': isRecurring ? 1 : 0,
      'sync_status': syncStatus.name,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory TransactionModel.fromMap(Map<String, dynamic> map) {
    return TransactionModel(
      id: map['id'] as String,
      rawInput: map['raw_input'] as String,
      amount: (map['amount'] as num).toDouble(),
      description: (map['description'] as String?) ?? '',
      tag: normalizeCategory(map['tag'] as String?),
      merchant: map['merchant'] as String?,
      displayLabel: map['display_label'] as String?,
      aiConfidence: map['ai_confidence'] != null ? (map['ai_confidence'] as num).toDouble() : null,
      isRecurring: map['is_recurring'] == 1 || map['is_recurring'] == true,
      syncStatus: SyncStatus.values.firstWhere(
        (e) => e.name == map['sync_status'],
        orElse: () => SyncStatus.pending,
      ),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  TransactionModel reparse(String input) {
    final parsed = TransactionModel.parse(input, defaultDate: createdAt);
    return TransactionModel(
      id: id,
      rawInput: parsed.rawInput,
      amount: parsed.amount,
      description: parsed.description,
      tag: parsed.tag,
      merchant: null,
      displayLabel: null,
      aiConfidence: null,
      isRecurring: false,
      syncStatus: SyncStatus.pending,
      createdAt: parsed.createdAt,
      updatedAt: DateTime.now(),
    );
  }

  TransactionModel copyWith({
    String? id,
    String? rawInput,
    double? amount,
    String? description,
    String? tag,
    String? merchant,
    String? displayLabel,
    double? aiConfidence,
    bool? isRecurring,
    SyncStatus? syncStatus,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TransactionModel(
      id: id ?? this.id,
      rawInput: rawInput ?? this.rawInput,
      amount: amount ?? this.amount,
      description: description ?? this.description,
      tag: tag ?? this.tag,
      merchant: merchant ?? this.merchant,
      displayLabel: displayLabel ?? this.displayLabel,
      aiConfidence: aiConfidence ?? this.aiConfidence,
      isRecurring: isRecurring ?? this.isRecurring,
      syncStatus: syncStatus ?? this.syncStatus,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}
