// screens/auth_screen.dart
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math';
import '../services/turnstile_service.dart';
import '../services/passphrase_service.dart';
import '../services/biometric_service.dart';
import '../services/storage_service.dart';
import '../services/api_service.dart';
import '../models/auth_models.dart';
import '../utils/feedback_utils.dart';
import '../utils/app_config.dart';
import 'camera_screen.dart';

class AuthScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const AuthScreen({Key? key, required this.cameras}) : super(key: key);

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with TickerProviderStateMixin {
  // State variables
  bool _isLoading = false;
  bool _isBiometricAvailable = false;
  bool _isRegistered = false;
  String _statusMessage = 'Memulai URNA...';
  UserCredential? _userCredential;

  // Animation controllers
  late AnimationController _pulseController;
  late AnimationController _fadeController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeApp();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  // ==========================================
  // INITIALIZATION METHODS
  // ==========================================

  void _initializeAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    _pulseController.repeat(reverse: true);
    _fadeController.forward();
  }

  Future<void> _initializeApp() async {
    try {
      // Initialize feedback utils
      await FeedbackUtils.initializeTts();

      // Check biometric availability
      final isBiometricAvailable = await BiometricService.isAvailable();

      // Check if user is already registered
      final isRegistered = await StorageService.isUserRegistered();
      final userCredential = await StorageService.loadCredential();

      setState(() {
        _isBiometricAvailable = isBiometricAvailable;
        _isRegistered = isRegistered;
        _userCredential = userCredential;

        if (!isBiometricAvailable) {
          _statusMessage = 'Biometrik tidak didukung pada perangkat ini';
        } else if (isRegistered && userCredential != null) {
          _statusMessage =
              'Selamat datang kembali! Tekan untuk masuk dengan sidik jari';
        } else {
          _statusMessage =
              'Selamat datang di URNA! Tekan untuk membuat akun baru';
        }
      });

      // Welcome message
      if (isBiometricAvailable) {
        await FeedbackUtils.speak(
          isRegistered
              ? 'Selamat datang kembali di URNA. Tekan tombol untuk masuk dengan sidik jari.'
              : 'Selamat datang di URNA. Tekan tombol untuk membuat akun baru.',
        );
      } else {
        await FeedbackUtils.speak(
          'Maaf, perangkat Anda tidak mendukung autentikasi biometrik.',
        );
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: ${e.toString()}';
      });
      await FeedbackUtils.errorFeedback();
    }
  }

  // ==========================================
  // AUTHENTICATION METHODS
  // ==========================================

  Future<void> _handleAuthentication() async {
    if (!_isBiometricAvailable) {
      _showSnackBar('Biometrik tidak tersedia pada perangkat ini');
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = _isRegistered
          ? 'Memverifikasi sidik jari...'
          : 'Membuat akun baru...';
    });

    try {
      if (_isRegistered && _userCredential != null) {
        await _handleLogin();
      } else {
        await _handleRegistration();
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: ${e.toString()}';
      });
      _showSnackBar('Terjadi kesalahan: $e');
      await FeedbackUtils.errorFeedback();
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _handleRegistration() async {
    try {
      setState(() {
        _statusMessage = 'Mendapatkan token keamanan...';
      });

      // Step 1: Get Turnstile token
      final turnstileToken = await TurnstileService.getToken();

      setState(() {
        _statusMessage = 'Membuat passphrase unik...';
      });

      // Step 2: Generate passphrase with retry mechanism
      String passphrase;
      bool isUnique = false;
      int retryCount = 0;
      const maxRetries = 5;

      do {
        passphrase = await PassphraseService.generatePassphrase();

        if (AppConfig.isBackendAuthReady) {
          // Check if passphrase is unique on backend
          final deviceId = _generateDeviceId();
          final authResponse = await ApiService.registerUser(
            passphrase: passphrase,
            turnstileToken: turnstileToken,
            deviceId: deviceId,
          );

          if (authResponse.success) {
            isUnique = true;
          } else if (authResponse.message.contains('already exists')) {
            retryCount++;
            setState(() {
              _statusMessage =
                  'Passphrase sudah ada, membuat ulang... (${retryCount}/$maxRetries)';
            });
            await FeedbackUtils.speak('Membuat passphrase baru');
          } else {
            throw Exception(authResponse.message);
          }
        } else {
          // In development mode, assume always unique
          isUnique = true;
        }
      } while (!isUnique && retryCount < maxRetries);

      if (!isUnique) {
        throw Exception(
          'Gagal membuat passphrase unik setelah $maxRetries percobaan',
        );
      }

      setState(() {
        _statusMessage = 'Daftarkan sidik jari Anda...';
      });

      // Step 3: Biometric authentication for registration
      final biometricResult =
          await BiometricService.authenticateForRegistration();
      if (!biometricResult) {
        throw Exception('Autentikasi biometrik gagal');
      }

      setState(() {
        _statusMessage = 'Menyimpan kredensial...';
      });

      // Step 4: Save credential to secure storage
      final now = DateTime.now();
      final credential = UserCredential(
        passphrase: passphrase,
        turnstileToken: turnstileToken,
        deviceId: _generateDeviceId(),
        createdAt: now,
        lastUsed: now,
      );

      await StorageService.saveCredential(credential);

      setState(() {
        _userCredential = credential;
        _isRegistered = true;
        _statusMessage = 'Akun berhasil dibuat! Menuju kamera...';
      });

      await FeedbackUtils.successFeedback();
      await FeedbackUtils.speak(
        'Akun berhasil dibuat. Selamat datang di URNA!',
      );

      // Navigate to camera screen
      await _navigateToCamera(credential);
    } catch (e) {
      print('❌ Registration error: $e');
      setState(() {
        _statusMessage = 'Registrasi gagal: $e';
      });
      await FeedbackUtils.errorFeedback();
      throw e;
    }
  }

  Future<void> _handleLogin() async {
    try {
      setState(() {
        _statusMessage = 'Mendapatkan token keamanan...';
      });

      // Step 1: Get Turnstile token
      final turnstileToken = await TurnstileService.getToken();

      setState(() {
        _statusMessage = 'Verifikasi sidik jari...';
      });

      // Step 2: Biometric authentication for login
      final biometricResult = await BiometricService.authenticateForLogin();
      if (!biometricResult) {
        throw Exception('Autentikasi biometrik gagal');
      }

      setState(() {
        _statusMessage = 'Memuat kredensial...';
      });

      // Step 3: Load credential from secure storage
      final credential = await StorageService.loadCredential();
      if (credential == null) {
        throw Exception('Kredensial tidak ditemukan');
      }

      // Step 4: Authenticate with backend (if ready)
      if (AppConfig.isBackendAuthReady) {
        setState(() {
          _statusMessage = 'Verifikasi dengan server...';
        });

        final authResponse = await ApiService.loginUser(
          passphrase: credential.passphrase,
          turnstileToken: turnstileToken,
        );

        if (!authResponse.success) {
          throw Exception(authResponse.message);
        }

        // Save session token
        if (authResponse.sessionToken != null) {
          await StorageService.saveSessionToken(authResponse.sessionToken!);
        }
      }

      // Step 5: Update last used timestamp
      await StorageService.updateLastUsed();

      setState(() {
        _statusMessage = 'Login berhasil! Menuju kamera...';
      });

      await FeedbackUtils.successFeedback();
      await FeedbackUtils.speak('Login berhasil. Selamat datang kembali!');

      // Navigate to camera screen
      await _navigateToCamera(credential);
    } catch (e) {
      print('❌ Login error: $e');
      setState(() {
        _statusMessage = 'Login gagal: $e';
      });
      await FeedbackUtils.errorFeedback();
      throw e;
    }
  }

  // ==========================================
  // UTILITY METHODS
  // ==========================================

  Future<void> _navigateToCamera(UserCredential credential) async {
    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              CameraScreen(cameras: widget.cameras, credential: credential),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 1000),
        ),
      );
    }
  }

  String _generateDeviceId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = Random().nextInt(999999);
    return 'urna_${Platform.operatingSystem}_${timestamp}_$random';
  }

  Future<void> _resetAccount() async {
    try {
      setState(() {
        _isLoading = true;
        _statusMessage = 'Menghapus akun...';
      });

      await StorageService.clearAllData();

      setState(() {
        _isRegistered = false;
        _userCredential = null;
        _statusMessage = 'Akun berhasil dihapus. Tekan untuk membuat akun baru';
        _isLoading = false;
      });

      await FeedbackUtils.speak('Akun berhasil dihapus');
      _showSnackBar('Akun berhasil dihapus');
    } catch (e) {
      setState(() {
        _statusMessage = 'Error menghapus akun: $e';
        _isLoading = false;
      });
      await FeedbackUtils.errorFeedback();
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

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  // ==========================================
  // UI BUILD METHODS
  // ==========================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue.shade50, Colors.white, Colors.blue.shade50],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  const SizedBox(height: 40),
                  _buildLogo(),
                  const SizedBox(height: 40),
                  _buildAppTitle(),
                  const SizedBox(height: 20),
                  _buildModeIndicator(),
                  const SizedBox(height: 40),
                  _buildAuthenticationButton(),
                  const SizedBox(height: 24),
                  _buildStatusMessage(),
                  const SizedBox(height: 30),
                  // if (_userCredential != null) _buildCredentialInfo(),
                  const SizedBox(height: 20),
                  _buildFeatureHighlights(),
                  // if (_isRegistered && AppConfig.isDevelopmentMode) ...[
                  //   const SizedBox(height: 20),
                  //   _buildResetButton(),
                  // ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _pulseAnimation.value,
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade600, Colors.blue.shade800],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(60),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withOpacity(0.3),
                  spreadRadius: 0,
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: const Icon(Icons.visibility, size: 60, color: Colors.white),
          ),
        );
      },
    );
  }

  Widget _buildAppTitle() {
    return Column(
      children: [
        Text(
          'URNA',
          style: TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.bold,
            color: Colors.blue.shade600,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Mata Digital untuk Tunanetra',
          style: TextStyle(
            fontSize: 18,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w300,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildModeIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppConfig.isDevelopmentMode
            ? Colors.orange.shade100
            : Colors.green.shade100,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppConfig.isDevelopmentMode
              ? Colors.orange.shade300
              : Colors.green.shade300,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            AppConfig.isDevelopmentMode ? Icons.code : Icons.cloud_done,
            size: 16,
            color: AppConfig.isDevelopmentMode
                ? Colors.orange.shade700
                : Colors.green.shade700,
          ),
          const SizedBox(width: 8),
          Text(
            AppConfig.isDevelopmentMode ? 'DEVELOPMENT MODE' : 'BETA MODE',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppConfig.isDevelopmentMode
                  ? Colors.orange.shade700
                  : Colors.green.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthenticationButton() {
    return GestureDetector(
      onTap: _isLoading ? null : _handleAuthentication,
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          gradient: _isLoading
              ? LinearGradient(
                  colors: [Colors.grey.shade400, Colors.grey.shade500],
                )
              : _isRegistered
              ? LinearGradient(
                  colors: [Colors.blue.shade600, Colors.blue.shade800],
                )
              : LinearGradient(
                  colors: [Colors.green.shade600, Colors.green.shade800],
                ),
          borderRadius: BorderRadius.circular(60),
          boxShadow: [
            BoxShadow(
              color: _isRegistered
                  ? Colors.blue.withOpacity(0.3)
                  : Colors.green.withOpacity(0.3),
              spreadRadius: 0,
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: _isLoading
            ? const CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 3,
              )
            : Icon(
                _isRegistered ? Icons.fingerprint : Icons.add_circle,
                size: 60,
                color: Colors.white,
              ),
      ),
    );
  }

  Widget _buildStatusMessage() {
    return Text(
      _statusMessage,
      style: TextStyle(
        fontSize: 16,
        color: Colors.grey.shade700,
        fontWeight: FontWeight.w500,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildCredentialInfo() {
    if (_userCredential == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_circle, color: Colors.blue.shade600, size: 24),
              const SizedBox(width: 12),
              Text(
                'Akun Tersimpan',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoRow(
            'Passphrase',
            '${_userCredential!.passphrase.substring(0, 15)}...',
          ),
          _buildInfoRow(
            'Device ID',
            _userCredential!.deviceId.substring(0, 20) + '...',
          ),
          _buildInfoRow('Dibuat', _formatDate(_userCredential!.createdAt)),
          _buildInfoRow(
            'Terakhir Digunakan',
            _formatDate(_userCredential!.lastUsed),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade800,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureHighlights() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            'Fitur URNA:',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 12),
          _buildFeatureItem('👁️', 'Analisis Visual Real-time'),
          _buildFeatureItem('🗣️', 'AI Assistant Interaktif'),
          _buildFeatureItem('🎤', 'Voice Recognition'),
          _buildFeatureItem('🔒', 'Autentikasi Biometrik Aman'),
          _buildFeatureItem('🔐', 'Turnstile Security'),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(String icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 12),
          Text(
            text,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  Widget _buildResetButton() {
    return TextButton.icon(
      onPressed: _isLoading ? null : _resetAccount,
      icon: Icon(Icons.delete_outline, color: Colors.red.shade600),
      label: Text(
        'Reset Akun (Development)',
        style: TextStyle(color: Colors.red.shade600),
      ),
    );
  }
}
