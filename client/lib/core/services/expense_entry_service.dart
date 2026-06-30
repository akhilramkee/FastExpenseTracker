import 'dart:async';

import '../config/enrichment_config_service.dart';
import '../config/server_config_service.dart';
import '../db/database_helper.dart';
import '../models/transaction_model.dart';
import 'enrichment_service.dart';

class ExpenseEntryService {
  final DatabaseHelper _dbHelper;
  final EnrichmentService _enrichmentService;
  final EnrichmentConfigService _enrichmentConfig;
  final ServerConfigService _serverConfig;
  final Map<String, Future<void>> _enriching = {};

  ExpenseEntryService({
    DatabaseHelper? dbHelper,
    EnrichmentService? enrichmentService,
    EnrichmentConfigService? enrichmentConfig,
    ServerConfigService? serverConfig,
  })  : _dbHelper = dbHelper ?? DatabaseHelper(),
        _enrichmentConfig = enrichmentConfig ?? EnrichmentConfigService(),
        _serverConfig = serverConfig ?? ServerConfigService(),
        _enrichmentService = enrichmentService ??
            EnrichmentService(
              config: enrichmentConfig ?? EnrichmentConfigService(),
            );

  /// Parses and persists immediately; OpenRouter enrichment runs in the background.
  Future<TransactionModel> addFromText(
    String text, {
    void Function(TransactionModel enriched)? onEnriched,
  }) async {
    final parsed = TransactionModel.parse(text.trim());
    await _dbHelper.insertTransaction(parsed);
    unawaited(enrichInBackground(parsed.id, onComplete: onEnriched));
    return parsed;
  }

  Future<void> enrichInBackground(
    String txId, {
    void Function(TransactionModel enriched)? onComplete,
  }) {
    return _enriching.putIfAbsent(txId, () async {
      try {
        final tx = await _dbHelper.getTransactionById(txId);
        if (tx == null) return;

        final enriched = await enrichIfPossible(tx);
        if (enriched == tx) return;

        await _dbHelper.updateTransaction(enriched);
        onComplete?.call(enriched);
      } finally {
        _enriching.remove(txId);
      }
    });
  }

  Future<TransactionModel> enrichIfPossible(TransactionModel tx) async {
    if (tx.displayLabel != null && tx.displayLabel!.isNotEmpty) return tx;
    if (_serverConfig.isConfigured) {
      await _enrichmentConfig.syncFromServer(_serverConfig);
    }
    try {
      final result = await _enrichmentService.enrich(tx.rawInput);
      if (result == null) return tx;
      return tx.copyWith(
        merchant: result.merchant,
        displayLabel: result.displayLabel,
        aiConfidence: result.confidence,
        isRecurring: result.isRecurring,
        tag: result.category,
      );
    } catch (_) {
      return tx;
    }
  }
}
