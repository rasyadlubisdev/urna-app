// services/biometric_service.dart
import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';
import '../utils/feedback_utils.dart';

class BiometricService {
  static final LocalAuthentication _localAuth = LocalAuthentication();

  static Future<bool> isAvailable() async {
    try {
      final bool isSupported = await _localAuth.isDeviceSupported();
      final bool canCheckBiometrics = await _localAuth.canCheckBiometrics;
      final bool isAvailable = isSupported && canCheckBiometrics;

      print('📱 Biometric availability: $isAvailable');
      return isAvailable;
    } catch (e) {
      print('❌ Error checking biometric availability: $e');
      return false;
    }
  }

  static Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      print('❌ Error getting available biometrics: $e');
      return [];
    }
  }

  static Future<bool> authenticateForRegistration() async {
    try {
      print('🔐 Starting biometric authentication for registration...');

      await FeedbackUtils.playSound('authentication_start');
      await FeedbackUtils.vibrate();

      final bool didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Daftarkan sidik jari Anda untuk URNA',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      if (didAuthenticate) {
        print('✅ Biometric registration authentication successful');
        await FeedbackUtils.playSound('authentication_success');
        await FeedbackUtils.vibrate(pattern: [100, 200, 100]);
      } else {
        print('❌ Biometric registration authentication failed');
        await FeedbackUtils.playSound('authentication_failed');
      }

      return didAuthenticate;
    } on PlatformException catch (e) {
      print('❌ Platform exception during biometric auth: $e');
      await FeedbackUtils.playSound('authentication_failed');
      return false;
    } catch (e) {
      print('❌ Error during biometric authentication: $e');
      await FeedbackUtils.playSound('authentication_failed');
      return false;
    }
  }

  static Future<bool> authenticateForLogin() async {
    try {
      print('🔐 Starting biometric authentication for login...');

      await FeedbackUtils.playSound('authentication_start');
      await FeedbackUtils.vibrate();

      final bool didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Masuk ke URNA dengan sidik jari Anda',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      if (didAuthenticate) {
        print('✅ Biometric login authentication successful');
        await FeedbackUtils.playSound('authentication_success');
        await FeedbackUtils.vibrate(pattern: [100, 200, 100]);
      } else {
        print('❌ Biometric login authentication failed');
        await FeedbackUtils.playSound('authentication_failed');
      }

      return didAuthenticate;
    } on PlatformException catch (e) {
      print('❌ Platform exception during biometric auth: $e');
      await FeedbackUtils.playSound('authentication_failed');
      return false;
    } catch (e) {
      print('❌ Error during biometric authentication: $e');
      await FeedbackUtils.playSound('authentication_failed');
      return false;
    }
  }

  static Future<void> cancelAuthentication() async {
    try {
      await _localAuth.stopAuthentication();
      print('🚫 Biometric authentication cancelled');
    } catch (e) {
      print('⚠️ Error cancelling biometric authentication: $e');
    }
  }
}
