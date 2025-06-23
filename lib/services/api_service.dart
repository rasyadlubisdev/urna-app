// services/api_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/auth_models.dart';
import '../utils/app_config.dart';

class ApiService {
  static const Duration _timeoutDuration = Duration(seconds: 1000);

  // Authentication endpoints (for future use)
  static Future<AuthResponse> registerUser({
    required String passphrase,
    required String turnstileToken,
    required String deviceId,
  }) async {
    if (!AppConfig.isBackendAuthReady) {
      // Simulate successful registration for development
      await Future.delayed(const Duration(seconds: 2));
      return AuthResponse(
        success: true,
        message: 'Registration simulated successfully',
        sessionToken: 'dev_session_${DateTime.now().millisecondsSinceEpoch}',
      );
    }

    try {
      final url = Uri.parse(
        '${AppConfig.baseUrl}${AppConfig.authEndpoint}/register',
      );

      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'User-Agent': 'URNA-Mobile/1.0',
            },
            body: json.encode({
              'passphrase': passphrase,
              'turnstile_token': turnstileToken,
              'device_id': deviceId,
              'timestamp': DateTime.now().toIso8601String(),
            }),
          )
          .timeout(_timeoutDuration);

      print('📤 Register request sent to: $url');
      print('📦 Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        return AuthResponse.fromJson(responseData);
      } else if (response.statusCode == 409) {
        // Passphrase already exists
        return AuthResponse(
          success: false,
          message: 'Passphrase already exists. Please generate a new one.',
        );
      } else {
        return AuthResponse(
          success: false,
          message: 'Registration failed: HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      print('❌ Registration error: $e');
      return AuthResponse(
        success: false,
        message: 'Network error during registration: $e',
      );
    }
  }

  static Future<AuthResponse> loginUser({
    required String passphrase,
    required String turnstileToken,
  }) async {
    if (!AppConfig.isBackendAuthReady) {
      // Simulate successful login for development
      await Future.delayed(const Duration(seconds: 1));
      return AuthResponse(
        success: true,
        message: 'Login simulated successfully',
        sessionToken: 'dev_session_${DateTime.now().millisecondsSinceEpoch}',
      );
    }

    try {
      final url = Uri.parse(
        '${AppConfig.baseUrl}${AppConfig.authEndpoint}/login',
      );

      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'User-Agent': 'URNA-Mobile/1.0',
            },
            body: json.encode({
              'passphrase': passphrase,
              'turnstile_token': turnstileToken,
              'timestamp': DateTime.now().toIso8601String(),
            }),
          )
          .timeout(_timeoutDuration);

      print('📤 Login request sent to: $url');
      print('📦 Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        return AuthResponse.fromJson(responseData);
      } else {
        return AuthResponse(
          success: false,
          message: 'Login failed: HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      print('❌ Login error: $e');
      return AuthResponse(
        success: false,
        message: 'Network error during login: $e',
      );
    }
  }

  // Main prediction endpoint
  static Future<PredictionResponse> sendPredictionRequest({
    required File imageFile,
    File? audioFile,
    required String userPassphrase,
    String? sessionToken,
  }) async {
    try {
      final url = Uri.parse('${AppConfig.baseUrl}${AppConfig.predictEndpoint}');

      print('📤 Sending prediction request to: $url');
      print('📸 Image file: ${imageFile.path}');
      print('🎤 Audio file: ${audioFile?.path ?? 'None'}');

      // Create multipart request
      final request = http.MultipartRequest('POST', url);

      // Add headers
      request.headers.addAll({
        'User-Agent': 'URNA-Mobile/1.0',
        'X-User-Passphrase': userPassphrase,
        if (sessionToken != null) 'Authorization': 'Bearer $sessionToken',
      });

      // Add image file
      final imageBytes = await imageFile.readAsBytes();
      request.files.add(
        http.MultipartFile.fromBytes(
          'image_file',
          imageBytes,
          filename: 'image.${AppConfig.captureImageFormat}',
        ),
      );

      // Add audio file if provided
      if (audioFile != null) {
        final audioBytes = await audioFile.readAsBytes();
        request.files.add(
          http.MultipartFile.fromBytes(
            'audio_file',
            audioBytes,
            filename: 'audio.${AppConfig.audioRecordingFormat}',
          ),
        );
      }

      print('📦 Image size: ${imageBytes.length} bytes');
      if (audioFile != null) {
        final audioBytes = await audioFile!.readAsBytes();
        print('📦 Audio size: ${audioBytes.length} bytes');
      }

      // Send request
      final streamedResponse = await request.send().timeout(_timeoutDuration);
      final response = await http.Response.fromStream(streamedResponse);

      print('📦 Response status: ${response.statusCode}');
      print('📦 Response headers: ${response.headers}');

      if (response.statusCode == 200) {
        // Check if response is JSON or binary
        final contentType = response.headers['content-type'] ?? '';

        if (contentType.contains('application/json')) {
          // JSON response with base64 audio
          final responseData = json.decode(response.body);
          return PredictionResponse.fromJson(responseData);
        } else if (contentType.contains('audio/')) {
          // Direct audio response
          final audioBase64 = base64.encode(response.bodyBytes);
          return PredictionResponse(success: true, audioBase64: audioBase64);
        } else {
          return PredictionResponse(
            success: false,
            audioBase64: '',
            errorMessage: 'Unexpected response format: $contentType',
          );
        }
      } else {
        String errorMessage = 'HTTP ${response.statusCode}';
        try {
          final errorData = json.decode(response.body);
          errorMessage = errorData['error'] ?? errorMessage;
        } catch (e) {
          // Response body is not JSON
          errorMessage = response.body.isNotEmpty
              ? response.body
              : errorMessage;
        }

        return PredictionResponse(
          success: false,
          audioBase64: '',
          errorMessage: errorMessage,
        );
      }
    } catch (e) {
      print('❌ Prediction request error: $e');
      return PredictionResponse(
        success: false,
        audioBase64: '',
        errorMessage: 'Network error: $e',
      );
    }
  }

