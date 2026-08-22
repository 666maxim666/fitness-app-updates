import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'google_sheets_service.dart';

class NotificationService {
  static final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static Function(Map<String, dynamic>)? onNotificationReceived;

  static Future<void> init() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings();
    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _localNotifications.initialize(initSettings);

    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    String? token = await _fcm.getToken();
    if (token != null) {
      print('📱 FCM Token: $token');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fcm_token', token);
    }

    FirebaseMessaging.onBackgroundMessage(_backgroundHandler);
    FirebaseMessaging.onMessage.listen(_foregroundHandler);
    FirebaseMessaging.onMessageOpenedApp.listen(_tapHandler);
  }

  @pragma('vm:entry-point')
  static Future<void> _backgroundHandler(RemoteMessage message) async {
    print('📩 Фоновое сообщение: ${message.notification?.title}');
  }

  static Future<void> _foregroundHandler(RemoteMessage message) async {
    print('📩 Сообщение в foreground: ${message.notification?.title}');
    _showLocalNotification(message);
    if (onNotificationReceived != null) {
      final data = {
        'title': message.notification?.title ?? 'Уведомление',
        'body': message.notification?.body ?? '',
        'time': DateTime.now().toLocal().toString(),
        'type': 'update',
        'read': false,
        'download_url': message.data['download_url'] ?? '',
      };
      onNotificationReceived!(data);
    }
    await _logToSheet(message);
  }

  static Future<void> _tapHandler(RemoteMessage message) async {
    print('👆 Пользователь нажал на уведомление');
    final url = message.data['download_url'];
    if (url != null && url.isNotEmpty) {
      // открыть ссылку (можно добавить url_launcher)
    }
  }

  static Future<void> _showLocalNotification(RemoteMessage message) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'fitness_channel',
      'Фитнес-уведомления',
      channelDescription: 'Уведомления о тренировках и обновлениях',
      importance: Importance.high,
      priority: Priority.high,
    );
    const DarwinNotificationDetails iosDetails =
        DarwinNotificationDetails();
    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      message.hashCode,
      message.notification?.title,
      message.notification?.body,
      details,
    );
  }

  static Future<void> _logToSheet(RemoteMessage message) async {
    try {
      await GoogleSheetsService.appendRow('Уведомления', [
        DateTime.now().toIso8601String(),
        message.notification?.title ?? '',
        message.notification?.body ?? '',
        message.data['download_url'] ?? '',
        'FALSE',
      ]);
    } catch (e) {
      print('Ошибка логирования уведомления: $e');
    }
  }

  static Future<String?> getFcmToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('fcm_token');
  }
}