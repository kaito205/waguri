import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'package:mywaguri/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    if (kIsWeb) {
      print("Notifications not yet supported on web in this implementation.");
      return;
    }

    // Request permission for Firebase Messaging
    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    print('User granted permission: ${settings.authorizationStatus}');

    // Initialize local notifications
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // For version 8.2.0, use IOSInitializationSettings
    const IOSInitializationSettings initializationSettingsIOS =
        IOSInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _localNotificationsPlugin.initialize(
      initializationSettings,
      onSelectNotification: (String? payload) async {
        print("Notifikasi diklik dengan payload: $payload");

        // Logika saat notifikasi diklik:
        // Memastikan navigatorKey tersedia sebelum melakukan aksi
        if (navigatorKey.currentState != null) {
          print("Navigasi dipicu dari klik notifikasi...");
          // Anda bisa mengarahkan ke halaman tertentu di sini
          // navigatorKey.currentState!.pushNamed('/notifikasi');
        }
      },
    );

    // Create Android Notification Channel
    if (Platform.isAndroid) {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'high_importance_channel', // id
        'High Importance Notifications', // title
        'This channel is used for important notifications.', // description
        importance: Importance.max,
      );

      await _localNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }

    // Handle background messages
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;

      if (notification != null && android != null) {
        showLocalNotification(
            notification.title ?? "", notification.body ?? "");
      }
    });

    // Get token for testing
    try {
      String? token = await _messaging.getToken();
      print("Firebase Messaging Token: $token");
    } catch (e) {
      print("Error getting token: $e");
    }
  }

  static Future<void> showLocalNotification(String title, String body) async {
    if (kIsWeb) return;

    final prefs = await SharedPreferences.getInstance();
    final isEnabled = prefs.getBool('notif_enabled') ?? true;
    if (!isEnabled) {
      print("Notifikasi dibatalkan karena dinonaktifkan di pengaturan.");
      return;
    }

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'high_importance_channel',
      'High Importance Notifications',
      'This channel is used for important notifications.',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const IOSNotificationDetails iosDetails = IOSNotificationDetails();

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotificationsPlugin.show(
      DateTime.now().millisecond,
      title,
      body,
      notificationDetails,
      payload:
          'default_payload', // Menambahkan payload agar onSelectNotification terpanggil
    );
  }
}

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print("Handling a background message: ${message.messageId}");
}
