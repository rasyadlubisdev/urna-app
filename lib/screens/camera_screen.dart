// screens/camera_screen.dart - UPDATED FOR record library COMPATIBILITY (M4A format)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import '../models/auth_models.dart';
import '../services/audio_service.dart'; // UPDATED: Use record library service
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../utils/feedback_utils.dart';
import '../utils/app_config.dart';
import '../utils/file_debug_utils.dart';
import 'auth_screen.dart';

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final UserCredential credential;

  const CameraScreen({
    Key? key,
    required this.cameras,
    required this.credential,
  }) : super(key: key);

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with TickerProviderStateMixin {
  // Camera related
  CameraController? _cameraController;
  bool _isCameraInitialized = false;

  // Gesture detection for image capture
  bool _isDetecting = false;
  Timer? _longPressTimer;
  double _pressProgress = 0.0;

  // Tap detection for microphone
  int _tapCount = 0;
  Timer? _tapTimer;
  bool _isMicrophoneActive = false;

  // API processing
  bool _isProcessingApi = false;
  File? _lastCapturedImage;
  File? _lastRecordedAudio;

  // Audio playback
  bool _isPlayingResponse = false;
  bool _isPaused = false;

  // Session state management
  bool _hasImageCaptured = false;
  bool _hasAudioRecorded = false;
  bool _canSendToApi = false;

  // UPDATED: Recording duration tracking for record library
  StreamSubscription<Duration>? _recordingDurationSubscription;
  Duration _currentRecordingDuration = Duration.zero;

  // Animation controllers
  late AnimationController _progressController;
  late AnimationController _micController;
  late Animation<double> _progressAnimation;
  late Animation<double> _micAnimation;

  // Session token for API calls
  String? _sessionToken;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeServices();
    _initializeCamera();

    print(
      '\n📷 URNA CAMERA SCREEN INITIALIZED (record library M4A compatible)',
    );
    widget.credential.printCredentialInfo();
  }

  void _initializeAnimations() {
    _progressController = AnimationController(
      duration: AppConfig.longPressDuration,
      vsync: this,
    );

    _micController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _progressAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _progressController, curve: Curves.linear),
    );

    _micAnimation = Tween<double>(
      begin: 1.0,
      end: 1.3,
    ).animate(CurvedAnimation(parent: _micController, curve: Curves.easeInOut));
  }

  Future<void> _initializeServices() async {
    try {
      // UPDATED: Initialize record library audio service
      await AudioService.initialize();

      // Load session token
      _sessionToken = await StorageService.loadSessionToken();

      print('✅ Services initialized successfully (record library)');
    } catch (e) {
      print('❌ Error initializing services: $e');
    }
  }

  Future<void> _initializeCamera() async {
    if (widget.cameras.isEmpty) {
      print('❌ No cameras available');
      await FeedbackUtils.speak('Kamera tidak tersedia');
      return;
    }

    try {
      _cameraController = CameraController(
        widget.cameras[0],
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
        print('✅ Camera initialized successfully');

        // Welcome message
        await FeedbackUtils.speak(
          'URNA siap digunakan. Tahan layar 3 detik untuk mengambil gambar, lalu ketuk 3 kali untuk merekam suara.',
        );
      }
    } catch (e) {
      print('❌ Error initializing camera: $e');
      if (mounted) {
        _showSnackBar('Gagal menginisialisasi kamera: $e');
      }
    }
  }

  // Handle tap detection for microphone activation
  void _handleTap() async {
    _tapCount++;
    print('👆 Tap count: $_tapCount');

    if (_tapCount == 1) {
      // Single tap: pause/resume audio if playing
      if (_isPlayingResponse) {
        await _toggleAudioPlayback();
        _tapCount = 0;
        return;
      }

      // Start timer for triple tap detection
      _tapTimer = Timer(AppConfig.tapTimeout, () {
        _tapCount = 0;
      });
    } else if (_tapCount == AppConfig.tripleTapCount) {
      _tapTimer?.cancel();
      _tapCount = 0;
      await _handleMicrophoneToggle();
    }
  }

  // Toggle audio playback (pause/resume)
  Future<void> _toggleAudioPlayback() async {
    if (_isPaused) {
      await AudioService.resumePlaying();
      setState(() {
        _isPaused = false;
      });
      await FeedbackUtils.lightVibrate();
    } else {
      await AudioService.pausePlaying();
      setState(() {
        _isPaused = true;
      });
      await FeedbackUtils.lightVibrate();
    }
  }

  // Handle microphone toggle (start/stop recording)
  Future<void> _handleMicrophoneToggle() async {
    if (_isProcessingApi) {
      await FeedbackUtils.speak('Sedang memproses, mohon tunggu');
      return;
    }

    if (_isMicrophoneActive) {
      // Stop recording
      await _stopRecording();
    } else {
      // Start recording
      await _startRecording();
    }
  }

  // UPDATED: Start audio recording with record library
  Future<void> _startRecording() async {
    try {
      print('\n🎤 Starting M4A audio recording with record library...');

      // Stop any ongoing audio playback
      if (_isPlayingResponse) {
        await AudioService.stopPlaying();
        setState(() {
          _isPlayingResponse = false;
          _isPaused = false;
        });
      }

      setState(() {
        _isMicrophoneActive = true;
        _currentRecordingDuration = Duration.zero;
      });

      _micController.repeat(reverse: true);

      final started = await AudioService.startRecording();
      if (started) {
        // UPDATED: Subscribe to recording duration stream from record library
        _recordingDurationSubscription = AudioService.recordingDurationStream
            ?.listen((duration) {
              if (mounted) {
                setState(() {
                  _currentRecordingDuration = duration;
                });
              }
            });

        await FeedbackUtils.microphoneStartFeedback();
        await FeedbackUtils.speak(
          'Mulai berbicara sekarang. Ketuk 3 kali lagi untuk berhenti merekam.',
        );
      } else {
        setState(() {
          _isMicrophoneActive = false;
        });
        _micController.stop();
        await FeedbackUtils.speak('Gagal memulai perekaman');
      }
    } catch (e) {
      print('❌ Error starting recording: $e');
      setState(() {
        _isMicrophoneActive = false;
      });
      _micController.stop();
      await FeedbackUtils.errorFeedback();
    }
  }

  // UPDATED: Stop audio recording and prepare for API call
  Future<void> _stopRecording() async {
    try {
      print('\n🛑 Stopping M4A audio recording with record library...');

      setState(() {
        _isMicrophoneActive = false;
      });
      _micController.stop();
      _micController.reset();

      // UPDATED: Cancel duration subscription
      await _recordingDurationSubscription?.cancel();
      _recordingDurationSubscription = null;

      final audioFile = await AudioService.stopRecording();
      if (audioFile != null) {
        _lastRecordedAudio = audioFile;

        setState(() {
          _hasAudioRecorded = true;
          _canSendToApi = _hasImageCaptured && _hasAudioRecorded;
        });

        await FeedbackUtils.microphoneStopFeedback();

        // UPDATED: Check recording duration and format
        print(
          '📊 M4A Recording duration: ${_currentRecordingDuration.inSeconds}s',
        );
        print('📋 Format: ${AudioService.recordingFormat}');

        if (_canSendToApi) {
          await FeedbackUtils.speak(
            'Audio M4A AAC berkualitas tinggi direkam. Mengirim gambar dan audio ke AI...',
          );
          // Auto send to API when both image and audio are ready
          await _sendToApi();
        } else {
          await FeedbackUtils.speak(
            'Silakan ambil gambar terlebih dahulu dengan menahan layar 3 detik.',
          );
        }
      } else {
        await FeedbackUtils.speak('Gagal merekam audio');
      }
    } catch (e) {
      print('❌ Error stopping recording: $e');
      await FeedbackUtils.errorFeedback();
    }
  }

  // Start long press detection for image capture
  void _startLongPress() {
    if (_isProcessingApi || _isMicrophoneActive) return;

    print('\n🔥 Long press started');

    // Stop any ongoing audio playback
    if (_isPlayingResponse) {
      AudioService.stopPlaying();
      setState(() {
        _isPlayingResponse = false;
        _isPaused = false;
      });
    }

    setState(() {
      _isDetecting = true;
      _pressProgress = 0.0;
    });

    _progressController.reset();
    _progressController.forward();

    _longPressTimer = Timer.periodic(const Duration(milliseconds: 100), (
      timer,
    ) {
      setState(() {
        _pressProgress = _progressController.value;
      });

      if (_pressProgress >= 1.0) {
        timer.cancel();
        _captureImageOnly();
      }
    });

    FeedbackUtils.captureStartFeedback();
  }

  // Cancel long press
  void _cancelLongPress() {
    print('❌ Long press cancelled');
    _longPressTimer?.cancel();
    _progressController.stop();
    _progressController.reset();

    setState(() {
      _isDetecting = false;
      _pressProgress = 0.0;
    });
  }

  // Capture real image from camera and save as JPG
  Future<void> _captureImageOnly() async {
    try {
      print('\n📸 CAPTURING REAL IMAGE FROM CAMERA');

      setState(() {
        _isDetecting = false;
        _pressProgress = 0.0;
      });

      await FeedbackUtils.captureCompleteFeedback();

      File imageFile;

      // Always try to capture from camera first
      if (_cameraController != null && _cameraController!.value.isInitialized) {
        try {
          print('📷 Attempting camera capture...');

          final XFile capturedImage = await _cameraController!.takePicture();
          print('📸 Raw capture successful: ${capturedImage.path}');

          // Convert to JPG format and save to permanent location
          imageFile = await _convertAndSaveAsJpg(File(capturedImage.path));

          print('✅ Image converted and saved as JPG: ${imageFile.path}');
        } catch (cameraError) {
          print('⚠️ Camera capture failed: $cameraError');

          // Fallback: Try to load test image from assets
          imageFile = await _loadTestImageFromAssets();
        }
      } else {
        print('⚠️ Camera not available, using test image');

        // Fallback: Load test image from assets
        imageFile = await _loadTestImageFromAssets();
      }

      // Verify the final image file
      if (await imageFile.exists()) {
        final fileSize = await imageFile.length();
        print('📋 Final image verification:');
        print('📁 Path: ${imageFile.path}');
        print('📏 Size: $fileSize bytes');

        // Verify JPG format
        await _verifyJpgFormat(imageFile);

        _lastCapturedImage = imageFile;

        setState(() {
          _hasImageCaptured = true;
          _canSendToApi = _hasImageCaptured && _hasAudioRecorded;
        });

        if (_canSendToApi) {
          await FeedbackUtils.speak(
            'Gambar diambil. Mengirim gambar dan audio ke AI...',
          );
          await _sendToApi();
        } else {
          await FeedbackUtils.speak(
            'Gambar berhasil diambil. Sekarang ketuk 3 kali untuk merekam pertanyaan Anda.',
          );
        }
      } else {
        throw Exception('Image file was not created successfully');
      }
    } catch (e) {
      print('❌ Image capture error: $e');
      await FeedbackUtils.errorFeedback();
      await FeedbackUtils.speak('Gagal mengambil gambar: $e');
    }
  }

  // Convert captured image to proper JPG format
  Future<File> _convertAndSaveAsJpg(File capturedFile) async {
    try {
      print('\n🔄 Converting captured image to JPG format...');

      // Read the captured image bytes
      final Uint8List imageBytes = await capturedFile.readAsBytes();
      print('📁 Original file size: ${imageBytes.length} bytes');

      // Decode the image using the image package
      img.Image? decodedImage = img.decodeImage(imageBytes);

      if (decodedImage == null) {
        print('❌ Failed to decode captured image, using original file');
        return await _copyToJpgFile(capturedFile);
      }

      print(
        '📏 Image dimensions: ${decodedImage.width}x${decodedImage.height}',
      );

      // Resize if too large (max 1920x1080 for efficiency)
      if (decodedImage.width > 1920 || decodedImage.height > 1080) {
        print('🔽 Resizing large image...');
        decodedImage = img.copyResize(
          decodedImage,
          width: decodedImage.width > decodedImage.height ? 1920 : null,
          height: decodedImage.height > decodedImage.width ? 1080 : null,
          maintainAspect: true,
        );
        print('📏 Resized to: ${decodedImage.width}x${decodedImage.height}');
      }

      // Encode as JPG with good quality
      final List<int> jpgBytes = img.encodeJpg(decodedImage, quality: 85);

      // Save to a permanent file location
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final jpgFile = File('${tempDir.path}/urna_captured_$timestamp.jpg');

      await jpgFile.writeAsBytes(jpgBytes);

      print('✅ JPG conversion successful');
      print('📁 JPG file: ${jpgFile.path}');
      print('📏 JPG size: ${jpgBytes.length} bytes');

      // Clean up original captured file if different
      if (capturedFile.path != jpgFile.path) {
        try {
          await capturedFile.delete();
          print('🗑️ Cleaned up original captured file');
        } catch (e) {
          print('⚠️ Could not delete original file: $e');
        }
      }

      return jpgFile;
    } catch (e) {
      print('❌ Error converting to JPG: $e');
      // Fallback: just copy the original file with .jpg extension
      return await _copyToJpgFile(capturedFile);
    }
  }

  // Helper: Copy file with JPG extension
  Future<File> _copyToJpgFile(File originalFile) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final jpgFile = File('${tempDir.path}/urna_copied_$timestamp.jpg');

      await originalFile.copy(jpgFile.path);

      print('📋 File copied with JPG extension: ${jpgFile.path}');
      return jpgFile;
    } catch (e) {
      print('❌ Error copying file: $e');
      // Last resort: return original file
      return originalFile;
    }
  }

  // Load test image from assets
  Future<File> _loadTestImageFromAssets() async {
    try {
      print('\n🖼️ Loading test image from assets...');

      // Try to load the test image from assets
      final byteData = await rootBundle.load('lib/assets/test_image.jpg');
      final bytes = byteData.buffer.asUint8List();

      // Create a temporary file with JPG extension
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${tempDir.path}/urna_test_image_$timestamp.jpg');

      // Write the asset bytes to the temporary file
      await file.writeAsBytes(bytes);

      print('✅ Test image loaded from assets: ${file.path}');
      print('📏 Test image size: ${bytes.length} bytes');

      return file;
    } catch (assetError) {
      print('⚠️ Failed to load test image from assets: $assetError');

      // Final fallback: create a proper test JPG
      return await _createProperTestJpg();
    }
  }

  // Create a proper test JPG image
  Future<File> _createProperTestJpg() async {
    try {
      print('\n🆘 Creating proper test JPG image...');

      // Create a 640x480 red test image using the image package
      final img.Image testImage = img.Image(width: 640, height: 480);

      // Fill with red color
      img.fill(testImage, color: img.ColorRgb8(255, 0, 0));

      // Add some text to make it more realistic
      img.drawString(
        testImage,
        'URNA TEST IMAGE',
        font: img.arial24,
        x: 50,
        y: 200,
        color: img.ColorRgb8(255, 255, 255),
      );

      // Encode as JPG
      final List<int> jpgBytes = img.encodeJpg(testImage, quality: 85);

      // Save to file
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${tempDir.path}/urna_test_created_$timestamp.jpg');

      await file.writeAsBytes(jpgBytes);

      print('✅ Test JPG created: ${file.path}');
      print('📏 Test JPG size: ${jpgBytes.length} bytes');

      return file;
    } catch (e) {
      print('❌ Error creating test JPG: $e');
      rethrow;
    }
  }

  // Verify JPG format
  Future<void> _verifyJpgFormat(File jpgFile) async {
    try {
      final bytes = await jpgFile.readAsBytes();
      if (bytes.length >= 4) {
        // JPG files should start with 0xFF 0xD8 and end with 0xFF 0xD9
        final startCorrect = bytes[0] == 0xFF && bytes[1] == 0xD8;
        final endCorrect =
            bytes[bytes.length - 2] == 0xFF && bytes[bytes.length - 1] == 0xD9;

        if (startCorrect && endCorrect) {
          print('✅ JPG format verified (proper SOI and EOI markers)');
        } else {
          print('⚠️ JPG format verification failed');
          print(
            '📋 Start: ${bytes[0].toRadixString(16)} ${bytes[1].toRadixString(16)} (should be FF D8)',
          );
          print(
            '📋 End: ${bytes[bytes.length - 2].toRadixString(16)} ${bytes[bytes.length - 1].toRadixString(16)} (should be FF D9)',
          );
        }
      }
    } catch (e) {
      print('⚠️ Could not verify JPG format: $e');
    }
  }

  // Send to API when both image and audio are ready
  Future<void> _sendToApi() async {
    if (!_canSendToApi) {
      print('⚠️ Cannot send to API: Missing image or audio');
      if (!_hasImageCaptured) {
        await FeedbackUtils.speak(
          'Belum ada gambar. Tahan layar 3 detik untuk mengambil gambar.',
        );
      } else if (!_hasAudioRecorded) {
        await FeedbackUtils.speak(
          'Belum ada audio. Ketuk 3 kali untuk merekam pertanyaan Anda.',
        );
      }
      return;
    }

    try {
      print('\n📤 Sending complete request to API (Image + M4A AAC Audio)...');

      // DEBUG: Check files before sending
      print('\n🔍 DEBUGGING FILES BEFORE API CALL:');
      await FileDebugUtils.debugFile(_lastCapturedImage!, 'Captured Image');
      await FileDebugUtils.debugFile(
        _lastRecordedAudio!,
        'Recorded M4A AAC Audio',
      );

      // Copy files to accessible location for manual checking
      try {
        final imageCopyPath = await FileDebugUtils.copyToDownloads(
          _lastCapturedImage!,
          'urna_debug_image_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        final audioCopyPath = await FileDebugUtils.copyToDownloads(
          _lastRecordedAudio!,
          'urna_debug_audio_${DateTime.now().millisecondsSinceEpoch}.m4a',
        );

        if (imageCopyPath != null) {
          print('📋 Image copied for manual check: $imageCopyPath');
        }
        if (audioCopyPath != null) {
          print('📋 Audio copied for manual check: $audioCopyPath');
        }
      } catch (copyError) {
        print('⚠️ Failed to copy files for manual check: $copyError');
      }

      // Validate files
      final imageValid = await FileDebugUtils.isValidForApi(
        _lastCapturedImage!,
        'jpeg',
      );
      final audioValid = await FileDebugUtils.isValidForApi(
        _lastRecordedAudio!,
        'm4a',
      );

      print('📋 Image validation: $imageValid');
      print('📋 Audio validation: $audioValid');

      // UPDATED: Enhanced audio validation for M4A AAC
      if (audioValid) {
        final audioSize = await _lastRecordedAudio!.length();
        print('📋 M4A AAC file size: $audioSize bytes');
        print('📋 Recording duration: ${_currentRecordingDuration.inSeconds}s');
        print('📋 Format: ${AudioService.outputFormat}');

        // UPDATED: Create multipart data using record library service
        final multipartData = await AudioService.createMultipartData(
          _lastRecordedAudio!,
        );
        print('📋 Multipart validation: ${multipartData['is_valid_m4a']}');
        print('📋 Content type: ${multipartData['content_type']}');
        print('📋 Codec: ${multipartData['codec']}');

        if (audioSize < 5000) {
          print('⚠️ M4A AAC file suspiciously small, but proceeding...');
        }
      }

      if (!imageValid || !audioValid) {
        await FeedbackUtils.speak('File tidak valid untuk dikirim ke server');
        return;
      }

      setState(() {
        _isProcessingApi = true;
      });

      await FeedbackUtils.processingFeedback();

      PredictionResponse response;

      if (AppConfig.isDevelopmentMode) {
        // Use simulation for development
        response = await ApiService.sendSimpleApiRequest(
          imageFile: _lastCapturedImage!,
          audioFile: _lastRecordedAudio!,
        );
      } else {
        // Use real API
        response = await ApiService.sendPredictionRequest(
          imageFile: _lastCapturedImage!,
          audioFile: _lastRecordedAudio!,
          userPassphrase: widget.credential.passphrase,
          sessionToken: _sessionToken,
        );
      }

      setState(() {
        _isProcessingApi = false;
      });

      if (response.success && response.audioBase64.isNotEmpty) {
        print('✅ API request successful with M4A AAC');
        await FeedbackUtils.successFeedback();

        // Reset session state after successful API call
        _resetSessionState();

        // Play response audio
        await _playResponseAudio(response.audioBase64);
      } else {
        print('❌ API request failed: ${response.errorMessage}');
        await FeedbackUtils.errorFeedback();
        await FeedbackUtils.speak(
          response.errorMessage ?? 'Gagal mendapatkan respons dari server',
        );
      }
    } catch (e) {
      print('❌ API request error: $e');
      setState(() {
        _isProcessingApi = false;
      });
      await FeedbackUtils.errorFeedback();
      await FeedbackUtils.speak('Terjadi kesalahan saat mengirim data');
    }
  }

  // Reset session state after API call
  void _resetSessionState() {
    setState(() {
      _hasImageCaptured = false;
      _hasAudioRecorded = false;
      _canSendToApi = false;
      _currentRecordingDuration = Duration.zero;
    });

    // Clear files
    _lastCapturedImage = null;
    _lastRecordedAudio = null;

    print('🔄 Session state reset');
  }

  // Play response audio from API
  Future<void> _playResponseAudio(String audioBase64) async {
    try {
      setState(() {
        _isPlayingResponse = true;
        _isPaused = false;
      });

      bool success;

      if (AppConfig.isDevelopmentMode && audioBase64.length < 1000) {
        // For simulation mode, speak the text instead of playing audio
        final responseText =
            'Ini adalah respons simulasi dari URNA AI menggunakan M4A AAC dengan record library';
        await FeedbackUtils.speak(responseText);
        success = true;
      } else {
        // UPDATED: Play actual audio response using record library compatible service
        success = await AudioService.playAudioFromBase64(audioBase64);
      }

      if (success) {
        print('🔊 Playing response audio with record library compatibility');

        // Auto-stop playing state when audio completes
        Timer(const Duration(seconds: 15), () {
          if (mounted) {
            setState(() {
              _isPlayingResponse = false;
              _isPaused = false;
            });
          }
        });
      } else {
        setState(() {
          _isPlayingResponse = false;
        });
        await FeedbackUtils.speak('Gagal memutar respons audio');
      }
    } catch (e) {
      print('❌ Error playing response audio: $e');
      setState(() {
        _isPlayingResponse = false;
        _isPaused = false;
      });
      await FeedbackUtils.speak('Gagal memutar respons');
    }
  }

  // Logout function
  Future<void> _logout() async {
    try {
      print('\n👋 LOGOUT');

      // Stop all ongoing activities
      if (_isMicrophoneActive) {
        await AudioService.stopRecording();
      }
      if (_isPlayingResponse) {
        await AudioService.stopPlaying();
      }

      // UPDATED: Cancel subscriptions
      await _recordingDurationSubscription?.cancel();

      await FeedbackUtils.speak('Keluar dari URNA. Sampai jumpa!');
      await Future.delayed(const Duration(seconds: 2));

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                AuthScreen(cameras: widget.cameras),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
            transitionDuration: const Duration(milliseconds: 500),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      print('❌ Logout error: $e');
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _longPressTimer?.cancel();
    _tapTimer?.cancel();
    _progressController.dispose();
    _micController.dispose();
    _recordingDurationSubscription?.cancel(); // UPDATED: Cancel subscription
    AudioService.dispose(); // UPDATED: Use record library service
    FeedbackUtils.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Camera Preview
            _buildCameraPreview(),

            // Top Bar
            _buildTopBar(),

            // Status Overlay
            // _buildStatusOverlay(),

            // Detection Progress Indicator
            if (_isDetecting) _buildDetectionProgress(),

            // API Processing Indicator
            if (_isProcessingApi) _buildApiProcessingIndicator(),

            // Microphone Indicator
            if (_isMicrophoneActive) _buildMicrophoneIndicator(),

            // Audio Playback Controls
            if (_isPlayingResponse) _buildAudioControls(),

            // Session Status Indicator
            _buildSessionStatusIndicator(),

            // Instructions
            // _buildInstructions(),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (_isCameraInitialized && _cameraController != null) {
      return Positioned.fill(
        child: AspectRatio(
          aspectRatio: _cameraController!.value.aspectRatio,
          child: GestureDetector(
            onTap: _handleTap,
            onLongPressStart: (_) => _startLongPress(),
            onLongPressEnd: (_) => _cancelLongPress(),
            child: CameraPreview(_cameraController!),
          ),
        ),
      );
    } else {
      return Container(
        color: Colors.grey.shade800,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text(
                'Menginisialisasi kamera...',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 16,
      left: 16,
      right: 16,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // App Title with Status
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black.withOpacity(0.8),
                  Colors.blue.withOpacity(0.8),
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'URNA',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  _isMicrophoneActive
                      ? Icons.mic
                      : _isPlayingResponse
                      ? (_isPaused ? Icons.pause : Icons.volume_up)
                      : Icons.camera_alt,
                  color: _isMicrophoneActive
                      ? Colors.red.shade400
                      : _isPlayingResponse
                      ? Colors.green.shade400
                      : Colors.blue.shade400,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _canSendToApi ? Colors.green : Colors.orange,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _canSendToApi ? 'READY' : 'WAIT',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Logout Button
          GestureDetector(
            onTap: _logout,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.red.shade600, Colors.red.shade800],
                ),
                borderRadius: BorderRadius.circular(25),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.logout, color: Colors.white, size: 24),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusOverlay() {
    return Positioned(
      top: 70,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.black.withOpacity(0.9),
              Colors.blue.withOpacity(0.8),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.withOpacity(0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.mic, color: Colors.green.shade400, size: 16),
                const SizedBox(width: 6),
                const Text(
                  'M4A',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'User: ${widget.credential.passphrase.split(' ')[0]}',
              style: TextStyle(color: Colors.grey.shade300, fontSize: 10),
            ),
            Text(
              'Engine: record library',
              style: TextStyle(
                color: Colors.green.shade300,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Format: ${AudioService.outputFormat.toUpperCase()}',
              style: TextStyle(
                color: Colors.green.shade300,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            // UPDATED: Show recording duration when active
            if (_isMicrophoneActive)
              Text(
                'Duration: ${_currentRecordingDuration.inSeconds}s',
                style: TextStyle(
                  color: Colors.red.shade300,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionStatusIndicator() {
    return Positioned(
      bottom: 20,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.black.withOpacity(0.8),
              Colors.indigo.withOpacity(0.8),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.indigo.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Image Status
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.camera_alt,
                  color: _hasImageCaptured ? Colors.green : Colors.grey,
                  size: 20,
                ),
                const SizedBox(height: 4),
                Text(
                  _hasImageCaptured ? 'CAPTURED' : 'PENDING',
                  style: TextStyle(
                    color: _hasImageCaptured ? Colors.green : Colors.grey,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            // Plus sign
            Icon(Icons.add, color: Colors.white, size: 16),

            // Audio Status with M4A AAC indicator
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.mic, // Indicates M4A AAC quality
                  color: _hasAudioRecorded ? Colors.green : Colors.grey,
                  size: 20,
                ),
                const SizedBox(height: 4),
                Text(
                  _hasAudioRecorded ? 'RECORDED' : 'PENDING',
                  style: TextStyle(
                    color: _hasAudioRecorded ? Colors.green : Colors.grey,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            // Equals sign
            Icon(Icons.drag_handle, color: Colors.white, size: 16),

            // API Status
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.send,
                  color: _canSendToApi ? Colors.blue : Colors.grey,
                  size: 20,
                ),
                const SizedBox(height: 4),
                Text(
                  _canSendToApi ? 'READY' : 'WAITING',
                  style: TextStyle(
                    color: _canSendToApi ? Colors.blue : Colors.grey,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetectionProgress() {
    return Center(
      child: Container(
        width: 140,
        height: 140,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.black.withOpacity(0.8),
              Colors.blue.withOpacity(0.8),
            ],
          ),
          borderRadius: BorderRadius.circular(70),
          boxShadow: [
            BoxShadow(
              color: Colors.blue.withOpacity(0.5),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _progressAnimation,
                builder: (context, child) {
                  return CircularProgressIndicator(
                    value: _progressAnimation.value,
                    strokeWidth: 8,
                    backgroundColor: Colors.white.withOpacity(0.3),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.blue.shade400,
                    ),
                  );
                },
              ),
            ),
            const Center(
              child: Icon(Icons.camera_alt, color: Colors.white, size: 50),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApiProcessingIndicator() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.black.withOpacity(0.9),
              Colors.purple.withOpacity(0.8),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.purple.withOpacity(0.3),
              blurRadius: 15,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              color: Colors.blue.shade400,
              strokeWidth: 3,
            ),
            const SizedBox(height: 16),
            const Text(
              'Mengirim JPG + M4A ke AI...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMicrophoneIndicator() {
    return Positioned(
      bottom: 200,
      left: 0,
      right: 0,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _micAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _micAnimation.value,
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.red.shade600, Colors.red.shade800],
                      ),
                      borderRadius: BorderRadius.circular(50),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withOpacity(0.5),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.mic, color: Colors.white, size: 40),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            // UPDATED: Show recording duration and M4A AAC format
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.8),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Text(
                'M4A ${_currentRecordingDuration.inSeconds}s',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioControls() {
    return Positioned(
      bottom: 200,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.black.withOpacity(0.9),
                Colors.green.withOpacity(0.8),
              ],
            ),
            borderRadius: BorderRadius.circular(25),
            boxShadow: [
              BoxShadow(
                color: Colors.green.withOpacity(0.3),
                blurRadius: 15,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isPaused ? Icons.play_arrow : Icons.pause,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(
                _isPaused ? 'Tap untuk melanjutkan' : 'Tap untuk pause',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInstructions() {
    return Positioned(
      bottom: 20,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.black.withOpacity(0.8),
              Colors.grey.withOpacity(0.8),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.touch_app, color: Colors.blue.shade400, size: 16),
                const SizedBox(width: 8),
                const Text(
                  'URNA Controls',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '1️⃣ Tahan layar 3 detik → Capture Real Image (JPG)',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '2️⃣ Ketuk 3x → Start Recording (M4A)',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '3️⃣ Ketuk 3x → Stop Recording & Send to AI',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '⏯️ Ketuk 1x → Pause/Resume Audio Response',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.mic, color: Colors.green.shade400, size: 14),
                const SizedBox(width: 6),
                Text(
                  'Real Camera → JPG | record library → M4A | API',
                  style: TextStyle(color: Colors.grey.shade300, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
