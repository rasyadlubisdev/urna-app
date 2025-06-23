// models/auth_models.dart
import 'dart:convert';

class UserCredential {
  final String passphrase;
  final String turnstileToken;
  final String deviceId;
  final DateTime createdAt;
  final DateTime lastUsed;

  UserCredential({
    required this.passphrase,
    required this.turnstileToken,
    required this.deviceId,
    required this.createdAt,
    required this.lastUsed,
  });

  Map<String, dynamic> toJson() {
    return {
      'passphrase': passphrase,
      'turnstileToken': turnstileToken,
      'deviceId': deviceId,
      'createdAt': createdAt.toIso8601String(),
      'lastUsed': lastUsed.toIso8601String(),
    };
  }

  factory UserCredential.fromJson(Map<String, dynamic> json) {
    return UserCredential(
      passphrase: json['passphrase'],
      turnstileToken: json['turnstileToken'],
      deviceId: json['deviceId'],
      createdAt: DateTime.parse(json['createdAt']),
      lastUsed: DateTime.parse(json['lastUsed']),
    );
  }

  UserCredential copyWith({
    String? passphrase,
    String? turnstileToken,
    String? deviceId,
    DateTime? createdAt,
    DateTime? lastUsed,
  }) {
    return UserCredential(
      passphrase: passphrase ?? this.passphrase,
      turnstileToken: turnstileToken ?? this.turnstileToken,
      deviceId: deviceId ?? this.deviceId,
      createdAt: createdAt ?? this.createdAt,
      lastUsed: lastUsed ?? this.lastUsed,
    );
  }

  void printCredentialInfo() {
    print('\n' + '=' * 50);
    print('🔐 URNA USER CREDENTIAL');
    print('=' * 50);
    print('Passphrase: ${passphrase.substring(0, 20)}...');
    print('Device ID: $deviceId');
    print('Created: ${createdAt.toLocal()}');
    print('Last Used: ${lastUsed.toLocal()}');
    print('=' * 50 + '\n');
  }
}

class AuthResponse {
  final bool success;
  final String message;
  final String? sessionToken;
  final Map<String, dynamic>? metadata;

  AuthResponse({
    required this.success,
    required this.message,
    this.sessionToken,
    this.metadata,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      success: json['success'] ?? false,
      message: json['message'] ?? '',
      sessionToken: json['sessionToken'],
      metadata: json['metadata'],
    );
  }
}

class PredictionRequest {
  final String imageBase64;
  final String? audioBase64;
  final String userPassphrase;
  final String sessionToken;

  PredictionRequest({
    required this.imageBase64,
    this.audioBase64,
    required this.userPassphrase,
    required this.sessionToken,
  });

  Map<String, dynamic> toJson() {
    return {
      'image_file': imageBase64,
      'audio_file': audioBase64,
      'user_passphrase': userPassphrase,
      'session_token': sessionToken,
    };
  }
}

class PredictionResponse {
  final bool success;
  final String audioBase64;
  final String? errorMessage;
  final Map<String, dynamic>? metadata;

  PredictionResponse({
    required this.success,
    required this.audioBase64,
    this.errorMessage,
    this.metadata,
  });

  factory PredictionResponse.fromJson(Map<String, dynamic> json) {
    return PredictionResponse(
      success: json['success'] ?? false,
      audioBase64: json['audio_base64'] ?? '',
      errorMessage: json['error'],
      metadata: json['metadata'],
    );
  }
}
