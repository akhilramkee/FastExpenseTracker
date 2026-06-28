import 'package:flutter_test/flutter_test.dart';
import 'package:client/core/utils/categories.dart';

void main() {
  group('normalizeCategory', () {
    test('maps travel and transport aliases', () {
      expect(normalizeCategory('Travel'), 'travel');
      expect(normalizeCategory('Transportation'), 'transport');
      expect(normalizeCategory('fuel'), 'transport');
      expect(normalizeCategory('accommodation'), 'travel');
    });

    test('maps healthcare and gifts', () {
      expect(normalizeCategory('Healthcare'), 'healthcare');
      expect(normalizeCategory('Gift'), 'gifts');
      expect(normalizeCategory('donation'), 'charity');
    });

    test('formatCategoryLabel title-cases canonical slug', () {
      expect(formatCategoryLabel('transport'), 'Transport');
      expect(formatCategoryLabel('subscriptions'), 'Subscriptions');
    });
  });
}
