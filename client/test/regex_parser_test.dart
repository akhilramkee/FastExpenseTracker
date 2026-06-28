import 'package:flutter_test/flutter_test.dart';
import 'package:client/core/models/transaction_model.dart';

void main() {
  group('TransactionModel.parse tests', () {
    test('should parse amount and tag with spaces', () {
      const input = "1450 zoom subscription renewal @work";
      final tx = TransactionModel.parse(input);

      expect(tx.amount, 1450.0);
      expect(tx.tag, "work");
      expect(tx.description, "zoom subscription renewal");
      expect(tx.syncStatus, SyncStatus.pending);
    });

    test('should parse decimal amounts', () {
      const input = "45.90 dinner @night #food";
      final tx = TransactionModel.parse(input);

      expect(tx.amount, 45.90);
      expect(tx.tag, "night");
      expect(tx.description, "dinner #food");
    });

    test('should handle missing tag and amount', () {
      const input = "Just some text description";
      final tx = TransactionModel.parse(input);

      expect(tx.amount, 0.0);
      expect(tx.tag, "uncategorized");
      expect(tx.description, "Just some text description");
    });

    test('should fallback to default description if empty', () {
      const input = "100 @work";
      final tx = TransactionModel.parse(input);

      expect(tx.amount, 100.0);
      expect(tx.tag, "work");
      expect(tx.description, "Expense under work");
    });

    test('should parse ISO date prefix', () {
      const input = "2026-06-15 45.90 lunch #food";
      final tx = TransactionModel.parse(input);

      expect(tx.amount, 45.90);
      expect(tx.tag, "food");
      expect(tx.description, "lunch");
      expect(tx.createdAt.year, 2026);
      expect(tx.createdAt.month, 6);
      expect(tx.createdAt.day, 15);
    });

    test('should parse MM/DD date prefix with current year', () {
      const input = "06/20 12.50 coffee #food";
      final tx = TransactionModel.parse(input);

      expect(tx.amount, 12.50);
      expect(tx.description, "coffee");
      expect(tx.createdAt.month, 6);
      expect(tx.createdAt.day, 20);
      expect(tx.createdAt.year, DateTime.now().year);
    });

    test('should parse today keyword', () {
      const input = "today 9.99 snack #food";
      final tx = TransactionModel.parse(input);

      expect(tx.amount, 9.99);
      expect(tx.createdAt.year, DateTime.now().year);
      expect(tx.createdAt.month, DateTime.now().month);
      expect(tx.createdAt.day, DateTime.now().day);
    });

    test('should default to today when no date provided', () {
      final tx = TransactionModel.parse("20.00 groceries #food");

      expect(tx.createdAt.year, DateTime.now().year);
      expect(tx.createdAt.month, DateTime.now().month);
      expect(tx.createdAt.day, DateTime.now().day);
    });

    test('reparse should keep existing date when edit omits date', () {
      final original = TransactionModel.parse("2026-01-10 30.00 taxi #transport");
      final edited = original.reparse("35.00 taxi #transport");

      expect(edited.amount, 35.0);
      expect(edited.createdAt.year, 2026);
      expect(edited.createdAt.month, 1);
      expect(edited.createdAt.day, 10);
    });

    test('should parse amount at end when name contains digits', () {
      const input = "Zee5 subscription annual 799";
      final tx = TransactionModel.parse(input);

      expect(tx.amount, 799.0);
      expect(tx.description, "Zee5 subscription annual");
    });

    test('displayTitle strips tokenizer pad artifacts from displayLabel', () {
      final tx = TransactionModel(
        id: 'test-id',
        rawInput: '1450 zoom subscription',
        amount: 1450,
        description: 'zoom subscription',
        tag: 'work',
        displayLabel: 'Zoom <pad> Subscription',
      );

      expect(tx.displayTitle, 'Zoom Subscription');
    });

    test('reparse should clear enrichment fields and mark pending', () {
      final original = TransactionModel(
        id: 'test-id',
        rawInput: '799 Zee5 subscription',
        amount: 799,
        description: 'Zee5 subscription',
        tag: 'entertainment',
        merchant: 'Zee5',
        displayLabel: 'Zee5 Subscription',
        aiConfidence: 0.95,
        isRecurring: true,
        syncStatus: SyncStatus.completed,
        createdAt: DateTime(2026, 6, 12),
      );

      final edited = original.reparse('799 Zee5 annual subscription');

      expect(edited.amount, 799.0);
      expect(edited.syncStatus, SyncStatus.pending);
      expect(edited.merchant, isNull);
      expect(edited.displayLabel, isNull);
      expect(edited.aiConfidence, isNull);
      expect(edited.isRecurring, isFalse);
    });

    test('should parse amount with Rs. prefix', () {
      const input = "Rs. 1450 zoom subscription @work";
      final tx = TransactionModel.parse(input);

      expect(tx.amount, 1450.0);
      expect(tx.description, "zoom subscription");
    });

    test('should parse amount with rupee suffix', () {
      const input = "500 rupees groceries #food";
      final tx = TransactionModel.parse(input);

      expect(tx.amount, 500.0);
      expect(tx.description, "groceries");
    });

    test('should parse amount with rs suffix', () {
      const input = "99.50 rs dinner #food";
      final tx = TransactionModel.parse(input);

      expect(tx.amount, 99.50);
      expect(tx.description, "dinner");
    });
  });
}
