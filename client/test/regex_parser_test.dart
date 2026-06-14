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
      expect(tx.tag, "night"); // Extracts the first tag starting with @ or #
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
  });
}
