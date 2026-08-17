import 'package:github_release_apk_updater/github_release_apk_updater.dart';

class UpdateService {
  static const String owner = '666maxim666';
  static const String repo = 'fitness-app-updates';

  static Future<bool> checkAndUpdate() async {
    try {
      final updater = GithubReleaseApkUpdater();
      final apiService = GithubApiService();

      final release = await apiService.getLatestGithubAPKRelease(
        ownerGithub: owner,
        repositoryGithub: repo,
        apkKeyName: '', // если в релизе один APK
      );

      if (release == null) return false;

      final currentVersion = await updater.getCurrentAppVersion();
      final isNewer = VersionComparator().isNewerVersion(
        release.version,
        currentVersion,
      );

      if (isNewer) {
        final filePath = await updater.downloadAPK(
          release.apkUrl,
          null,
          (received, total) {
            print('Загрузка: $received / $total');
          },
        );
        if (filePath != null) {
          await updater.installApk(filePath);
          return true;
        }
      }
      return false;
    } catch (e) {
      print('Ошибка обновления: $e');
      return false;
    }
  }

  // Проверка без установки (для колокольчика)
  static Future<Map<String, String>?> checkNewVersion() async {
    try {
      final apiService = GithubApiService();
      final release = await apiService.getLatestGithubAPKRelease(
        ownerGithub: owner,
        repositoryGithub: repo,
        apkKeyName: '',
      );
      if (release == null) return null;
      final currentVersion = await GithubReleaseApkUpdater().getCurrentAppVersion();
      final isNewer = VersionComparator().isNewerVersion(release.version, currentVersion);
      if (isNewer) {
        return {
          'version': release.version,
          'download_url': release.apkUrl,
          'whats_new': release.body ?? 'Обновление доступно',
        };
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}