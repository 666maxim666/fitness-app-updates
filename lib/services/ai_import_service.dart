import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/user.dart';

class AiChatService {
  static const String webAppUrl =
      'https://script.google.com/macros/s/AKfycbzyAurDGBLXjIve-u3JBNShbhPSkVvxyG57mOAoKrs0JhhVKuOJNAT4IyJx38VkHUKPBg/exec';

  /// Отправляет сообщение в Apps Script → Gemini.
  /// context — профиль пользователя + состояние.
  /// chatHistory — последние N сообщений для контекста.
  static Future<Map<String, dynamic>> send({
    required String email,
    required String question,
    required Map<String, dynamic> context,
    List<Map<String, String>> chatHistory = const [],
    String? timezone,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse(webAppUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'action': 'chat',
              'email': email,
              'question': question,
              'context': context,
              'chatHistory': chatHistory,
              'timezone': timezone,
            }),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        return decoded is Map<String, dynamic>
            ? decoded
            : {'success': false, 'error': 'Неверный формат ответа'};
      } else {
        return {
          'success': false,
          'error': 'HTTP ${response.statusCode}: ${response.body}',
        };
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Собирает context для передачи в Apps Script.
  /// Используется AiChatDialog.
  static Map<String, dynamic> buildContext({
    required AppUser user,
    required int waterToday,
    required int waterGoal,
    required bool creatineToday,
    required bool onRest,
    required int restDaysLeft,
    required int pushupGoal,
    required int pushupToday,
    required int totalWorkouts,
    required int attendancePercent,
  }) {
    return {
      'name': user.name,
      'weight': user.weight,
      'height': user.height ?? 180,
      'gender': user.gender ?? 'male',
      'trainingDays': user.trainingDays.join(','),
      'waterToday': waterToday,
      'waterGoal': waterGoal,
      'creatineToday': creatineToday,
      'onRest': onRest,
      'restDaysLeft': restDaysLeft,
      'pushupGoal': pushupGoal,
      'pushupToday': pushupToday,
      'totalWorkouts': totalWorkouts,
      'attendancePercent': attendancePercent,
    };
  }
}