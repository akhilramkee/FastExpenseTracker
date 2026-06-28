import 'package:client/core/models/transaction_model.dart';
import 'package:client/core/services/enrichment_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EnrichmentService JSON parsing', () {
    test('strips pad tokens from raw JSON response', () {
      const raw = '{"amount": 2097.9<pad>, "category": "travel", "confidence": 0.95, '
          '"merchant": "redBus", "is_recurring": false, '
          '"display_label": "Redbus Bus<pad><pad>"}';

      final result = EnrichmentService.parseJsonContentForTest(raw);

      expect(result['amount'], 2097.9);
      expect(result['category'], 'travel');
      expect(result['merchant'], 'redBus');
      expect(result['display_label'], 'Redbus Bus');
    });
  });

  group('TransactionModel display sanitization', () {
    test('sanitizeDisplayText strips pad tokens', () {
      expect(
        TransactionModel.sanitizeDisplayText('Zoom <pad> Subscription'),
        'Zoom Subscription',
      );
      expect(
        TransactionModel.sanitizeDisplayText('Zoom <|pad|> Subscription'),
        'Zoom Subscription',
      );
    });
  });
}