  // Simple API call without authentication - hanya fokus pada body request
  static Future<PredictionResponse> sendSimpleApiRequest({
    required File imageFile,
    File? audioFile,
  }) async {
    try {
      final url = Uri.parse('${AppConfig.baseUrl}${AppConfig.predictEndpoint}');

      print('📤 Simple API request to: $url');
      print('📸 Image: ${imageFile.path}');
      print('🎤 Audio: ${audioFile?.path ?? 'None'}');

      // Create multipart request dengan headers minimal
      final request = http.MultipartRequest('POST', url);

      // Headers paling basic
      request.headers.addAll({'User-Agent': 'URNA-Mobile/1.0'});

      // Add image file
      final imageBytes = await imageFile.readAsBytes();
      request.files.add(
        http.MultipartFile.fromBytes(
          'image_file',
          imageBytes,
          filename: 'image.jpg',
        ),
      );

      // Add audio file if provided
      if (audioFile != null && await audioFile.exists()) {
        final audioBytes = await audioFile.readAsBytes();
        request.files.add(
          http.MultipartFile.fromBytes(
            'audio_file',
            audioBytes,
            filename: 'audio.m4a',
          ),
        );
      }

      print(
        '📦 Sending: Image ${imageBytes.length} bytes, Audio ${audioFile != null ? "included" : "none"}',
      );

      // Send request
      final streamedResponse = await request.send().timeout(
        Duration(seconds: 600),
      );
      final response = await http.Response.fromStream(streamedResponse);

      print('📦 Response: ${response.statusCode}');
      print(
        '📦 Body preview: ${response.body.length > 100 ? response.body.substring(0, 100) + "..." : response.body}',
      );

      if (response.statusCode == 200) {
        final contentType = response.headers['content-type'] ?? '';

        if (contentType.contains('application/json')) {
          final responseData = json.decode(response.body);
          return PredictionResponse.fromJson(responseData);
        } else if (contentType.contains('audio/')) {
          final audioBase64 = base64.encode(response.bodyBytes);
          return PredictionResponse(success: true, audioBase64: audioBase64);
        } else {
          // Handle text response
          final textResponse = response.body;
          final audioBase64 = base64.encode(utf8.encode(textResponse));
          return PredictionResponse(
            success: true,
            audioBase64: audioBase64,
            metadata: {'response_text': textResponse},
          );
        }
      } else {
        return PredictionResponse(
          success: false,
          audioBase64: '',
          errorMessage: 'HTTP ${response.statusCode}: ${response.body}',
        );
      }
    } catch (e) {
      print('❌ Simple API error: $e');
      return PredictionResponse(
        success: false,
        audioBase64: '',
        errorMessage: 'Network error: $e',
      );
    }
  }

  // Development mode simulation
  static Future<PredictionResponse> simulatePredictionRequest({
    required File imageFile,
    File? audioFile,
    required String userPassphrase,
  }) async {
    print('🔧 DEVELOPMENT MODE - Simulating API call');
    print('📸 Image: ${imageFile.path}');
    print('🎤 Audio: ${audioFile?.path ?? 'None'}');
    print('🔐 Passphrase: ${userPassphrase.substring(0, 10)}...');

    // Simulate processing delay
    await Future.delayed(const Duration(seconds: 3));

    // Simulate response based on whether audio is provided
    final responseTexts = audioFile != null
        ? [
            'Berdasarkan gambar yang Anda kirim dan pertanyaan Anda, saya dapat melihat ini adalah pemandangan yang menarik. Cuaca terlihat cerah dengan langit biru yang jernih.',
            'Dari analisis visual dan audio yang Anda berikan, kondisi di gambar menunjukkan lingkungan yang aman dan nyaman untuk aktivitas outdoor.',
            'Sesuai dengan pertanyaan Anda tentang gambar ini, saya dapat menjelaskan bahwa objek-objek yang terlihat dalam kondisi baik dan tertata rapi.',
          ]
        : [
            'Di depan Anda terdapat pemandangan dengan berbagai objek menarik. Cuaca tampak cerah dan kondisi lingkungan terlihat aman.',
            'Terlihat area yang cukup luas dengan pencahayaan yang baik. Tidak ada halangan atau bahaya yang terdeteksi di sekitar area ini.',
            'Lingkungan sekitar menunjukkan aktivitas normal dengan beberapa objek yang dapat diidentifikasi dengan jelas.',
          ];

    final selectedText =
        responseTexts[DateTime.now().second % responseTexts.length];

    // Convert text to simulated audio (base64)
    // In real implementation, this would be actual audio data
    final simulatedAudioData = base64.encode(utf8.encode(selectedText));

    return PredictionResponse(
      success: true,
      audioBase64: simulatedAudioData,
      metadata: {
        'mode': 'simulation',
        'timestamp': DateTime.now().toIso8601String(),
        'has_audio_input': audioFile != null,
        'response_text': selectedText,
      },
    );
  }

  // Health check
  static Future<bool> checkBackendHealth() async {
    try {
      final url = Uri.parse('${AppConfig.baseUrl}/health');
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (e) {
      print('❌ Backend health check failed: $e');
      return false;
    }
  }
}
