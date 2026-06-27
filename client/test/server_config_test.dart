import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:client/core/config/server_config_service.dart';

void main() {
  group('ServerConfigService', () {
    late ServerConfigService config;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      config = ServerConfigService();
      config.resetForTest();
      await config.initialize();
    });

    test('starts unconfigured without saved host', () {
      expect(config.isConfigured, isFalse);
      expect(config.baseUrl, isEmpty);
    });

    test('persists server host and builds base URL', () async {
      await config.setServerHost('akhilesh');
      expect(config.getServerHost(), 'akhilesh');
      expect(config.isConfigured, isTrue);
      expect(config.baseUrl, 'http://akhilesh:8080');
      expect(config.healthUrl, 'http://akhilesh:8080/health');
    });

    test('trims whitespace from host', () async {
      await config.setServerHost('  my-server  ');
      expect(config.getServerHost(), 'my-server');
    });
  });
}
