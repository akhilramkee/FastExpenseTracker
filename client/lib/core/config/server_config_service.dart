import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists sync server host and optional Tailscale API credentials.
class ServerConfigService {
  static const _hostKey = 'server_host';
  static const _portKey = 'server_port';
  static const _apiKeyStorageKey = 'tailscale_api_key';
  static const defaultPort = 8080;

  static final ServerConfigService _instance = ServerConfigService._internal();
  factory ServerConfigService() => _instance;
  ServerConfigService._internal();

  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  SharedPreferences? _prefs;
  String? _cachedApiKey;

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    await _seedHostFromBuildDefineIfNeeded();
  }

  /// One-time migration: if [SERVER_HOST] was passed at build time and no
  /// saved host exists yet, use it as the initial default.
  Future<void> _seedHostFromBuildDefineIfNeeded() async {
    const buildHost = String.fromEnvironment('SERVER_HOST');
    if (buildHost.isEmpty) return;
    if (getServerHost().isNotEmpty) return;
    await setServerHost(buildHost);
  }

  String getServerHost() => _prefs?.getString(_hostKey) ?? '';

  int getServerPort() => _prefs?.getInt(_portKey) ?? defaultPort;

  Future<void> setServerHost(String host) async {
    await _prefs?.setString(_hostKey, host.trim());
  }

  Future<void> setServerPort(int port) async {
    await _prefs?.setInt(_portKey, port);
  }

  bool get isConfigured => getServerHost().isNotEmpty;

  String get baseUrl {
    final host = getServerHost();
    if (host.isEmpty) return '';
    return 'http://$host:${getServerPort()}';
  }

  String get healthUrl => baseUrl.isEmpty ? '' : '$baseUrl/health';

  String get syncUrl => baseUrl.isEmpty ? '' : '$baseUrl/api/v1/sync';

  String get deletesUrl => baseUrl.isEmpty ? '' : '$baseUrl/api/v1/sync/deletes';

  String get statusUrl => baseUrl.isEmpty ? '' : '$baseUrl/api/v1/sync/status';

  String get importUrl => baseUrl.isEmpty ? '' : '$baseUrl/api/v1/import';

  String transactionUrl(String id) =>
      baseUrl.isEmpty ? '' : '$baseUrl/api/v1/transactions/$id';

  Future<String?> getTailscaleApiKey() async {
    _cachedApiKey ??= await _secureStorage.read(key: _apiKeyStorageKey);
    return _cachedApiKey;
  }

  Future<void> setTailscaleApiKey(String? key) async {
    final trimmed = key?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      await _secureStorage.delete(key: _apiKeyStorageKey);
      _cachedApiKey = null;
      return;
    }
    await _secureStorage.write(key: _apiKeyStorageKey, value: trimmed);
    _cachedApiKey = trimmed;
  }

  bool get hasTailscaleApiKey =>
      _cachedApiKey != null && _cachedApiKey!.isNotEmpty;

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
