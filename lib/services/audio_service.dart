// services/audio_service.dart
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart' as audioplayers;
import 'package:audioplayers/audioplayers.dart';
import '../utils/feedback_utils.dart';
import '../utils/app_config.dart';

class AudioService {
  static final AudioRecorder _recorder = AudioRecorder();
  static AudioPlayer? _audioPlayer;
  static bool _isRecorderInitialized = false;
  static bool _isPlayerInitialized = false;
  static bool _isRecording = false;
  static bool _isPlaying = false;
  static String? _currentRecordingPath;
  static String? _currentPlayingPath;
  static DateTime? _recordingStartTime;
  static Timer? _recordingTimer;
  static StreamController<Duration>? _durationController;
  static StreamSubscription<Amplitude>? _amplitudeSubscription;

  // M4A (AAC) recording with record library
  static const String _recordingFormat = 'm4a';
  static const String _outputFormat = 'm4a';

  // Initialize audio services
  static Future<void> initialize() async {
    try {
      print('🎵 Initializing audio services (record library - M4A)...');
      await _initializeRecorder();
      await _initializePlayer();
      print('✅ Audio service initialized successfully');
    } catch (e) {
      print('❌ Error initializing audio service: $e');
    }
  }

  static Future<void> _initializeRecorder() async {
    if (_isRecorderInitialized) return;

    try {
      print('🎤 Initializing M4A audio recorder...');

      // Check permission first
      final hasPermission = await checkMicrophonePermission();
      if (!hasPermission) {
        print('⚠️ Microphone permission denied, recorder not initialized');
        return;
      }

      // Check if recording is supported
      final isSupported = await _recorder.hasPermission();
      if (!isSupported) {
        print('⚠️ Recording not supported on this device');
        return;
      }

      _isRecorderInitialized = true;
      print('✅ M4A audio recorder initialized');
    } catch (e) {
      print('❌ Error initializing recorder: $e');
      _isRecorderInitialized = false;
    }
  }

  static Future<void> _initializePlayer() async {
    if (_isPlayerInitialized) return;

    try {
      print('🔊 Initializing audio player...');
      _audioPlayer = audioplayers.AudioPlayer();
      _isPlayerInitialized = true;
      print('✅ Audio player initialized');
    } catch (e) {
      print('❌ Error initializing player: $e');
      _isPlayerInitialized = false;
      _audioPlayer = null;
    }
  }

  // Check and request microphone permission
  static Future<bool> checkMicrophonePermission() async {
    try {
      print('🔒 Checking microphone permission...');

      final status = await Permission.microphone.status;
      if (status.isGranted) {
        print('✅ Microphone permission already granted');
        return true;
      }

      if (status.isDenied || status.isRestricted) {
        print('❓ Requesting microphone permission...');
        final result = await Permission.microphone.request();

        if (result.isGranted) {
          print('✅ Microphone permission granted');
          return true;
        } else {
          print('❌ Microphone permission denied');
          return false;
        }
      }

      if (status.isPermanentlyDenied) {
        print('🚫 Microphone permission permanently denied');
        return false;
      }

      return false;
    } catch (e) {
      print('❌ Error checking microphone permission: $e');
      return false;
    }
  }

  // Generate file path for recording
  static Future<String> _getRecordingFilePath() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final recordPath = "${directory.path}/urna_recordings";

      final recordDirectory = Directory(recordPath);
      if (!recordDirectory.existsSync()) {
        recordDirectory.createSync(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = "urna_recording_$timestamp.$_recordingFormat";
      final fullPath = "$recordPath/$fileName";

      print('📁 Recording path: $fullPath');
      return fullPath;
    } catch (e) {
      print('❌ Error generating recording path: $e');
      rethrow;
    }
  }

