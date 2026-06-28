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

  Future<TransactionModel> addFromText(String text) async {
    var parsed = TransactionModel.parse(text.trim());
    parsed = await enrichIfPossible(parsed);
    await _dbHelper.insertTransaction(parsed);
    return parsed;
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
