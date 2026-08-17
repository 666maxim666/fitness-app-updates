import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/google_sheets_service.dart';
import '../services/config_service.dart';
import '../services/auth_service.dart';
import '../services/update_service.dart';
import '../models/user.dart';
import '../models/workout.dart';
import 'plan_tab.dart';
import 'progress_tab.dart';
import 'profile_tab.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/glass_app_bar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  AppUser? user;
  List<Workout> workouts = [];
  List<Map<String, String>> notifications = [];
  Map<String, dynamic> config = {};
  bool isConfigLoaded = false;
  bool isUserLoaded = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadConfig();
    _loadUser();
  }

  Future<void> _loadConfig() async {
    final cfg = await ConfigService.loadAll();
    setState(() {
      config = cfg;
      isConfigLoaded = true;
    });
  }

  Future<void> _loadUser() async {
    final firebaseUser = AuthService.currentUser;
    if (firebaseUser != null) {
      // Пользователь уже вошёл
      await _setUser(firebaseUser);
    } else {
      // Показать диалог входа
      _showLoginDialog();
    }
  }

  Future<void> _setUser(User firebaseUser) async {
    final loadedWorkouts = await GoogleSheetsService.loadWorkouts(firebaseUser.email!);
    setState(() {
      user = AppUser(
        email: firebaseUser.email!,
        name: firebaseUser.displayName ?? 'Пользователь',
        weight: 75,
        trainingDays: [1, 3, 5],
        createdAt: DateTime.now(),
      );
      workouts = loadedWorkouts;
      isUserLoaded = true;
    });
    // Сохраняем пользователя в таблицу (если его ещё нет)
    GoogleSheetsService.appendRow('Пользователи', [
      user!.email,
      user!.name,
      user!.weight,
      user!.trainingDays.join(','),
      user!.createdAt.toIso8601String(),
    ]);
    // Проверка обновлений после входа
    _checkForUpdate();
  }

  void _showLoginDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Вход'),
        content: const Text('Войдите через Google, чтобы продолжить'),
        actions: [
          ElevatedButton(
            onPressed: () async {
              final firebaseUser = await AuthService.signInWithGoogle();
              if (firebaseUser != null) {
                Navigator.pop(ctx);
                await _setUser(firebaseUser);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Ошибка входа')),
                );
              }
            },
            child: const Text('Войти через Google'),
          ),
        ],
      ),
    );
  }

  Future<void> _checkForUpdate() async {
    try {
      final updateInfo = await UpdateService.checkNewVersion();
      if (updateInfo != null) {
        setState(() {
          notifications.add({
            'title': 'Новая версия ${updateInfo['version']}',
            'body': updateInfo['whats_new'] ?? 'Обновление доступно',
            'download_url': updateInfo['download_url'] ?? '',
          });
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('📢 Доступно обновление ${updateInfo['version']}'),
              action: SnackBarAction(
                label: 'Обновить',
                onPressed: () => UpdateService.checkAndUpdate(),
              ),
            ),
          );
        }
      }
    } catch (e) {
      print('Ошибка проверки обновлений: $e');
    }
  }

  void _addWorkout(Workout w) {
    setState(() {
      workouts.add(w);
    });
    GoogleSheetsService.appendRow('Тренировки', [
      user!.email,
      w.date.toIso8601String(),
      w.exercise,
      w.sets,
      w.reps,
      w.weight.toString(),
      w.isProhodka ? 'true' : 'false',
      w.weekNumber,
    ]);
  }

  void _updateUser(AppUser newUser) {
    setState(() {
      user = newUser;
    });
    GoogleSheetsService.appendRow('Пользователи', [
      newUser.email,
      newUser.name,
      newUser.weight,
      newUser.trainingDays.join(','),
      newUser.createdAt.toIso8601String(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (!isConfigLoaded || !isUserLoaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final appTitle = ConfigService.getValue<String>(config, 'texts.appTitle', '🏋️ Тренировки');
    return Scaffold(
      appBar: GlassAppBar(
        title: appTitle,
        notificationCount: notifications.length,
        onNotificationTap: _showNotificationsDialog,
        config: config,
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          PlanTab(
            workouts: workouts,
            onAddWorkout: _addWorkout,
            config: config,
          ),
          ProgressTab(workouts: workouts, config: config),
          ProfileTab(user: user, onUpdate: _updateUser, config: config),
        ],
      ),
      bottomNavigationBar: GlassBottomNav(controller: _tabController, config: config),
    );
  }

  void _showNotificationsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Уведомления'),
        content: notifications.isEmpty
            ? const Text('Нет новых уведомлений')
            : SizedBox(
                width: 300,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: notifications.length,
                  itemBuilder: (_, i) {
                    final n = notifications[i];
                    return ListTile(
                      title: Text(n['title'] ?? ''),
                      subtitle: Text(n['body'] ?? ''),
                      trailing: n['download_url'] != null && n['download_url']!.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.download),
                              onPressed: () {
                                // открыть ссылку
                              },
                            )
                          : null,
                    );
                  },
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}