  // Start recording audio in M4A format
  static Future<bool> startRecording() async {
    if (_isRecording) {
      print('⚠️ Already recording');
      return false;
    }

    try {
      print('🎤 Starting M4A audio recording...');

      // Check permission
      final hasPermission = await checkMicrophonePermission();
      if (!hasPermission) {
        print('❌ No microphone permission');
        return false;
      }

      // Initialize recorder if needed
      if (!_isRecorderInitialized) {
        await _initializeRecorder();
      }

      if (!_isRecorderInitialized) {
        print('❌ Recorder not initialized');
        return false;
      }

      // Check if device supports recording
      final canRecord = await _recorder.hasPermission();
      if (!canRecord) {
        print('❌ Recording not supported or no permission');
        return false;
      }

      // Generate recording path
      _currentRecordingPath = await _getRecordingFilePath();

      // Start recording with AAC configuration
      await _recorder.start(
        RecordConfig(
          encoder: AudioEncoder.aacLc, // AAC-LC encoder for M4A
          bitRate: 128000, // 128 kbps
          sampleRate: 44100, // 44.1 kHz
          numChannels: 1, // Mono for smaller file size
        ),
        path: _currentRecordingPath!,
      );

      _isRecording = true;
      _recordingStartTime = DateTime.now();
      print('✅ M4A recording started successfully');

      // Start duration tracking
      _startDurationTracking();

      // Start amplitude monitoring
      _startAmplitudeMonitoring();

      return true;
    } catch (e) {
      print('❌ Error starting recording: $e');
      _isRecording = false;
      _currentRecordingPath = null;
      _recordingStartTime = null;
      return false;
    }
  }

  // Start duration tracking
  static void _startDurationTracking() {
    _durationController = StreamController<Duration>.broadcast();
    _recordingTimer = Timer.periodic(const Duration(milliseconds: 500), (
      timer,
    ) {
      if (_isRecording && _recordingStartTime != null) {
        final duration = DateTime.now().difference(_recordingStartTime!);
        _durationController?.add(duration);

        // Log every 5 seconds
        if (duration.inSeconds % 5 == 0 &&
            duration.inMilliseconds % 1000 < 500) {
          print('🎤 M4A Recording: ${duration.inSeconds}s');
        }
      }
    });
  }

