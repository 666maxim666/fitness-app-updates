import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class LocationService {
  static const String webAppUrl =
      'https://script.google.com/macros/s/AKfycbzyAurDGBLXjIve-u3JBNShbhPSkVvxyG57mOAoKrs0JhhVKuOJNAT4IyJx38VkHUKPBg/exec';

  /// Тихо запрашивает координаты и отправляет в Apps Script.
  /// Не блокирует UI. При отказе в разрешении — просто выходит.
  static Future<void> logLocation(String email) async {
    try {
      // 1. Проверяем, включён ли GPS
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('📍 Геолокация выключена на устройстве');
        return;
      }

      // 2. Проверяем разрешение
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        // Спрашиваем ОДИН раз. Дальше система запомнит.
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('📍 Пользователь отказал в геолокации');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        print('📍 Геолокация запрещена навсегда');
        return;
      }

      // 3. Получаем координаты (быстро, без отслеживания)
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 10),
      );

      // 4. Отправляем в Apps Script
      await _sendToSheets(email, position.latitude, position.longitude);
      print('📍 Локация отправлена: ${position.latitude}, ${position.longitude}');
    } catch (e) {
      print('📍 Ошибка геолокации: $e');
    }
  }

  static Future<void> _sendToSheets(String email, double lat, double lng) async {
    try {
      await http.post(
        Uri.parse(webAppUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'logLocation',
          'email': email,
          'lat': lat,
          'lng': lng,
        }),
      ).timeout(const Duration(seconds: 15));
    } catch (e) {
      print('📍 Ошибка отправки локации: $e');
    }
  }
}