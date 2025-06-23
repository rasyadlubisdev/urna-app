import 'dart:async';
import 'dart:io';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/feedback_utils.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';

class AudioServiceRecord {
  static AudioRecorder? _recorder;
  static AudioPlayer? _audioPlayer;
  static bool _isRecorderInitialized = false;
  static bool _isPlayerInitialized = false;
  static bool _isRecording = false;
  static bool _isPlaying = false;
  static String? _currentRecordingPath;
  static String? _currentPlayingPath;
  static StreamSubscription? _playerCompleteSubscription;

  // Initialize audio services'
  static Future<void> initialize() async {
    try {
      await _initializeRecorder();
      await _initializePlayer();
      print('✅ Record audio service initialized successfully');
    } catch (e) {
      print('❌ Error initializing record audio service: $e');
    }
  }

  static Future<void> _initializeRecorder() async {
    if (_isRecorderInitialized) return;

    try {
      _recorder = AudioRecorder();
      _isRecorderInitialized = true;
      print('✅ Record audio recorder initialized');
    } catch (e) {
      print('❌ Error initializing record recorder: $e');
    }
  }

  static Future<void> _initializePlayer() async {
    if (_isPlayerInitialized) return;

    try {
      _audioPlayer = AudioPlayer();
      _isPlayerInitialized = true;
      print('✅ Record audio player initialized');
    } catch (e) {
      print('❌ Error initializing record player: $e');
    }
  }

  // Check and request microphone permission
  static Future<bool> checkMicrophonePermission() async {
    try {
      final status = await Permission.microphone.status;
      print('🎤 Microphone permission status: $status');

      if (status.isGranted) {
        return true;
      } else if (status.isDenied) {
        final result = await Permission.microphone.request();
        print('🎤 Permission request result: $result');
        return result.isGranted;
      } else if (status.isPermanentlyDenied) {
        print('❌ Microphone permission permanently denied');
        return false;
      }

      return false;
    } catch (e) {
      print('❌ Error checking microphone permission: $e');
      return false;
    }
  }