  // Start amplitude monitoring for visual feedback (fixed API)
  static void _startAmplitudeMonitoring() {
    try {
      _amplitudeSubscription = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 200))
          .listen((amplitude) {
            // Can be used for visual amplitude display
            // amplitude.current contains the current amplitude value
          });
    } catch (e) {
      print('⚠️ Amplitude monitoring not supported: $e');
    }
  }

  // Stop recording and return M4A file
  static Future<File?> stopRecording() async {
    if (!_isRecording) {
      print('⚠️ Not currently recording');
      return null;
    }

    try {
      print('🛑 Stopping M4A audio recording...');

      // Stop the recording
      final recordedPath = await _recorder.stop();

      // Stop duration tracking
      _recordingTimer?.cancel();
      _recordingTimer = null;
      await _durationController?.close();
      _durationController = null;

      // Stop amplitude monitoring
      await _amplitudeSubscription?.cancel();
      _amplitudeSubscription = null;

      _isRecording = false;
      final recordingDuration = _recordingStartTime != null
          ? DateTime.now().difference(_recordingStartTime!)
          : Duration.zero;
      _recordingStartTime = null;

      if (recordedPath != null) {
        final recordedFile = File(recordedPath);

        if (await recordedFile.exists()) {
          final fileSize = await recordedFile.length();
          print('📁 Recorded M4A file: $recordedPath');
          print('📏 File size: $fileSize bytes');
          print('📊 Recording duration: ${recordingDuration.inSeconds}s');

          if (fileSize > 1000) {
            // Validate M4A file
            final bytes = await recordedFile.readAsBytes();
            final isValidM4a = _isValidM4aFile(bytes);
            print('🔍 M4A validation: $isValidM4a');

            if (isValidM4a) {
              print('✅ Valid M4A file created');
              return recordedFile;
            } else {
              print(
                '⚠️ File created but M4A validation failed - still returning file',
              );
              return recordedFile; // Still return, might work
            }
          } else {
            print('❌ Recorded file too small: $fileSize bytes');
            try {
              await recordedFile.delete();
            } catch (e) {
              print('⚠️ Failed to delete small file: $e');
            }
            return null;
          }
        } else {
          print('❌ Recorded file does not exist');
          return null;
        }
      } else {
        print('❌ Recording returned null path');
        return null;
      }
    } catch (e) {
      print('❌ Error stopping recording: $e');
      _isRecording = false;
      _currentRecordingPath = null;
      _recordingStartTime = null;
      return null;
    }
  }

  // Validate M4A file
  static bool _isValidM4aFile(Uint8List bytes) {
    if (bytes.length < 8) return false;

    // Check for M4A/MP4 container signatures
    // Look for "ftyp" at offset 4
    if (bytes.length >= 8) {
      final ftypCheck =
          bytes[4] == 0x66 &&
          bytes[5] == 0x74 &&
          bytes[6] == 0x79 &&
          bytes[7] == 0x70;
      if (ftypCheck) return true;
    }

    // Alternative: Check for AAC ADTS frame header
    if (bytes[0] == 0xFF && (bytes[1] & 0xF0) == 0xF0) {
      return true;
    }

    return false;
  }

  // Keep MP3 validation for base64 responses
  static bool _isValidMp3File(Uint8List bytes) {
    if (bytes.length < 4) return false;

    // Check for MP3 signatures
    // ID3v2 tag (starts with "ID3")
    if (bytes.length >= 3 &&
        bytes[0] == 0x49 &&
        bytes[1] == 0x44 &&
        bytes[2] == 0x33) {
      return true;
    }

    // MP3 frame header (first 11 bits should be 1)
    if (bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0) {
      return true;
    }

    return false;
  }

  // Pause recording
  static Future<bool> pauseRecording() async {
    try {
      if (_isRecording) {
        await _recorder.pause();
        print('⏸️ Recording paused');
        return true;
      }
      return false;
    } catch (e) {
      print('❌ Error pausing recording: $e');
      return false;
    }
  }

  // Resume recording
  static Future<bool> resumeRecording() async {
    try {
      if (!_isRecording) {
        await _recorder.resume();
        print('▶️ Recording resumed');
        return true;
      }
      return false;
    } catch (e) {
      print('❌ Error resuming recording: $e');
      return false;
    }
  }

  // Play audio from file
  static Future<bool> playAudioFromFile(File audioFile) async {
    try {
      print('🔊 Playing audio from file: ${audioFile.path}');

      if (_isPlaying) {
        await stopPlaying();
      }

      if (!await audioFile.exists()) {
        print('❌ Audio file does not exist');
        return false;
      }

      final fileSize = await audioFile.length();
      if (fileSize == 0) {
        print('❌ Audio file is empty');
        return false;
      }

      if (!_isPlayerInitialized || _audioPlayer == null) {
        await _initializePlayer();
      }

      if (!_isPlayerInitialized || _audioPlayer == null) {
        print('❌ Audio player not initialized');
        return false;
      }

      _currentPlayingPath = audioFile.path;
      await _audioPlayer!.play(audioplayers.DeviceFileSource(audioFile.path));
      _isPlaying = true;

      // Listen for completion
      _audioPlayer!.onPlayerComplete.listen((_) {
        _isPlaying = false;
        _currentPlayingPath = null;
        print('✅ Audio playback completed');
      });

      // Listen for state changes
      _audioPlayer!.onPlayerStateChanged.listen((state) {
        if (state == audioplayers.PlayerState.stopped ||
            state == audioplayers.PlayerState.completed) {
          _isPlaying = false;
          _currentPlayingPath = null;
        }
      });

      return true;
    } catch (e) {
      print('❌ Error playing audio: $e');
      _isPlaying = false;
      _currentPlayingPath = null;
      return false;
    }
  }

  // Play audio from base64 data
  static Future<bool> playAudioFromBase64(String base64Data) async {
    try {
      print('🔊 Playing audio from base64 data...');

      if (base64Data.isEmpty || !_isValidBase64(base64Data)) {
        print('❌ Invalid base64 data');
        return false;
      }

      final bytes = base64Decode(base64Data);
      if (bytes.isEmpty) {
        print('❌ No data decoded from base64');
        return false;
      }

      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileExtension = _detectAudioFormatFromBytes(bytes);
      final tempFile = File(
        '${directory.path}/temp_response_$timestamp.$fileExtension',
      );

      await tempFile.writeAsBytes(bytes);
      return await playAudioFromFile(tempFile);
    } catch (e) {
      print('❌ Error playing audio from base64: $e');
      return false;
    }
  }

  // Detect audio format from bytes
  static String _detectAudioFormatFromBytes(Uint8List bytes) {
    if (bytes.length < 4) return 'm4a';

    final header = bytes.take(12).toList();

    // MP3 signatures
    if (header[0] == 0xFF && (header[1] & 0xE0) == 0xE0) {
      return 'mp3';
    }

    // ID3 tag (MP3 with metadata)
    if (header.length >= 3 &&
        header[0] == 0x49 &&
        header[1] == 0x44 &&
        header[2] == 0x33) {
      return 'mp3';
    }

    // WAV signature
    if (header.length >= 4 &&
        header[0] == 0x52 &&
        header[1] == 0x49 &&
        header[2] == 0x46 &&
        header[3] == 0x46) {
      return 'wav';
    }

    // M4A/AAC signatures
    if (bytes.length >= 8) {
      final extendedHeader = bytes.take(8).toList();
      if (extendedHeader[4] == 0x66 &&
          extendedHeader[5] == 0x74 &&
          extendedHeader[6] == 0x79 &&
          extendedHeader[7] == 0x70) {
        return 'm4a';
      }
    }

    return 'm4a'; // Default to M4A
  }

  static bool _isValidBase64(String str) {
    try {
      base64Decode(str);
      return true;
    } catch (e) {
      return false;
    }
  }

  // Control methods
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

  static Future<void> stopPlaying() async {
    try {
      if (_audioPlayer != null) {
        await _audioPlayer!.stop();
        _isPlaying = false;
        _currentPlayingPath = null;
        print('🛑 Audio stopped');
      }
    } catch (e) {
      print('❌ Error stopping audio: $e');
    }
  }

  // Getters
  static bool get isRecording => _isRecording;
  static bool get isPlaying => _isPlaying;
  static bool get isRecorderInitialized => _isRecorderInitialized;
  static bool get isPlayerInitialized => _isPlayerInitialized;
  static String? get currentRecordingPath => _currentRecordingPath;
  static String? get currentPlayingPath => _currentPlayingPath;
  static Stream<Duration>? get recordingDurationStream =>
      _durationController?.stream;

  static Duration? get recordingDuration {
    if (_isRecording && _recordingStartTime != null) {
      return DateTime.now().difference(_recordingStartTime!);
    }
    return null;
  }

  static String get recordingFormat => _recordingFormat;
  static String get outputFormat => _outputFormat;

  // Get amplitude stream for visual feedback (fixed API)
  static Stream<Amplitude>? get amplitudeStream {
    try {
      return _recorder.onAmplitudeChanged(const Duration(milliseconds: 200));
    } catch (e) {
      print('⚠️ Amplitude stream not supported: $e');
      return null;
    }
  }

  // Check if recording is supported on this device
  static Future<bool> isRecordingSupported() async {
    try {
      return await _recorder.hasPermission();
    } catch (e) {
      print('❌ Error checking recording support: $e');
      return false;
    }
  }

  // Get list of available input devices
  static Future<List<InputDevice>> getInputDevices() async {
    try {
      return await _recorder.listInputDevices();
    } catch (e) {
      print('❌ Error getting input devices: $e');
      return [];
    }
  }

  // Create multipart data for API upload
  static Future<Map<String, dynamic>> createMultipartData(
    File audioFile,
  ) async {
    try {
      print('📤 Creating multipart data for M4A API...');

      final bytes = await audioFile.readAsBytes();
      final isValidM4a = _isValidM4aFile(bytes);

      print('🔍 M4A file analysis:');
      print('   File size: ${bytes.length} bytes');
      print('   Is valid M4A: $isValidM4a');
      print('   Recording engine: record library');

      return {
        'file_bytes': bytes,
        'filename': 'audio_recording.m4a',
        'content_type': 'audio/mp4', // M4A uses audio/mp4 MIME type
        'field_name': 'audio_file',
        'file_size': bytes.length,
        'duration_ms': recordingDuration?.inMilliseconds ?? 0,
        'format': 'm4a',
        'sample_rate': 44100,
        'bit_rate': 128000,
        'is_valid_m4a': isValidM4a,
        'codec': 'aac_lc',
        'engine': 'record_library',
      };
    } catch (e) {
      print('❌ Error creating multipart data: $e');
      return {};
    }
  }

  // Test recording functionality
  static Future<bool> testRecording({int durationSeconds = 3}) async {
    try {
      print('\n🧪 === TESTING M4A RECORDING ===');

      await initialize();

      // Check device support
      final isSupported = await isRecordingSupported();
      if (!isSupported) {
        print('❌ Recording not supported on this device');
        return false;
      }

      print('▶️ Starting test recording...');
      final started = await startRecording();

      if (!started) {
        print('❌ Failed to start recording');
        return false;
      }

      print('⏱️ Recording for $durationSeconds seconds...');
      await Future.delayed(Duration(seconds: durationSeconds));

      print('⏹️ Stopping recording...');
      final audioFile = await stopRecording();

      if (audioFile != null) {
        final fileSize = await audioFile.length();
        final fileName = audioFile.path.split('/').last;
        final bytes = await audioFile.readAsBytes();
        final isValidM4a = _isValidM4aFile(bytes);

        print('✅ M4A Recording successful!');
        print('📁 File: $fileName');
        print('📏 Size: $fileSize bytes');
        print('🔍 Valid M4A: $isValidM4a');

        // Test playback
        print('🔊 Testing playback...');
        final played = await playAudioFromFile(audioFile);
        print('🔊 Playback result: $played');

        // Test multipart creation
        final multipartData = await createMultipartData(audioFile);
        print(
          '📤 Multipart data: ${multipartData['content_type']} (${multipartData['file_size']} bytes)',
        );
        print('📤 Filename: ${multipartData['filename']}');
        print('📤 Engine: ${multipartData['engine']}');

        return true;
      } else {
        print('❌ No audio file produced');
        return false;
      }
    } catch (e) {
      print('❌ Test recording error: $e');
      return false;
    }
  }

  // Utility methods
  static Future<void> cleanupTempFiles() async {
    try {
      print('🧹 Cleaning up temporary audio files...');

      final directory = await getTemporaryDirectory();
      final files = directory.listSync();
      int deletedCount = 0;

      for (final file in files) {
        if (file is File) {
          final filename = file.path.split('/').last;
          if (filename.contains('urna_recording_') ||
              filename.contains('urna_final_') ||
              filename.contains('temp_response_')) {
            try {
              await file.delete();
              deletedCount++;
            } catch (e) {
              print('⚠️ Failed to delete $filename: $e');
            }
          }
        }
      }

      print('✅ Cleaned up $deletedCount temporary files');
    } catch (e) {
      print('❌ Error cleaning temp files: $e');
    }
  }

  static Future<bool> isMicrophoneAvailable() async {
    try {
      final status = await Permission.microphone.status;
      return !status.isPermanentlyDenied;
    } catch (e) {
      print('❌ Error checking microphone availability: $e');
      return false;
    }
  }

  static Future<void> reset() async {
    try {
      print('🔄 Resetting audio service...');

      if (_isRecording) {
        await stopRecording();
      }
      if (_isPlaying) {
        await stopPlaying();
      }

      _recordingTimer?.cancel();
      _recordingTimer = null;
      await _durationController?.close();
      _durationController = null;
      await _amplitudeSubscription?.cancel();
      _amplitudeSubscription = null;
      _currentRecordingPath = null;
      _currentPlayingPath = null;
      _recordingStartTime = null;

      print('✅ Audio service reset complete');
    } catch (e) {
      print('❌ Error resetting audio service: $e');
    }
  }

  static Future<void> dispose() async {
    try {
      print('🧹 Disposing audio service...');

      await reset();

      try {
        await _recorder.dispose();
      } catch (e) {
        print('⚠️ Error disposing recorder: $e');
      }

      if (_audioPlayer != null) {
        try {
          await _audioPlayer!.dispose();
        } catch (e) {
          print('⚠️ Error disposing audio player: $e');
        }
        _audioPlayer = null;
      }

      _isRecorderInitialized = false;
      _isPlayerInitialized = false;

      await cleanupTempFiles();
      print('✅ Audio service disposed successfully');
    } catch (e) {
      print('❌ Error disposing audio service: $e');
    }
  }
}
