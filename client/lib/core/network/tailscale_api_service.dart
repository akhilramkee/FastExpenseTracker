import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/server_config_service.dart';
import '../models/tailscale_device.dart';

class TailscaleApiException implements Exception {
  final String message;
  final int? statusCode;

  const TailscaleApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class TailscaleApiService {
  static const _devicesUrl =
      'https://api.tailscale.com/api/v2/tailnet/-/devices';

  final ServerConfigService _config;

  TailscaleApiService({ServerConfigService? config})
      : _config = config ?? ServerConfigService();

  Future<List<TailscaleDevice>> listTailnetDevices() async {
    final apiKey = await _config.getTailscaleApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw const TailscaleApiException(
        'Add a Tailscale API key in settings to browse your tailnet.',
      );
    }

    final uri = Uri.parse(_devicesUrl).replace(
      queryParameters: const {'fields': 'all'},
    );

    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $apiKey'},
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw TailscaleApiException(
        'Tailscale API key is invalid or expired.',
        statusCode: response.statusCode,
      );
    }

    if (response.statusCode != 200) {
      throw TailscaleApiException(
        'Tailscale API error (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final devices = body['devices'] as List<dynamic>? ?? [];

    final parsed = devices
        .whereType<Map<String, dynamic>>()
        .map(TailscaleDevice.fromApiJson)
        .where((d) => d.hostname.isNotEmpty)
        .toList();

    parsed.sort((a, b) {
      if (a.likelyOnline != b.likelyOnline) {
        return a.likelyOnline ? -1 : 1;
      }
      return a.hostname.toLowerCase().compareTo(b.hostname.toLowerCase());
    });

    return parsed;
  }
}
