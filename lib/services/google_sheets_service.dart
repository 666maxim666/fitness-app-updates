import 'dart:convert';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:flutter/services.dart' show rootBundle;
import '../models/workout.dart';

class GoogleSheetsService {
  static const String spreadsheetId = '10dAoeKI_x_i7xT8CawggOgE8kIsClLOdqR_4dwGSc1E';

  static Future<sheets.SheetsApi> _getApi() async {
    final jsonString = await rootBundle.loadString('assets/credentials.json');
    final jsonMap = jsonDecode(jsonString);
    final accountCredentials = auth.ServiceAccountCredentials.fromJson(jsonMap);
    final client = await auth.clientViaServiceAccount(
      accountCredentials,
      [sheets.SheetsApi.spreadsheetsScope],
    );
    return sheets.SheetsApi(client);
  }

  static Future<void> appendRow(String sheetName, List<dynamic> row) async {
    try {
      final api = await _getApi();
      final valueRange = sheets.ValueRange(values: [row]);
      await api.spreadsheets.values.append(
        valueRange,
        spreadsheetId,
        sheetName,
        valueInputOption: 'USER_ENTERED',
      );
    } catch (e) {
      print('Ошибка добавления строки: $e');
    }
  }

  static Future<List<List<dynamic>>> getRows(String sheetName) async {
    try {
      final api = await _getApi();
      final response = await api.spreadsheets.values.get(
        spreadsheetId,
        sheetName,
      );
      return response.values ?? [];
    } catch (e) {
      print('Ошибка получения данных: $e');
      return [];
    }
  }

  static Future<Map<String, String>?> getLastUpdate() async {
    try {
      final rows = await getRows('Обновления');
      if (rows.isEmpty) return null;
      final last = rows.last;
      return {
        'version': last.length > 0 ? last[0].toString() : '',
        'message': last.length > 1 ? last[1].toString() : '',
        'download_url': last.length > 2 ? last[2].toString() : '',
      };
    } catch (e) {
      print('Ошибка чтения обновления: $e');
      return null;
    }
  }

  // ===== ИСПРАВЛЕННЫЙ МЕТОД ЗАГРУЗКИ ТРЕНИРОВОК =====
  static Future<List<Workout>> loadWorkouts(String userEmail) async {
    try {
      final rows = await getRows('Тренировки');
      final workouts = <Workout>[];
      for (var row in rows) {
        if (row.length >= 8 && row[0] == userEmail) {
          workouts.add(Workout(
            id: row[0] + DateTime.now().millisecondsSinceEpoch.toString(),
            date: row[1], // ← строка, не DateTime
            exercise: row[2],
            sets: int.tryParse(row[3]) ?? 0,
            reps: int.tryParse(row[4]) ?? 0,
            weight: double.tryParse(row[5]) ?? 0,
            isProhodka: row[6] == 'true',
            weekNumber: int.tryParse(row[7]) ?? 1,
          ));
        }
      }
      return workouts;
    } catch (e) {
      print('Ошибка загрузки тренировок: $e');
      return [];
    }
  }
}