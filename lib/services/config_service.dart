import 'package:http/http.dart' as http;
import 'dart:convert';

class ConfigService {
  static const String baseUrl =
      'https://raw.githubusercontent.com/666maxim666/fitness-app-updates/main/config/';

  static const List<String> configFiles = [
    'colors.json',
    'sizes.json',
    'texts.json',
    'bottomNav.json',
    'calendar.json',
    'buttons.json',
    'cards.json',
    'profile.json',
    'notifications.json',
  ];

  static Future<Map<String, dynamic>> loadAll() async {
    Map<String, dynamic> fullConfig = {};
    for (var file in configFiles) {
      try {
        final response = await http.get(Uri.parse(baseUrl + file));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final key = file.split('.').first;
          fullConfig[key] = data;
        } else {
          print('Ошибка загрузки $file: ${response.statusCode}');
        }
      } catch (e) {
        print('Ошибка загрузки $file: $e');
      }
    }
    return fullConfig;
  }

  static T getValue<T>(Map<String, dynamic> config, String key, T defaultValue) {
    final parts = key.split('.');
    dynamic current = config;
    for (var part in parts) {
      if (current is Map && current.containsKey(part)) {
        current = current[part];
      } else {
        return defaultValue;
      }
    }
    return current is T ? current : defaultValue;
  }
}