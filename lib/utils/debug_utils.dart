import '../utils/app_config.dart';

class DebugUtils {
  static void logTurnstileConfiguration() {
    print('\n🔧 TURNSTILE CONFIGURATION DEBUG:');
    print('Site Key: ${AppConfig.turnstileSiteKey}');
    print('Base URL: ${AppConfig.turnstileBaseUrl}');
    print('Development Mode: ${AppConfig.isDevelopmentMode}');
    print('Backend Auth Ready: ${AppConfig.isBackendAuthReady}');
    print('Emulator Mode: ${AppConfig.isEmulatorMode}');
    print('=' * 50);
  }

  static void logError(String context, dynamic error) {
    print('\n❌ ERROR in $context:');
    print('Error: $error');
    print('Timestamp: ${DateTime.now()}');
    print('=' * 50);
  }

  static void logSuccess(String context, String message) {
    print('\n✅ SUCCESS in $context:');
    print('Message: $message');
    print('Timestamp: ${DateTime.now()}');
    print('=' * 50);
  }
}
