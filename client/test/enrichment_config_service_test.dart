import 'package:client/core/config/enrichment_config_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EnrichmentConfigService.applyFromServer', () {
    late EnrichmentConfigService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      service = EnrichmentConfigService();
      service.resetForTest();
      service.enableInMemoryApiKeyForTest();
      await service.bindPrefsForTest(await SharedPreferences.getInstance());
      await service.setOpenRouterApiKey('local-device-key');
    });

    test('keeps local API key when server has no OpenRouter config', () async {
      final configured = await service.applyFromServer(
        configured: false,
        apiKey: null,
        model: 'openrouter/free',
      );

      expect(configured, isTrue);
      expect(await service.getOpenRouterApiKey(), 'local-device-key');
    });

    test('overwrites local key when server provides one', () async {
      await service.applyFromServer(
        configured: true,
        apiKey: 'server-key',
        model: 'meta-llama/llama-3.2-3b-instruct:free',
      );

      expect(await service.getOpenRouterApiKey(), 'server-key');
      expect(service.getOpenRouterModel(), 'meta-llama/llama-3.2-3b-instruct:free');
    });
  });
}
