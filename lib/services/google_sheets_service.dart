import 'dart:convert';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:flutter/services.dart' show rootBundle;
import '../models/workout.dart';

class GoogleSheetsService {
  static const String spreadsheetId = '10dAoeKI_x_i7xT8CawggOgE8kIsClLOdqR_4dwGSc1E';

  // ==================== БАЗА ====================

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

  // ==================== ОБНОВЛЕНИЯ ====================

  static Future<Map<String, String>?> getLastUpdate() async {
    try {
      final rows = await getRows('Обновления');
      if (rows.isEmpty) return null;
      final last = rows.last;
      return {
        'version': last.isNotEmpty ? last[0].toString() : '',
        'message': last.length > 1 ? last[1].toString() : '',
        'download_url': last.length > 2 ? last[2].toString() : '',
      };
    } catch (e) {
      print('Ошибка чтения обновления: $e');
      return null;
    }
  }

  // ==================== ТРЕНИРОВКИ ====================

  static Future<List<Workout>> loadWorkouts(String userEmail) async {
    try {
      final rows = await getRows('Тренировки');
      final workouts = <Workout>[];
      for (var row in rows) {
        if (row.length >= 8 && row[0].toString() == userEmail) {
          // Вес: пусто → null (для проходки)
          final weightStr = row[5]?.toString().trim() ?? '';
          final double? weight = weightStr.isEmpty
              ? null
              : double.tryParse(weightStr);

          workouts.add(Workout(
            id: row[0].toString() + DateTime.now().millisecondsSinceEpoch.toString(),
            date: row[1].toString(),
            exercise: row[2].toString(),
            sets: int.tryParse(row[3].toString()) ?? 0,
            reps: int.tryParse(row[4].toString()) ?? 0,
            weight: weight,
            isProhodka: row[6].toString() == 'true',
            weekNumber: int.tryParse(row[7].toString()) ?? 1,
          ));
        }
      }
      return workouts;
    } catch (e) {
      print('Ошибка загрузки тренировок: $e');
      return [];
    }
  }

  // ==================== ВОДА И КРЕАТИН (ОБЪЕДИНЕНО) ====================

  /// Сохраняет воду и креатин за день **одним запросом**.
  /// Если строка есть — обновляет C (вода) и D (креатин) за раз.
  /// Если нет — добавляет новую.
  ///
  /// Это решает race condition: если пользователь одновременно нажал
  /// «+ вода» и «креатин», оба изменения уйдут в **одну** операцию.
  static Future<void> saveWaterAndCreatine({
    required String email,
    required String date,
    required int waterMl,
    required int creatineG,
  }) async {
    try {
      final api = await _getApi();

      // Одно чтение таблицы
      final response = await api.spreadsheets.values.get(
        spreadsheetId,
        'Питьё',
      );
      final rows = response.values ?? [];

      // Ищем существующую строку
      int rowIndex = -1;
      for (int i = 0; i < rows.length; i++) {
        if (rows[i].length >= 2 &&
            rows[i][0].toString() == email &&
            rows[i][1].toString() == date) {
          rowIndex = i + 1; // +1, потому что в Sheets строки с 1
          break;
        }
      }

      if (rowIndex != -1) {
        // Обновляем сразу обе колонки C (вода) и D (креатин) одним запросом
        final valueRange = sheets.ValueRange(values: [[waterMl, creatineG]]);
        await api.spreadsheets.values.update(
          valueRange,
          spreadsheetId,
          'Питьё!C$rowIndex:D$rowIndex',
          valueInputOption: 'USER_ENTERED',
        );
      } else {
        // Новая строка со всеми 4 колонками
        await api.spreadsheets.values.append(
          sheets.ValueRange(values: [[email, date, waterMl, creatineG]]),
          spreadsheetId,
          'Питьё',
          valueInputOption: 'USER_ENTERED',
        );
      }
    } catch (e) {
      print('Ошибка сохранения воды/креатина: $e');
    }
  }

  // ==================== ЗАГРУЗКА ВОДЫ ====================

  /// Возвращает историю за N дней:
  /// [{date: '2026-09-15', water: 1500, creatine: 5}, ...]
  static Future<List<Map<String, dynamic>>> loadDailyIntake(
      String email, int days) async {
    try {
      final rows = await getRows('Питьё');
      final result = <Map<String, dynamic>>[];
      for (var row in rows) {
        if (row.length >= 4 && row[0].toString() == email) {
          result.add({
            'date': row[1].toString(),
            'water': int.tryParse(row[2].toString()) ?? 0,
            'creatine': int.tryParse(row[3].toString()) ?? 0,
          });
        }
      }
      if (result.length > days) {
        result.removeRange(0, result.length - days);
      }
      return result;
    } catch (e) {
      print('Ошибка загрузки данных о воде: $e');
      return [];
    }
  }
}