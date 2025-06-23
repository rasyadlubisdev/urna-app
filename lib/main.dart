// main.dart
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'screens/auth_screen.dart';
import 'utils/app_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    final cameras = await availableCameras();
    runApp(URNAApp(cameras: cameras));
  } catch (e) {
    print('Error initializing cameras: $e');
    runApp(URNAApp(cameras: []));
  }
}

class URNAApp extends StatelessWidget {
  final List<CameraDescription> cameras;

  const URNAApp({Key? key, required this.cameras}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'URNA - Visual Assistant',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.light,
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: AuthScreen(cameras: cameras),
      debugShowCheckedModeBanner: AppConfig.isDevelopmentMode,
    );
  }
}
