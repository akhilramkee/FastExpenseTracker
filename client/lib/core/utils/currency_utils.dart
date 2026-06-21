import 'package:intl/intl.dart';

/// Matches rupee currency markers in free-text input (e.g. ₹, Rs., rupee).
final RegExp currencyMarkerPattern = RegExp(
  r'₹\s*|(?:rs\.?\s*|rupees?\s*|inr\s*)',
  caseSensitive: false,
);

final NumberFormat currencyFormatter = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
);

String formatCurrency(double amount) => currencyFormatter.format(amount);
