// utils/app_config.dart
class AppConfig {
  // Development flags for flexibility
  static const bool isDevelopmentMode = false;
  static const bool isBackendAuthReady =
      false; // Toggle when backend auth is ready
  static const bool isEmulatorMode = true; // Toggle for emulator vs real device

  // Backend configuration
  static const String baseUrl = "https://lifedebugger-urna-backend.hf.space";
  static const String predictEndpoint = "/api/v1/predict";
  static const String authEndpoint = "/api/v1/auth"; // For future use

  // Turnstile configuration
  static const String turnstileSiteKey =
      '0x4AAAAAABhz1K9KeD4BHNPK'; // Testing key
  static const String turnstileBaseUrl = 'https://www.spuun.art';

  // Audio settings
  static const Duration longPressDuration = Duration(seconds: 3);
  static const Duration tapTimeout = Duration(milliseconds: 800);
  static const int tripleTapCount = 3;

  // Feedback settings
  static const bool enableHapticFeedback = true;
  static const bool enableAudioFeedback = true;
  static const bool enableVibrationFeedback = true;

  // Camera settings
  static const String captureImageFormat = 'jpg';
  static const String audioRecordingFormat = 'mp3';
  static const String audioFieldName = 'audio_file';

  // Local test image path (for emulator mode)
  static const String testImagePath = '../assets/test_image.jpg';
}
