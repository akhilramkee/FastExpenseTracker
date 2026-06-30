import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/enrichment_config_service.dart';
import '../config/server_config_service.dart';
import '../db/database_helper.dart';
import '../models/transaction_model.dart';
import '../services/expense_entry_service.dart';

class SyncWorker {
  final DatabaseHelper _dbHelper;
  final ServerConfigService _config;
  final ExpenseEntryService _expenseEntryService;
  final EnrichmentConfigService _enrichmentConfig;

  SyncWorker({
    DatabaseHelper? dbHelper,
    ServerConfigService? config,
    ExpenseEntryService? expenseEntryService,
    EnrichmentConfigService? enrichmentConfig,
  })  : _dbHelper = dbHelper ?? DatabaseHelper(),
        _config = config ?? ServerConfigService(),
        _enrichmentConfig = enrichmentConfig ?? EnrichmentConfigService(),
        _expenseEntryService = expenseEntryService ??
            ExpenseEntryService(
              dbHelper: dbHelper ?? DatabaseHelper(),
              enrichmentConfig: enrichmentConfig ?? EnrichmentConfigService(),
              serverConfig: config ?? ServerConfigService(),
            );

  Future<bool> isServerReachable() async {
    final healthUrl = _config.healthUrl;
    if (healthUrl.isEmpty) return false;

    try {
      final response = await http
          .get(Uri.parse(healthUrl))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> syncEnrichmentConfig({bool skipReachabilityCheck = false}) async {
    if (_config.enrichmentConfigUrl.isEmpty) return false;
    if (!skipReachabilityCheck && !await isServerReachable()) return false;
    return _enrichmentConfig.syncFromServer(_config);
  }

  Future<bool> syncPendingDeletes({bool skipReachabilityCheck = false}) async {
    final pendingDeletes = await _dbHelper.getPendingDeletes();
    if (pendingDeletes.isEmpty) return true;

    if (!skipReachabilityCheck && !await isServerReachable()) return false;

    try {
      final response = await http
          .post(
            Uri.parse(_config.deletesUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'ids': pendingDeletes}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        for (final id in pendingDeletes) {
          await _dbHelper.clearPendingDelete(id);
        }
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _enrichPendingTransactions(List<TransactionModel> pending) async {
    await Future.wait(
      pending.map((tx) => _expenseEntryService.enrichInBackground(tx.id)),
    );
  }

  Future<bool> performBackgroundSync({bool skipReachabilityCheck = false}) async {
    if (!skipReachabilityCheck && !await isServerReachable()) return false;

    await syncPendingDeletes();

    var pending = await _dbHelper.getPendingTransactions();
    if (pending.isEmpty) return true;

    await _enrichPendingTransactions(pending);
    pending = await _dbHelper.getPendingTransactions();
    if (pending.isEmpty) return true;

    try {
      for (var tx in pending) {
        await _dbHelper.updateSyncStatus(tx.id, SyncStatus.processing);
      }

      final payload = {
        'transactions': pending.map((tx) => tx.toMap()).toList(),
      };

      final response = await http.post(
        Uri.parse(_config.syncUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 202) {
        return true;
      } else {
        for (var tx in pending) {
          await _dbHelper.updateSyncStatus(tx.id, SyncStatus.failed);
        }
        return false;
      }
    } catch (_) {
      for (var tx in pending) {
        await _dbHelper.updateSyncStatus(tx.id, SyncStatus.failed);
      }
      return false;
    }
  }

  Future<bool> restoreFromServer({bool skipReachabilityCheck = false}) async {
    if (!skipReachabilityCheck && !await isServerReachable()) return false;

    try {
      final response = await http
          .get(Uri.parse(_config.statusUrl))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return false;

      final pendingDeletes = (await _dbHelper.getPendingDeletes()).toSet();
      final localTransactions = await _dbHelper.getTransactions();
      final localPendingIds = localTransactions
          .where((tx) =>
              tx.syncStatus == SyncStatus.pending ||
              tx.syncStatus == SyncStatus.failed)
          .map((tx) => tx.id)
          .toSet();
      final List<dynamic> data = jsonDecode(response.body);

      for (final item in data) {
        final serverTx = TransactionModel.fromMap(item as Map<String, dynamic>);
        if (pendingDeletes.contains(serverTx.id)) continue;
        if (localPendingIds.contains(serverTx.id)) continue;
        await _dbHelper.insertTransaction(serverTx);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> pullSyncUpdates({bool skipReachabilityCheck = false}) async {
    if (!skipReachabilityCheck && !await isServerReachable()) return;

    try {
      final transactions = await _dbHelper.getTransactions();
      final unfinished = transactions
          .where((tx) =>
              tx.syncStatus == SyncStatus.processing ||
              tx.syncStatus == SyncStatus.failed)
          .toList();

      if (unfinished.isEmpty) return;

      final idsParam = unfinished.map((tx) => tx.id).join(',');
      final url = Uri.parse('${_config.statusUrl}?ids=$idsParam');

      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        for (var item in data) {
          final serverTx = TransactionModel.fromMap(item);
          await _dbHelper.updateTransaction(serverTx);
        }
      }
    } catch (_) {
      // Fail silently to prevent user disruption
    }
  }

  Future<bool> syncAll() async {
    if (!await isServerReachable()) return false;

    await syncEnrichmentConfig(skipReachabilityCheck: true);
    await syncPendingDeletes(skipReachabilityCheck: true);
    final pushed = await performBackgroundSync(skipReachabilityCheck: true);
    await pullSyncUpdates(skipReachabilityCheck: true);
    await restoreFromServer(skipReachabilityCheck: true);
    return pushed;
  }

  Future<bool> pushEditedTransaction(TransactionModel tx) async {
    if (!await isServerReachable()) return false;

    try {
      await _dbHelper.updateSyncStatus(tx.id, SyncStatus.processing);

      final response = await http
          .put(
            Uri.parse(_config.transactionUrl(tx.id)),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(tx.toMap()),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return true;
      }

      await _dbHelper.updateSyncStatus(tx.id, SyncStatus.failed);
      return false;
    } catch (_) {
      await _dbHelper.updateSyncStatus(tx.id, SyncStatus.failed);
      return false;
    }
  }

  Future<void> syncEditedTransaction(TransactionModel tx) async {
    final pushed = await pushEditedTransaction(tx);
    if (pushed) {
      await pullSyncUpdates();
    }
  }

  Future<void> submitImport({
    required String content,
    required String format,
  }) async {
    if (!await isServerReachable()) {
      throw Exception('Server is unreachable');
    }

    final response = await http
        .post(
          Uri.parse(_config.importUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'content': content, 'format': format}),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 202) {
      throw Exception('Import failed (${response.statusCode}): ${response.body}');
    }
  }
}
