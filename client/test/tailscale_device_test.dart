import 'package:flutter_test/flutter_test.dart';
import 'package:client/core/models/tailscale_device.dart';

void main() {
  group('TailscaleDevice', () {
    test('fromApiJson uses hostname for MagicDNS short name', () {
      final device = TailscaleDevice.fromApiJson({
        'hostname': 'akhilesh',
        'name': 'akhilesh.tail1234.ts.net',
        'os': 'linux',
        'authorized': true,
        'lastSeen': DateTime.now().toUtc().toIso8601String(),
        'clientConnectivity': {
          'endpoints': ['100.64.0.1:41641'],
        },
      });

      expect(device.hostname, 'akhilesh');
      expect(device.magicDnsName, 'akhilesh.tail1234.ts.net');
      expect(device.likelyOnline, isTrue);
    });

    test('fromApiJson falls back to DNS short name when hostname missing', () {
      final device = TailscaleDevice.fromApiJson({
        'name': 'macbook.tail1234.ts.net',
        'os': 'macOS',
      });

      expect(device.hostname, 'macbook');
    });
  });
}
