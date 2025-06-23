// services/storage_service.dart
import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/auth_models.dart';

class StorageService {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static const String _credentialKey = 'urna_user_credential';
  static const String _sessionTokenKey = 'urna_session_token';
  static const String _isRegisteredKey = 'urna_is_registered';

  // Credential Management
  static Future<void> saveCredential(UserCredential credential) async {
    try {
      final credentialJson = json.encode(credential.toJson());
      await _secureStorage.write(key: _credentialKey, value: credentialJson);
      await _secureStorage.write(key: _isRegisteredKey, value: 'true');
      print('✅ User credential saved to secure storage');
    } catch (e) {
      print('❌ Error saving credential: $e');
      throw Exception('Failed to save credential to secure storage');
    }
  }

  static Future<UserCredential?> loadCredential() async {
    try {
      final credentialJson = await _secureStorage.read(key: _credentialKey);

      if (credentialJson != null) {
        final Map<String, dynamic> data = json.decode(credentialJson);
        final credential = UserCredential.fromJson(data);
        print('✅ User credential loaded from secure storage');
        return credential;
      }

      print('ℹ️ No credential found in secure storage');
      return null;
    } catch (e) {
      print('❌ Error loading credential: $e');
      return null;
    }
  }

  static Future<void> updateLastUsed() async {
    try {
      final credential = await loadCredential();
      if (credential != null) {
        final updatedCredential = credential.copyWith(lastUsed: DateTime.now());
        await saveCredential(updatedCredential);
        print('✅ Last used timestamp updated');
      }
    } catch (e) {
      print('❌ Error updating last used: $e');
    }
  }

  // Session Token Management
  static Future<void> saveSessionToken(String token) async {
    try {
      await _secureStorage.write(key: _sessionTokenKey, value: token);
      print('✅ Session token saved');
    } catch (e) {
      print('❌ Error saving session token: $e');
    }
  }

  static Future<String?> loadSessionToken() async {
    try {
      final token = await _secureStorage.read(key: _sessionTokenKey);
      if (token != null) {
        print('✅ Session token loaded');
      }
      return token;
    } catch (e) {
      print('❌ Error loading session token: $e');
      return null;
    }
  }

  // Registration Status
  static Future<bool> isUserRegistered() async {
    try {
      final isRegistered = await _secureStorage.read(key: _isRegisteredKey);
      return isRegistered == 'true';
    } catch (e) {
      print('❌ Error checking registration status: $e');
      return false;
    }
  }

  // Clear All Data
  static Future<void> clearAllData() async {
    try {
      await _secureStorage.deleteAll();
      print('🗑️ All secure storage data cleared');
    } catch (e) {
      print('❌ Error clearing secure storage: $e');
    }
  }

  static Future<void> clearCredential() async {
    try {
      await _secureStorage.delete(key: _credentialKey);
      await _secureStorage.delete(key: _isRegisteredKey);
      print('🗑️ User credential cleared');
    } catch (e) {
      print('❌ Error clearing credential: $e');
    }
  }

  static Future<void> clearSessionToken() async {
    try {
      await _secureStorage.delete(key: _sessionTokenKey);
      print('🗑️ Session token cleared');
    } catch (e) {
      print('❌ Error clearing session token: $e');
    }
  }

  // Debug Methods
  static Future<void> printStorageInfo() async {
    try {
      final allData = await _secureStorage.readAll();
      print('\n📱 SECURE STORAGE INFO:');
      print('Total items: ${allData.length}');
      allData.forEach((key, value) {
        print('$key: ${value.substring(0, math.min(50, value.length))}...');
      });
      print('');
    } catch (e) {
      print('❌ Error reading storage info: $e');
    }
  }
}
