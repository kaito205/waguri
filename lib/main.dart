import 'package:flutter/material.dart';
import 'package:mywaguri/Screens/splash_screen.dart';
import 'theme.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:mywaguri/Services/notification_service.dart';
import 'firebase_options.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await NotificationService.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: theme(),
      home: const SplashScreen(),
    );
  }
}
