import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/config/server_config_service.dart';
import '../core/models/tailscale_device.dart';
import '../core/network/sync_worker.dart';
import '../core/network/tailscale_api_service.dart';

class ServerSettingsSheet extends StatefulWidget {
  final ServerConfigService config;
  final SyncWorker syncWorker;
  final VoidCallback? onSaved;

  const ServerSettingsSheet({
    super.key,
    required this.config,
    required this.syncWorker,
    this.onSaved,
  });

  static Future<bool?> show(
    BuildContext context, {
    required ServerConfigService config,
    required SyncWorker syncWorker,
    VoidCallback? onSaved,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1F30),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ServerSettingsSheet(
          config: config,
          syncWorker: syncWorker,
          onSaved: onSaved,
        ),
      ),
    );
  }

  @override
  State<ServerSettingsSheet> createState() => _ServerSettingsSheetState();
}

class _ServerSettingsSheetState extends State<ServerSettingsSheet> {
  late final TextEditingController _hostController;
  late final TextEditingController _apiKeyController;
  final TailscaleApiService _tailscaleApi = TailscaleApiService();

  List<TailscaleDevice> _devices = [];
  bool _loadingDevices = false;
  bool _testingConnection = false;
  bool? _connectionOk;
  String? _deviceError;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _hostController = TextEditingController(text: widget.config.getServerHost());
    _apiKeyController = TextEditingController();
    _loadApiKey();
  }

  Future<void> _loadApiKey() async {
    final key = await widget.config.getTailscaleApiKey();
    if (!mounted) return;
    if (key != null && key.isNotEmpty) {
      _apiKeyController.text = key;
    }
  }

  @override
  void dispose() {
    _hostController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _saveHost({bool closeOnSuccess = false}) async {
    final host = _hostController.text.trim();
    if (host.isEmpty) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Enter a server hostname.';
        _connectionOk = false;
      });
      return;
    }

    await widget.config.setServerHost(host);
    if (!mounted) return;

    if (closeOnSuccess) {
      Navigator.of(context).pop(true);
      return;
    }

    setState(() {
      _connectionOk = null;
      _statusMessage = 'Server host saved.';
    });
    widget.onSaved?.call();
  }

  Future<void> _saveAndClose() async {
    await _saveApiKey();
    await _saveHost(closeOnSuccess: true);
  }

  Future<void> _saveApiKey() async {
    await widget.config.setTailscaleApiKey(_apiKeyController.text);
    if (!mounted) return;
    setState(() {
      _deviceError = null;
      _statusMessage = 'Tailscale API key saved.';
    });
  }

  Future<void> _testConnection() async {
    await _saveHost();
    setState(() {
      _testingConnection = true;
      _connectionOk = null;
      _statusMessage = null;
    });

    final ok = await widget.syncWorker.isServerReachable();
    var enrichmentSynced = false;
    if (ok) {
      enrichmentSynced = await widget.syncWorker.syncEnrichmentConfig(
        skipReachabilityCheck: true,
      );
    }
    if (!mounted) return;
    setState(() {
      _testingConnection = false;
      _connectionOk = ok;
      if (!ok) {
        _statusMessage = 'Could not reach ${widget.config.baseUrl}/health';
      } else if (enrichmentSynced) {
        _statusMessage =
            'Server reachable. OpenRouter enrichment config synced from server.';
      } else {
        _statusMessage =
            'Server reachable at ${widget.config.baseUrl}. '
            'No OpenRouter key on server — Ollama fallback will be used.';
      }
    });
  }

  Future<void> _refreshDevices() async {
    await _saveApiKey();
    setState(() {
      _loadingDevices = true;
      _deviceError = null;
      _statusMessage = null;
    });

    try {
      final devices = await _tailscaleApi.listTailnetDevices();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _loadingDevices = false;
      });
    } on TailscaleApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingDevices = false;
        _deviceError = e.message;
        _devices = [];
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingDevices = false;
        _deviceError = 'Failed to load tailnet devices.';
        _devices = [];
      });
    }
  }

  Future<void> _selectDevice(TailscaleDevice device) async {
    _hostController.text = device.hostname;
    await _saveApiKey();
    await _saveHost(closeOnSuccess: true);
  }

  @override
  Widget build(BuildContext context) {
    final selectedHost = widget.config.getServerHost();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Sync Server',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.white70),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Choose the Tailscale device running your expense API (port ${ServerConfigService.defaultPort}).',
              style: TextStyle(color: Colors.grey[400], fontSize: 13),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _hostController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Server hostname',
                hintText: 'e.g. akhilesh',
                labelStyle: TextStyle(color: Colors.grey[400]),
                hintStyle: TextStyle(color: Colors.grey[600]),
                filled: true,
                fillColor: const Color(0xFF0F101A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              inputFormatters: [
                FilteringTextInputFormatter.deny(RegExp(r'\s')),
              ],
              onSubmitted: (_) => _saveAndClose(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _testingConnection ? null : _testConnection,
                    icon: _testingConnection
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_tethering, size: 18),
                    label: const Text('Test connection'),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _saveAndClose,
                  child: const Text('Save'),
                ),
              ],
            ),
            if (_statusMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _statusMessage!,
                style: TextStyle(
                  color: _connectionOk == false ? Colors.redAccent : Colors.greenAccent,
                  fontSize: 13,
                ),
              ),
            ],
            const SizedBox(height: 28),
            const Text(
              'Tailnet devices',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Paste a Tailscale API key to list devices on your tailnet. '
              'OpenRouter enrichment is configured on the server and synced automatically. '
              'Generate a Tailscale key at login.tailscale.com/admin/settings/keys',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _apiKeyController,
              style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Tailscale API key',
                hintText: 'tskey-api-...',
                labelStyle: TextStyle(color: Colors.grey[400]),
                filled: true,
                fillColor: const Color(0xFF0F101A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loadingDevices ? null : _refreshDevices,
              icon: _loadingDevices
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh tailnet devices'),
            ),
            if (_deviceError != null) ...[
              const SizedBox(height: 12),
              Text(
                _deviceError!,
                style: const TextStyle(color: Colors.orangeAccent, fontSize: 13),
              ),
            ],
            const SizedBox(height: 12),
            if (_devices.isEmpty && !_loadingDevices)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No devices loaded yet.',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
              )
            else
              ..._devices.map((device) {
                final isSelected =
                    device.hostname.toLowerCase() == selectedHost.toLowerCase();
                return Card(
                  color: isSelected
                      ? const Color(0xFF8B5CF6).withValues(alpha: 0.15)
                      : const Color(0xFF0F101A),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    onTap: () => _selectDevice(device),
                    leading: Icon(
                      device.likelyOnline ? Icons.circle : Icons.circle_outlined,
                      color: device.likelyOnline ? Colors.greenAccent : Colors.grey,
                      size: 14,
                    ),
                    title: Text(
                      device.hostname,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      '${device.os}${device.magicDnsName.isNotEmpty ? ' · ${device.magicDnsName}' : ''}',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle, color: Color(0xFF8B5CF6))
                        : const Icon(Icons.chevron_right, color: Colors.white38),
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}
