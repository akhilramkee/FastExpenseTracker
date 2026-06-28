import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/enrichment_config_service.dart';
import '../models/transaction_model.dart';
import '../utils/categories.dart';

class EnrichmentResult {
  final String category;
  final double confidence;
  final String? merchant;
  final bool isRecurring;
  final String displayLabel;

  const EnrichmentResult({
    required this.category,
    required this.confidence,
    required this.merchant,
    required this.isRecurring,
    required this.displayLabel,
  });
}

class EnrichmentService {
  final EnrichmentConfigService _config;

  EnrichmentService({EnrichmentConfigService? config})
      : _config = config ?? EnrichmentConfigService();

  static const _systemPromptPrefix = '''
You are an isolated financial intelligence string extraction parser microservice engine.
Your specific structural instructions are to accept raw, single-line data entries and resolve them into perfectly compliant structured parameters without additional narrative text wrapper outputs.

You must format output streams to match the parameters of this designated JSON schema map:
{
  "amount": float,
  "category": string,
  "confidence": float (range 0.00 to 1.00),
  "merchant": string or null,
  "is_recurring": boolean,
  "display_label": string
}

''';

  static const _systemPromptSuffix = '''

The display_label must be a short (max 50 characters), title-case, human-readable summary suitable for a mobile UI.
Do not include hashtags, currency symbols, or raw tag markers in display_label.
Example: "Zoom Subscription Renewal" instead of "zoom subscription renewal @work".''';

  static String get _systemPrompt =>
      '$_systemPromptPrefix$categoryPromptBlock$_systemPromptSuffix';

  Future<EnrichmentResult?> enrich(String rawInput) async {
    if (!await _config.isConfigured) return null;

    final apiKey = await _config.getOpenRouterApiKey();
    if (apiKey == null || apiKey.isEmpty) return null;

    final model = _config.getOpenRouterModel();
    if (!_config.isFreeModel(model)) {
      throw StateError('OpenRouter model must be free (openrouter/free or *:free)');
    }

    final response = await http
        .post(
          Uri.parse(EnrichmentConfigService.defaultUrl),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': model,
            'messages': [
              {'role': 'system', 'content': _systemPrompt},
              {'role': 'user', 'content': rawInput},
            ],
            'response_format': {'type': 'json_object'},
            'temperature': 0.1,
          }),
        )
        .timeout(const Duration(seconds: 120));

    if (response.statusCode != 200) {
      throw Exception(
        'OpenRouter returned ${response.statusCode}: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = data['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw Exception('OpenRouter response missing choices');
    }

    final message = choices.first as Map<String, dynamic>;
    final content = (message['message'] as Map<String, dynamic>?)?['content'] as String?;
    if (content == null || content.trim().isEmpty) {
      throw Exception('OpenRouter response missing message content');
    }

    final parsed = _parseJsonContent(content);
    final displayLabel = parsed['display_label'] as String?;
    if (displayLabel == null || displayLabel.trim().isEmpty) {
      throw Exception('OpenRouter response missing display_label');
    }

    return EnrichmentResult(
      category: normalizeCategory(parsed['category'] as String?),
      confidence: (parsed['confidence'] as num?)?.toDouble() ?? 1.0,
      merchant: _sanitizeOptionalString(parsed['merchant']),
      isRecurring: parsed['is_recurring'] == true,
      displayLabel: TransactionModel.sanitizeDisplayText(displayLabel),
    );
  }

  @visibleForTesting
  static Map<String, dynamic> parseJsonContentForTest(String messageContent) =>
      _parseJsonContent(messageContent);

  static Map<String, dynamic> _parseJsonContent(String messageContent) {
    var content = messageContent.trim();
    if (content.startsWith('```')) {
      final lines = content.split('\n');
      if (lines.length >= 3) {
        content = lines.sublist(1, lines.length - 1).join('\n');
      }
    }
    content = TransactionModel.stripTokenizerArtifacts(content);
    final decoded = jsonDecode(content);
    return Map<String, dynamic>.from(
      _sanitizeJsonValue(decoded) as Map,
    );
  }

  static dynamic _sanitizeJsonValue(dynamic value) {
    if (value is String) {
      return TransactionModel.sanitizeDisplayText(value);
    }
    if (value is List) {
      return value.map(_sanitizeJsonValue).toList();
    }
    if (value is Map) {
      return value.map(
        (key, item) => MapEntry(key, _sanitizeJsonValue(item)),
      );
    }
    return value;
  }

  static String? _sanitizeOptionalString(dynamic value) {
    if (value == null) return null;
    final text = TransactionModel.sanitizeDisplayText(value.toString());
    return text.isEmpty ? null : text;
  }
}
