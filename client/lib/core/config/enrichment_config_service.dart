import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'server_config_service.dart';

/// Persists OpenRouter credentials locally (manual entry or optional server sync).
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
  bool _inMemoryApiKeyOnly = false;

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    await _seedApiKeyFromBuildDefineIfNeeded();
    _cachedApiKey ??= await _secureStorage.read(key: _apiKeyStorageKey);
  }

  /// One-time migration: if [OPENROUTER_API_KEY] was passed at build time and no
  /// saved key exists yet, use it as the initial default.
  Future<void> _seedApiKeyFromBuildDefineIfNeeded() async {
    const buildKey = String.fromEnvironment('OPENROUTER_API_KEY');
    if (buildKey.isEmpty) return;
    final existing = await _secureStorage.read(key: _apiKeyStorageKey);
    if (existing != null && existing.isNotEmpty) return;
    await setOpenRouterApiKey(buildKey);
  }

  /// Applies OpenRouter settings fetched from the sync server.
  ///
  /// Updates the local API key only when the server provides one; a manually
  /// stored key is kept if the server has no OpenRouter configuration.
  Future<bool> applyFromServer({
    required bool configured,
    String? apiKey,
    required String model,
  }) async {
    await setOpenRouterModel(model);
    if (configured && apiKey != null && apiKey.trim().isNotEmpty) {
      await setOpenRouterApiKey(apiKey);
      return true;
    }
    return isConfigured;
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
    if (_inMemoryApiKeyOnly) return _cachedApiKey;
    _cachedApiKey ??= await _secureStorage.read(key: _apiKeyStorageKey);
    return _cachedApiKey;
  }

  Future<void> setOpenRouterApiKey(String? key) async {
    final trimmed = key?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      _cachedApiKey = null;
      if (_inMemoryApiKeyOnly) return;
      await _secureStorage.delete(key: _apiKeyStorageKey);
      return;
    }
    _cachedApiKey = trimmed;
    if (_inMemoryApiKeyOnly) return;
    await _secureStorage.write(key: _apiKeyStorageKey, value: trimmed);
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
    _inMemoryApiKeyOnly = false;
  }

  @visibleForTesting
  void enableInMemoryApiKeyForTest() {
    _inMemoryApiKeyOnly = true;
  }

  @visibleForTesting
  Future<void> bindPrefsForTest(SharedPreferences prefs) async {
    _prefs = prefs;
  }
}
