// utils/file_debug_utils.dart - FIXED M4A VALIDATION
import 'dart:io';
import 'dart:typed_data';

class FileDebugUtils {
  // Debug file content and headers
  static Future<void> debugFile(File file, String description) async {
    try {
      print('\n🔍 DEBUGGING FILE: $description');
      print('📁 Path: ${file.path}');
      print('📁 Exists: ${await file.exists()}');

      if (await file.exists()) {
        final size = await file.length();
        print('📁 Size: $size bytes');

        if (size > 0) {
          // Read first 16 bytes to check file header
          final bytes = await file.readAsBytes();
          final header = bytes.take(16).toList();

          print(
            '📁 Header (hex): ${header.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}',
          );
          print('📁 Header (dec): ${header.join(' ')}');

          // Show more bytes for analysis (first 64 bytes)
          if (bytes.length > 16) {
            final extended = bytes.take(64).toList();
            final hexDump = extended
                .map((b) => b.toRadixString(16).padLeft(2, '0'))
                .join(' ');
            print('📁 Extended hex dump (64 bytes): $hexDump');
          }

          // Detect file type from header
          final detectedType = _detectFileType(bytes);
          print('📁 Detected type: $detectedType');

          // Show readable content if text-based
          if (size < 1000) {
            try {
              final content = String.fromCharCodes(bytes.take(200));
              if (content.codeUnits.every(
                (c) => c >= 32 && c <= 126 || c == 10 || c == 13,
              )) {
                print('📁 Content preview: $content');
              }
            } catch (e) {
              print('📁 Content: Binary data');
            }
          }
        } else {
          print('❌ File is empty');
        }
      } else {
        print('❌ File does not exist');
      }

      print('🔍 END DEBUG: $description\n');
    } catch (e) {
      print('❌ Error debugging file $description: $e');
    }
  }

  // FIXED: Enhanced file type detection with better M4A support
  static String _detectFileType(Uint8List bytes) {
    if (bytes.length < 4) return 'Unknown (too small)';

    // JPEG signature
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
      return 'JPEG';
    }

