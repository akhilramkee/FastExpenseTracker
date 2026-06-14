import 'package:uuid/uuid.dart';

enum SyncStatus { pending, processing, completed, failed }

class TransactionModel {
  final String id;
  final String rawInput;
  final double amount;
  final String description;
  final String tag;
  final String? merchant;
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
    this.aiConfidence,
    this.isRecurring = false,
    this.syncStatus = SyncStatus.pending,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  static TransactionModel parse(String input) {
    final cleanInput = input.trim();
    
    // 1. Extract the first matching number (decimal or integer)
    final amountRegex = RegExp(r'\d+(\.\d{1,2})?');
    final amountMatch = amountRegex.firstMatch(cleanInput);
    final amount = amountMatch != null ? double.parse(amountMatch.group(0)!) : 0.0;

    // 2. Extract a tag starting with '#' or '@'
    final tagRegex = RegExp(r'[#@](\w+)');
    final tagMatch = tagRegex.firstMatch(cleanInput);
    final tag = tagMatch != null ? tagMatch.group(1)!.toLowerCase() : 'uncategorized';

    // 3. Clean remaining text for description
    String description = cleanInput
        .replaceAll(amountMatch?.group(0) ?? '', '')
        .replaceAll(tagMatch?.group(0) ?? '', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (description.isEmpty) {
      description = "Expense under $tag";
    }

    return TransactionModel(
      id: const Uuid().v4(),
      rawInput: cleanInput,
      amount: amount,
      description: description,
      tag: tag,
      syncStatus: SyncStatus.pending,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'raw_input': rawInput,
      'amount': amount,
      'description': description,
      'tag': tag,
      'merchant': merchant,
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
      description: map['description'] as String,
      tag: map['tag'] as String,
      merchant: map['merchant'] as String?,
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

  TransactionModel copyWith({
    String? id,
    String? rawInput,
    double? amount,
    String? description,
    String? tag,
    String? merchant,
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
      aiConfidence: aiConfidence ?? this.aiConfidence,
      isRecurring: isRecurring ?? this.isRecurring,
      syncStatus: syncStatus ?? this.syncStatus,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}
