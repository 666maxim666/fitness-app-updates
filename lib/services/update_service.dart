import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateService {
  // Прямая ссылка на version.json на GitHub
  static const String versionUrl =
      'https://raw.githubusercontent.com/666maxim666/fitness-app-updates/main/version.json';

  // Проверка новой версии (возвращает Map или null)
  static Future<Map<String, String>?> checkNewVersion() async {
    try {
      final response = await http.get(Uri.parse(versionUrl));
      if (response.statusCode != 200) {
        print('❌ Не удалось загрузить version.json: ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body);
      final version = data['version'] as String?;
      final downloadUrl = data['download_url'] as String?;
      final whatsNew = data['whats_new'] as String?;

      if (version == null || downloadUrl == null) {
        print('❌ version.json не содержит нужных полей');
        return null;
      }

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      // Сравниваем версии (просто строковое сравнение, можно усложнить)
      if (version != currentVersion) {
        print('🔍 Текущая: $currentVersion, последняя: $version');
        return {
          'version': version,
          'download_url': downloadUrl,
          'whats_new': whatsNew ?? 'Обновление доступно',
        };
      } else {
        print('✅ Версия актуальна ($currentVersion)');
        return null;
      }
    } catch (e) {
      print('❌ Ошибка проверки обновлений: $e');
      return null;
    }
  }

  // Открыть ссылку на скачивание APK
  static Future<void> openDownloadUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      print('❌ Не удалось открыть ссылку: $url');
    }
  }

  // Полная проверка и установка (через открытие браузера)
  static Future<bool> checkAndUpdate() async {
    final update = await checkNewVersion();
    if (update != null) {
      await openDownloadUrl(update['download_url']!);
      return true;
    }
    return false;
  }
}