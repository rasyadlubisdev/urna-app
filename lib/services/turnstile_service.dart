// services/turnstile_service.dart
import 'package:cloudflare_turnstile/cloudflare_turnstile.dart';
import '../utils/app_config.dart';

class TurnstileService {
  static Future<String> getToken() async {
    print('🔄 Starting Turnstile token generation...');

    final turnstile = CloudflareTurnstile.invisible(
      siteKey: AppConfig.turnstileSiteKey,
      baseUrl: AppConfig.turnstileBaseUrl,
    );

    try {
      final token = await turnstile.getToken();

      if (token == null) {
        throw TurnstileException('Token received from Cloudflare is null');
      }

      print('✅ Turnstile token generated successfully');
      return token;
    } on TurnstileException {
      rethrow;
    } catch (e) {
      throw TurnstileException('Failed to get Turnstile token: $e');
    } finally {
      print('🧹 Disposing Turnstile instance...');
      turnstile.dispose();
    }
  }
}
