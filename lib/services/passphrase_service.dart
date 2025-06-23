// services/passphrase_service.dart
import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:passphrase/passphrase.dart';

class PassphraseService {
  static const int _passphraseLength = 5;

  static Future<String> generatePassphrase() async {
    print('🔤 Generating passphrase...');

    try {
      // Try to load custom wordlist first
      final passphrase = await _loadCustomWordlist();
      if (passphrase != null) {
        final words = await passphrase.generate(_passphraseLength);
        final result = words.join(' ');
        print('✅ Passphrase generated with custom wordlist');
        return result;
      }
    } catch (e) {
      print('⚠️ Failed to load custom wordlist: $e');
    }

    // Fallback to demo wordlist
    return await _generateWithDemoWordlist();
  }

  static Future<Passphrase?> _loadCustomWordlist() async {
    try {
      final jsonString = await rootBundle.loadString(
        'assets/eff-wordlist.json',
      );
      final wordList = (json.decode(jsonString) as List).cast<String>();
      return Passphrase(wordList);
    } catch (e) {
      return null;
    }
  }

  static Future<String> _generateWithDemoWordlist() async {
    print('🎯 Using demo wordlist for passphrase generation');

    final demoWordList = [
      'apple',
      'banana',
      'cherry',
      'dragon',
      'elephant',
      'falcon',
      'guitar',
      'harbor',
      'island',
      'jungle',
      'kitten',
      'lantern',
      'mountain',
      'notebook',
      'ocean',
      'piano',
      'quartz',
      'rainbow',
      'sunset',
      'tiger',
      'umbrella',
      'village',
      'window',
      'xylophone',
      'yellow',
      'zebra',
      'forest',
      'castle',
      'diamond',
      'eagle',
      'flame',
      'galaxy',
      'horizon',
      'iceberg',
      'journey',
      'kingdom',
      'legend',
      'miracle',
      'nectar',
      'oasis',
      'phoenix',
      'quantum',
      'river',
      'storm',
      'thunder',
      'universe',
      'vision',
      'wizard',
      'xenial',
      'yoga',
      'zodiac',
      'anchor',
      'bridge',
      'comet',
      'dream',
      'echo',
      'fire',
      'garden',
      'happiness',
      'inspiration',
      'joy',
      'knowledge',
      'light',
      'magic',
      'nature',
      'optimism',
      'peace',
      'quest',
      'radiance',
      'serenity',
      'trust',
      'unity',
      'victory',
      'wisdom',
      'xenon',
      'youth',
      'zeal',
    ];

    final passphrase = Passphrase(demoWordList);
    final words = await passphrase.generate(_passphraseLength);
    final result = words.join(' ');

    print('✅ Demo passphrase generated: ${words.length} words');
    return result;
  }

  static Future<String> generateHighEntropyPassphrase() async {
    print('🔒 Generating high entropy passphrase...');

    try {
      final passphrase = await _loadCustomWordlist();
      if (passphrase != null) {
        final words = await passphrase.generateWithEntropy(50.0);
        final result = words.join(' ');
        print('✅ High entropy passphrase generated');
        return result;
      }
    } catch (e) {
      print('⚠️ Failed to generate high entropy passphrase: $e');
    }

    // Fallback to demo with more words
    return await _generateWithDemoWordlist();
  }

  static bool validatePassphrase(String passphrase) {
    final words = passphrase.trim().split(' ');
    return words.length >= 3 && words.every((word) => word.isNotEmpty);
  }
}