  // Start recording audio
  static Future<bool> startRecording() async {
    if (_isRecording) {
      print('⚠️ Already recording');
      return false;
    }

    try {
      print('🎤 Starting recording process...');

      // Check permission first
      final hasPermission = await checkMicrophonePermission();
      if (!hasPermission) {
        await FeedbackUtils.speak('Izin microphone diperlukan untuk merekam');
        print('❌ No microphone permission');
        return false;
      }

      // Initialize if needed
      if (!_isRecorderInitialized) {
        await _initializeRecorder();
      }

      // Check if recorder is available
      final isSupported = await _recorder!.hasPermission();
      if (!isSupported) {
        print('❌ Recorder not supported or no permission');
        await FeedbackUtils.speak(
          'Perekaman tidak didukung pada perangkat ini',
        );
        return false;
      }

      // Generate recording path
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentRecordingPath = '${directory.path}/urna_audio_$timestamp.m4a';

      print('🎤 Recording to: $_currentRecordingPath');

      // Start recording with most compatible settings
      await _recorder!.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: _currentRecordingPath!,
      );

      _isRecording = true;
      print('✅ Recording started successfully!');

      // Provide feedback
      await FeedbackUtils.microphoneStartFeedback();

      return true;
    } catch (e) {
      print('❌ Error starting recording: $e');
      print('❌ Error type: ${e.runtimeType}');
      await FeedbackUtils.errorFeedback();
      await FeedbackUtils.speak('Gagal memulai perekaman: $e');
      return false;
    }
  }

  // Stop recording audio
  static Future<File?> stopRecording() async {
    if (!_isRecording) {
      print('⚠️ Not currently recording');
      return null;
    }

    try {
      print('🛑 Stopping recording...');

      final path = await _recorder!.stop();
      _isRecording = false;

      print('🛑 Recording stopped. Path: $path');

      // Provide feedback
      await FeedbackUtils.microphoneStopFeedback();

      if (path != null) {
        final file = File(path);
        if (await file.exists()) {
          final fileSize = await file.length();
          print('📁 Recorded file size: $fileSize bytes');

          if (fileSize > 1000) {
            // Check if file has content
            return file;
          } else {
            print('⚠️ Recorded file too small: $fileSize bytes');
            return null;
          }
        } else {
          print('❌ Recorded file does not exist');
        }
      }

      return null;
    } catch (e) {
      print('❌ Error stopping recording: $e');
      await FeedbackUtils.errorFeedback();
      return null;
    }
  }

  // Pause audio playback
  static Future<void> pausePlaying() async {
    try {
      if (_isPlaying && _audioPlayer != null) {
        await _audioPlayer!.pause();
        print('⏸️ Audio paused');
      }
    } catch (e) {
      print('❌ Error pausing audio: $e');
    }
  }

  // Resume audio playback
  static Future<void> resumePlaying() async {
    try {
      if (_audioPlayer != null) {
        await _audioPlayer!.resume();
        print('▶️ Audio resumed');
      }
    } catch (e) {
      print('❌ Error resuming audio: $e');
    }
  }

  // Get current states
  static bool get isRecording => _isRecording;
  static bool get isPlaying => _isPlaying;
  static String? get currentRecordingPath => _currentRecordingPath;
  static String? get currentPlayingPath => _currentPlayingPath;

  // Play audio from base64 data
  // REVISI 2: Tambahkan parameter callback onComplete.
  static Future<bool> playAudioFromBase64(
    String base64Data, {
    VoidCallback? onComplete,
  }) async {
    try {
      print('🔊 Playing audio from base64 data...');

      if (!_isPlayerInitialized) {
        await _initializePlayer();
      }

      if (_isPlaying) {
        await stopPlaying();
      }

      // Batalkan listener sebelumnya untuk menghindari panggilan ganda
      await _playerCompleteSubscription?.cancel();

      final bytes = base64Decode(base64Data);
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final tempFile = File('${directory.path}/temp_response_$timestamp.mp3');

      await tempFile.writeAsBytes(bytes);
      print('📁 Temp audio file created: ${tempFile.path}');

      await _audioPlayer!.play(DeviceFileSource(tempFile.path));
      _isPlaying = true;

      print('🔊 Audio playback started');

      // Dengarkan event selesai
      _playerCompleteSubscription = _audioPlayer!.onPlayerComplete.listen((_) {
        _isPlaying = false;
        print('✅ Audio playback completed');
        // Panggil callback jika ada.
        onComplete?.call();
      });

      _audioPlayer!.onPlayerStateChanged.listen((state) {
        if (state == PlayerState.stopped || state == PlayerState.completed) {
          if (_isPlaying) {
            _isPlaying = false;
            onComplete?.call();
          }
        }
      });

      return true;
    } catch (e) {
      print('❌ Error playing audio from base64: $e');
      _isPlaying = false;
      // Panggil callback juga jika terjadi error agar UI tidak stuck.
      onComplete?.call();
      return false;
    }
  }

  // Stop audio playback
  static Future<void> stopPlaying() async {
    try {
      if (_audioPlayer != null) {
        await _audioPlayer!.stop();
        _isPlaying = false;
        // Batalkan listener saat dihentikan manual
        await _playerCompleteSubscription?.cancel();
        print('🛑 Audio stopped');
      }
    } catch (e) {
      print('❌ Error stopping audio: $e');
    }
  }

  // Dispose audio services
  static Future<void> dispose() async {
    try {
      if (_isRecording) {
        await stopRecording();
      }

      if (_isPlaying) {
        await stopPlaying();
      }

      await _playerCompleteSubscription?.cancel();
      await _recorder?.dispose();
      await _audioPlayer?.dispose();

      _isRecorderInitialized = false;
      _isPlayerInitialized = false;

      print('🧹 Record audio service disposed');
    } catch (e) {
      print('❌ Error disposing record audio service: $e');
    }
  }
}
