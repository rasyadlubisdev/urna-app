// utils/feedback_utils.dart
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import 'app_config.dart';

class FeedbackUtils {
  static FlutterTts? _flutterTts;
  static bool _isTtsInitialized = false;

  // Initialize TTS
  static Future<void> initializeTts() async {
    if (_isTtsInitialized) return;

    try {
      _flutterTts = FlutterTts();

      // Configure for Indonesian
      await _flutterTts?.setLanguage('id-ID');
      await _flutterTts?.setSpeechRate(0.5);
      await _flutterTts?.setPitch(1.0);
      await _flutterTts?.setVolume(1.0);

      _isTtsInitialized = true;
      print('✅ TTS initialized successfully');
    } catch (e) {
      print('❌ Error initializing TTS: $e');
    }
  }

  // Audio Feedback
  static Future<void> speak(String text) async {
    if (!AppConfig.enableAudioFeedback) return;

    try {
      if (!_isTtsInitialized) {
        await initializeTts();
      }

      await _flutterTts?.stop();
      await _flutterTts?.speak(text);
      print('🗣️ Speaking: $text');
    } catch (e) {
      print('❌ TTS Error: $e');
    }
  }

  static Future<void> stopSpeaking() async {
    try {
      await _flutterTts?.stop();
    } catch (e) {
      print('❌ Error stopping TTS: $e');
    }
  }

  // Haptic Feedback
  static Future<void> vibrate({List<int>? pattern}) async {
    if (!AppConfig.enableVibrationFeedback) return;

    try {
      if (await Vibration.hasVibrator() ?? false) {
        if (pattern != null) {
          await Vibration.vibrate(pattern: pattern);
        } else {
          await Vibration.vibrate(duration: 100);
        }
      } else {
        // Fallback to system haptic feedback
        await HapticFeedback.mediumImpact();
      }
    } catch (e) {
      print('❌ Vibration error: $e');
      // Fallback to system haptic feedback
      await HapticFeedback.mediumImpact();
    }
  }

  static Future<void> heavyVibrate() async {
    if (!AppConfig.enableVibrationFeedback) return;

    try {
      await HapticFeedback.heavyImpact();
    } catch (e) {
      print('❌ Heavy vibration error: $e');
    }
  }

  static Future<void> lightVibrate() async {
    if (!AppConfig.enableVibrationFeedback) return;

    try {
      await HapticFeedback.lightImpact();
    } catch (e) {
      print('❌ Light vibration error: $e');
    }
  }

  // Sound Effects
  static Future<void> playSound(String soundType) async {
    if (!AppConfig.enableAudioFeedback) return;

    try {
      switch (soundType) {
        case 'capture_start':
          await speak('Memulai capture');
          break;
        case 'capture_complete':
          await speak('Capture selesai');
          break;
        case 'microphone_start':
          await speak('Microphone aktif');
          break;
        case 'microphone_stop':
          await speak('Microphone berhenti');
          break;
        case 'authentication_start':
          await speak('Letakkan jari Anda pada sensor');
          break;
        case 'authentication_success':
          await speak('Autentikasi berhasil');
          break;
        case 'authentication_failed':
          await speak('Autentikasi gagal');
          break;
        case 'processing':
          await speak('Sedang memproses');
          break;
        case 'success':
          await speak('Berhasil');
          break;
        case 'error':
          await speak('Terjadi kesalahan');
          break;
        default:
          // No sound for unknown types
          break;
      }
    } catch (e) {
      print('❌ Sound playback error: $e');
    }
  }

  // Combined Feedback
  static Future<void> provideFeedback({
    String? audioMessage,
    String? soundType,
    List<int>? vibrationPattern,
    bool hapticOnly = false,
  }) async {
    try {
      // Vibration feedback
      if (vibrationPattern != null) {
        await vibrate(pattern: vibrationPattern);
      } else if (hapticOnly) {
        await vibrate();
      }

      // Audio feedback
      if (audioMessage != null) {
        await speak(audioMessage);
      } else if (soundType != null) {
        await playSound(soundType);
      }
    } catch (e) {
      print('❌ Combined feedback error: $e');
    }
  }

  // Specific feedback patterns for URNA
  static Future<void> captureStartFeedback() async {
    await provideFeedback(
      soundType: 'capture_start',
      vibrationPattern: [0, 100, 100, 100],
    );
  }

  static Future<void> captureCompleteFeedback() async {
    await provideFeedback(
      soundType: 'capture_complete',
      vibrationPattern: [0, 200, 100, 200],
    );
  }

  static Future<void> microphoneStartFeedback() async {
    await provideFeedback(
      soundType: 'microphone_start',
      vibrationPattern: [0, 50, 50, 50, 50, 50],
    );
  }

  static Future<void> microphoneStopFeedback() async {
    await provideFeedback(
      soundType: 'microphone_stop',
      vibrationPattern: [0, 100, 200, 100],
    );
  }

  static Future<void> processingFeedback() async {
    await provideFeedback(soundType: 'processing', vibrationPattern: [0, 50]);
  }

  static Future<void> successFeedback() async {
    await provideFeedback(
      soundType: 'success',
      vibrationPattern: [0, 100, 100, 100, 100, 100],
    );
  }

  static Future<void> errorFeedback() async {
    await provideFeedback(
      soundType: 'error',
      vibrationPattern: [0, 300, 100, 300],
    );
  }

  // Cleanup
  static Future<void> dispose() async {
    try {
      await _flutterTts?.stop();
      _isTtsInitialized = false;
    } catch (e) {
      print('❌ Error disposing TTS: $e');
    }
  }
}
