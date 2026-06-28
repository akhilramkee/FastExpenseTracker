import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'server_config_service.dart';

/// Persists OpenRouter credentials synced from the tailnet server.
class EnrichmentConfigService {
  static const _apiKeyStorageKey = 'openrouter_api_key';
  static const _modelKey = 'openrouter_model';
  static const defaultModel = 'openrouter/free';
  static const defaultUrl = 'https://openrouter.ai/api/v1/chat/completions';

  static final EnrichmentConfigService _instance = EnrichmentConfigService._internal();
  factory EnrichmentConfigService() => _instance;
  EnrichmentConfigService._internal();

  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  SharedPreferences? _prefs;
  String? _cachedApiKey;

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// Applies OpenRouter settings fetched from the sync server.
  Future<bool> applyFromServer({
    required bool configured,
    String? apiKey,
    required String model,
  }) async {
    await setOpenRouterModel(model);
    if (!configured || apiKey == null || apiKey.trim().isEmpty) {
      await setOpenRouterApiKey(null);
      return false;
    }
    await setOpenRouterApiKey(apiKey);
    return true;
  }

  /// Fetches OpenRouter settings from the tailnet server and caches them locally.
  Future<bool> syncFromServer(ServerConfigService serverConfig) async {
    final url = serverConfig.enrichmentConfigUrl;
    if (url.isEmpty) return false;

    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return false;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return applyFromServer(
        configured: data['configured'] == true,
        apiKey: data['openrouter_api_key'] as String?,
        model: data['openrouter_model'] as String? ?? defaultModel,
      );
    } catch (_) {
      return false;
    }
  }

  Future<String?> getOpenRouterApiKey() async {
    _cachedApiKey ??= await _secureStorage.read(key: _apiKeyStorageKey);
    return _cachedApiKey;
  }

  Future<void> setOpenRouterApiKey(String? key) async {
    final trimmed = key?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      await _secureStorage.delete(key: _apiKeyStorageKey);
      _cachedApiKey = null;
      return;
    }
    await _secureStorage.write(key: _apiKeyStorageKey, value: trimmed);
    _cachedApiKey = trimmed;
  }

  String getOpenRouterModel() =>
      _prefs?.getString(_modelKey) ?? defaultModel;

  Future<void> setOpenRouterModel(String model) async {
    final trimmed = model.trim();
    await _prefs?.setString(
      _modelKey,
      trimmed.isEmpty ? defaultModel : trimmed,
    );
  }

  bool isFreeModel(String model) =>
      model == defaultModel || model.endsWith(':free');

  Future<bool> get isConfigured async {
    final key = await getOpenRouterApiKey();
    if (key == null || key.isEmpty) return false;
    return isFreeModel(getOpenRouterModel());
  }

  @visibleForTesting
  void resetForTest() {
    _prefs = null;
    _cachedApiKey = null;
  }

  @visibleForTesting
  Future<void> bindPrefsForTest(SharedPreferences prefs) async {
    _prefs = prefs;
  }
}