    // PNG signature
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'PNG';
    }

    // WAV signature (RIFF)
    if (bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46) {
      return 'WAV';
    }

    // MP3 signature (MPEG frame header)
    if (bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0) {
      return 'MP3';
    }

    // Check for AAC in ADTS container
    if (bytes[0] == 0xFF && (bytes[1] & 0xF0) == 0xF0) {
      return 'AAC/ADTS';
    }

    // FIXED: M4A/MP4 container detection (more comprehensive)
    if (bytes.length >= 8) {
      // Look for 'ftyp' box at offset 4
      if (bytes[4] == 0x66 &&
          bytes[5] == 0x74 &&
          bytes[6] == 0x79 &&
          bytes[7] == 0x70) {
        // Check specific M4A brand identifiers
        if (bytes.length >= 12) {
          // Common M4A brands: M4A , mp41, mp42, isom, etc.
          final brand = String.fromCharCodes(bytes.sublist(8, 12));
          print('📁 M4A Brand: "$brand"');

          // Return more specific type
          if (brand.startsWith('M4A') ||
              brand.startsWith('mp4') ||
              brand.startsWith('iso')) {
            return 'M4A'; // Simplified return for M4A files
          }
        }
        return 'MP4/M4A'; // Generic MP4 container
      }
    }

    // Alternative M4A detection: Look for 'moov' or 'mdat' boxes
    if (bytes.length >= 12) {
      for (int i = 0; i < bytes.length - 8; i += 4) {
        if (i + 7 < bytes.length) {
          final boxType = String.fromCharCodes(bytes.sublist(i + 4, i + 8));
          if (boxType == 'moov' || boxType == 'mdat' || boxType == 'free') {
            return 'M4A/MP4';
          }
        }
      }
    }

    return 'Unknown';
  }

  // Copy file to accessible location for manual inspection
  static Future<String?> copyToDownloads(
    File sourceFile,
    String newName,
  ) async {
    try {
      print('📋 Attempting to copy file for manual inspection...');
      print('📋 Source: ${sourceFile.path}');
      print('📋 Target name: $newName');

      // Try multiple accessible locations (ordered by preference)
      final accessiblePaths = [
        '/storage/emulated/0/Download',
        '/storage/emulated/0/Downloads', // Alternative spelling
        '/storage/emulated/0/Documents',
        '/storage/emulated/0/Pictures', // For images
        '/storage/emulated/0/Music', // For audio files
        '/storage/emulated/0/Movies', // Alternative for media
        '/storage/emulated/0/DCIM', // Camera folder
        '/storage/emulated/0/Android/data/com.example.fp_kp3l_urnal_app/files',
        '/storage/emulated/0',
        '/sdcard/Download',
        '/sdcard/Downloads',
        '/sdcard',
        '/data/media/0/Download',
        '/mnt/sdcard/Download',
      ];

      for (final path in accessiblePaths) {
        try {
          print('📋 Trying path: $path');
          final dir = Directory(path);

          // Check if directory exists
          if (await dir.exists()) {
            print('📋 Directory exists: $path');

            final targetFile = File('$path/$newName');

            // Try to copy file
            await sourceFile.copy(targetFile.path);

            // Verify the copy was successful
            if (await targetFile.exists()) {
              final sourceSize = await sourceFile.length();
              final targetSize = await targetFile.length();

              print('📋 Copy verification:');
              print('📋   Source size: $sourceSize bytes');
              print('📋   Target size: $targetSize bytes');

              if (targetSize > 0 && targetSize == sourceSize) {
                print('✅ File copied successfully to: ${targetFile.path}');
                print('✅ YOU CAN FIND THE FILE AT: ${targetFile.path}');
                print('✅ Open your File Manager and navigate to: $path');
                return targetFile.path;
              } else {
                print('❌ Copy verification failed - size mismatch');
                try {
                  await targetFile.delete();
                } catch (e) {
                  print('⚠️ Failed to delete failed copy: $e');
                }
              }
            } else {
              print('❌ Target file not created');
            }
          } else {
            print('📋 Directory does not exist: $path');
          }
        } catch (e) {
          print('⚠️ Failed to copy to $path: $e');
          continue;
        }
      }

      print('❌ Failed to copy to any accessible location');
      print('💡 Try using ADB to pull files:');
      print('💡   adb pull ${sourceFile.path} ./debug_file');
    } catch (e) {
      print('❌ Failed to copy file: $e');
    }
    return null;
  }

  // FIXED: Improved validation logic for M4A files
  static Future<bool> isValidForApi(File file, String expectedType) async {
    try {
      if (!await file.exists()) {
        print('❌ File does not exist');
        return false;
      }

      final size = await file.length();
      if (size == 0) {
        print('❌ File is empty');
        return false;
      }

      final bytes = await file.readAsBytes();
      final detectedType = _detectFileType(bytes);

      print(
        '🔍 Expected: $expectedType, Detected: $detectedType, Size: $size bytes',
      );

      // FIXED: Improved validation rules with better M4A support
      final expectedLower = expectedType.toLowerCase();
      final detectedLower = detectedType.toLowerCase();

      if (expectedLower == 'jpeg' || expectedLower == 'jpg') {
        if (detectedType == 'JPEG' && size > 100) {
          print('✅ Valid JPEG file');
          return true;
        } else {
          print('❌ Invalid JPEG: wrong signature or too small');
          return false;
        }
      }
      // FIXED: Enhanced M4A validation
      else if (expectedLower == 'm4a' ||
          expectedLower == 'mp4' ||
          expectedLower == 'm4a/mp4') {
        // Accept various detected M4A formats
        if (detectedLower.contains('m4a') ||
            detectedLower.contains('mp4') ||
            detectedType == 'M4A' ||
            detectedType == 'MP4/M4A' ||
            detectedType == 'M4A/MP4') {
          if (size > 1000) {
            // Minimum reasonable size for M4A
            print('✅ Valid M4A/MP4 file (detected as: $detectedType)');
            return true;
          } else {
            print('❌ M4A file too small: $size bytes (minimum 1000 bytes)');
            return false;
          }
        } else {
          print('❌ Invalid M4A: detected as $detectedType (expected M4A/MP4)');

          // Additional diagnostic for M4A files
          if (bytes.length >= 8) {
            final firstEightBytes = bytes.take(8).toList();
            final hexDump = firstEightBytes
                .map((b) => b.toRadixString(16).padLeft(2, '0'))
                .join(' ');
            print('🔍 First 8 bytes (hex): $hexDump');

            // Check if it might be AAC in different container
            if (bytes[0] == 0xFF && (bytes[1] & 0xF0) == 0xF0) {
              print('💡 Detected AAC ADTS - might be valid audio');
              return true; // Accept AAC files too
            }
          }

          return false;
        }
      }
      // FIXED: Add support for other audio formats
      else if (expectedLower == 'mp3') {
        if (detectedType == 'MP3' && size > 100) {
          print('✅ Valid MP3 file');
          return true;
        } else {
          print('❌ Invalid MP3: wrong signature or too small');
          return false;
        }
      } else if (expectedLower == 'aac') {
        if (detectedType == 'AAC/ADTS' && size > 100) {
          print('✅ Valid AAC file');
          return true;
        } else {
          print('❌ Invalid AAC: wrong signature or too small');
          return false;
        }
      }

      // If no specific rule found
      print('⚠️ Unknown expected type: $expectedType');
      return false;
    } catch (e) {
      print('❌ Error validating file: $e');
      return false;
    }
  }

  // ADDED: Helper method to get comprehensive file info
  static Future<Map<String, dynamic>> getFileInfo(File file) async {
    try {
      if (!await file.exists()) {
        return {'exists': false};
      }

      final size = await file.length();
      final bytes = await file.readAsBytes();
      final detectedType = _detectFileType(bytes);

      final info = {
        'exists': true,
        'path': file.path,
        'size': size,
        'detectedType': detectedType,
        'extension': file.path.split('.').last.toLowerCase(),
      };

      // Add specific info for M4A files
      if (detectedType.toLowerCase().contains('m4a') ||
          detectedType.toLowerCase().contains('mp4')) {
        info['isValidM4A'] = size > 1000;
        info['containerFormat'] = 'ISO Base Media File Format';

        if (bytes.length >= 12) {
          final brand = String.fromCharCodes(bytes.sublist(8, 12));
          info['brand'] = brand.trim();
        }
      }

      return info;
    } catch (e) {
      return {'exists': false, 'error': e.toString()};
    }
  }

  // ADDED: Test method to validate audio service output
  static Future<bool> validateAudioServiceOutput(File audioFile) async {
    try {
      print('\n🧪 VALIDATING AUDIO SERVICE OUTPUT');

      final info = await getFileInfo(audioFile);
      print('📊 File info: $info');

      if (!info['exists']) {
        print('❌ Audio file does not exist');
        return false;
      }

      final size = info['size'] as int;
      final detectedType = info['detectedType'] as String;

      // Check minimum size
      if (size < 1000) {
        print('❌ Audio file too small: $size bytes');
        return false;
      }

      // Check if it's a valid audio format
      final validAudioTypes = ['M4A', 'MP4/M4A', 'M4A/MP4', 'MP3', 'AAC/ADTS'];
      final isValidAudio = validAudioTypes.any(
        (type) => detectedType.contains(type) || type.contains(detectedType),
      );

      if (!isValidAudio) {
        print('❌ Invalid audio format detected: $detectedType');
        return false;
      }

      print('✅ Audio file validation passed');
      print('📊 Format: $detectedType, Size: $size bytes');
      return true;
    } catch (e) {
      print('❌ Error validating audio service output: $e');
      return false;
    }
  }
}
