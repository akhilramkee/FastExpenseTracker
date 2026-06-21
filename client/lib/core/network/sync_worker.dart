import 'dart:convert';
import 'package:http/http.dart' as http;
import '../db/database_helper.dart';
import '../models/transaction_model.dart';

class SyncWorker {
  static const String serverHost = String.fromEnvironment(
    'SERVER_HOST',
    defaultValue: '100.118.49.74',
  );
  static const String baseUrl = 'http://$serverHost:8080';
  static const String healthUrl = '$baseUrl/health';
  static const String syncUrl = '$baseUrl/api/v1/sync';
  static const String deletesUrl = '$baseUrl/api/v1/sync/deletes';
  static const String statusUrl = '$baseUrl/api/v1/sync/status';

  final DatabaseHelper _dbHelper = DatabaseHelper();

  Future<bool> isServerReachable() async {
    try {
      final response = await http
          .get(Uri.parse(healthUrl))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> syncPendingDeletes() async {
    final pendingDeletes = await _dbHelper.getPendingDeletes();
    if (pendingDeletes.isEmpty) return true;

    if (!await isServerReachable()) return false;

    try {
      final response = await http
          .post(
            Uri.parse(deletesUrl),
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

  Future<bool> performBackgroundSync() async {
    if (!await isServerReachable()) return false;

    await syncPendingDeletes();

    final pending = await _dbHelper.getPendingTransactions();
    if (pending.isEmpty) return true;

    try {
      for (var tx in pending) {
        await _dbHelper.updateSyncStatus(tx.id, SyncStatus.processing);
      }

      final payload = {
        'transactions': pending.map((tx) => tx.toMap()).toList(),
      };

      final response = await http.post(
        Uri.parse(syncUrl),
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

  Future<void> pullSyncUpdates() async {
    if (!await isServerReachable()) return;

    try {
      final transactions = await _dbHelper.getTransactions();
      final unfinished = transactions
          .where((tx) =>
              tx.syncStatus == SyncStatus.processing ||
              tx.syncStatus == SyncStatus.failed)
          .toList();

      if (unfinished.isEmpty) return;

      final idsParam = unfinished.map((tx) => tx.id).join(',');
      final url = Uri.parse('$statusUrl?ids=$idsParam');

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
    await syncPendingDeletes();
    final pushed = await performBackgroundSync();
    await pullSyncUpdates();
    return pushed;
  }
}
