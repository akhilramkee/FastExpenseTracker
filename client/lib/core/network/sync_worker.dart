import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../db/database_helper.dart';
import '../models/transaction_model.dart';

class SyncWorker {
  static const String serverHost = String.fromEnvironment(
    'SERVER_HOST',
    defaultValue: '100.118.49.74',
  );
  static const String baseUrl = 'http://$serverHost:8080';
  static const String syncUrl = '$baseUrl/api/v1/sync';
  static const String statusUrl = '$baseUrl/api/v1/sync/status';

  final DatabaseHelper _dbHelper = DatabaseHelper();

  // Network Handshake Verification (Fail-fast if target node is unreachable)
  Future<bool> isServerReachable() async {
    try {
      final result = await InternetAddress.lookup(serverHost)
          .timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // Pushes pending transactions to the server
  Future<bool> performBackgroundSync() async {
    final pending = await _dbHelper.getPendingTransactions();
    if (pending.isEmpty) return true;

    if (!await isServerReachable()) {
      return false;
    }

    try {
      // Set status to processing locally to avoid duplicate syncs
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
        // Rollback to pending/failed if server rejected it
        for (var tx in pending) {
          await _dbHelper.updateSyncStatus(tx.id, SyncStatus.failed);
        }
        return false;
      }
    } catch (_) {
      // Rollback to failed on error
      for (var tx in pending) {
        await _dbHelper.updateSyncStatus(tx.id, SyncStatus.failed);
      }
      return false;
    }
  }

  // Pulls enriched states from the server and updates local DB
  Future<void> pullSyncUpdates() async {
    if (!await isServerReachable()) return;

    try {
      final transactions = await _dbHelper.getTransactions();
      final unfinished = transactions
          .where((tx) => tx.syncStatus == SyncStatus.processing || tx.syncStatus == SyncStatus.failed)
          .toList();

      if (unfinished.isEmpty) return;

      final idsParam = unfinished.map((tx) => tx.id).join(',');
      final url = Uri.parse('$statusUrl?ids=$idsParam');

      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        for (var item in data) {
          final serverTx = TransactionModel.fromMap(item);
          // Update local record if the status changed from processing
          await _dbHelper.updateTransaction(serverTx);
        }
      }
    } catch (e) {
      // Fail silently to prevent user disruption
    }
  }
}
