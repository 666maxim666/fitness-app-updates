import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui';
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
import '../widgets/calendar_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  AppUser? user;
  List<Workout> workouts = [];
  List<Map<String, dynamic>> notifications = [];
  Map<String, dynamic> config = {};
  bool isConfigLoaded = false;
  bool isUserLoaded = false;
  bool allRead = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadConfig();
    _loadUser();
    _loadReadState();
  }

  Future<void> _loadConfig() async {
    final cfg = await ConfigService.loadAll();
    setState(() {
      config = cfg;
      isConfigLoaded = true;
    });
  }

  Future<void> _loadReadState() async {
    final prefs = await SharedPreferences.getInstance();
    allRead = prefs.getBool('notifications_all_read') ?? false;
    if (allRead) {
      setState(() {
        for (var n in notifications) {
          n['read'] = true;
        }
      });
    }
  }

  Future<void> _loadUser() async {
    final firebaseUser = AuthService.currentUser;
    if (firebaseUser != null) {
      await _setUser(firebaseUser);
    } else {
      _showLoginDialog();
    }
  }

  Future<void> _setUser(User firebaseUser) async {
    final loadedWorkouts = await GoogleSheetsService.loadWorkouts(firebaseUser.email!);
    final notifs = [
      {'title': '📢 Новая версия 1.1.0', 'body': 'Добавлен график прогресса и исправлены ошибки', 'time': 'Сегодня, 14:30', 'type': 'update', 'read': false},
      {'title': '💧 Напоминание о воде', 'body': 'Не забудь выпить 300 мл воды перед тренировкой', 'time': 'Сегодня, 12:00', 'type': 'reminder', 'read': false},
      {'title': '🏆 Достижение: 50 тренировок', 'body': 'Ты выполнил 50 тренировок! Отличная работа!', 'time': 'Вчера, 20:15', 'type': 'achievement', 'read': false},
      {'title': '🚰 Пора пить воду', 'body': 'Ты давно не пил воду – время восполнить баланс', 'time': '2 часа назад', 'type': 'water', 'read': false},
    ];

    setState(() {
      user = AppUser(
        email: firebaseUser.email!,
        name: firebaseUser.displayName ?? 'Пользователь',
        weight: 75,
        trainingDays: [1, 3, 5],
        createdAt: DateTime.now(),
      );
      workouts = loadedWorkouts;
      notifications = notifs;
      isUserLoaded = true;
    });

    GoogleSheetsService.appendRow('Пользователи', [
      user!.email,
      user!.name,
      user!.weight,
      user!.trainingDays.join(','),
      user!.createdAt.toIso8601String(),
    ]);

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

  // ===== АВТОМАТИЧЕСКАЯ ПРОВЕРКА ПРИ ЗАПУСКЕ =====
  Future<void> _checkForUpdate() async {
    try {
      final updateInfo = await UpdateService.checkNewVersion();
      if (updateInfo != null) {
        setState(() {
          notifications.add({
            'title': '📢 Новая версия ${updateInfo['version']}',
            'body': updateInfo['whats_new'] ?? 'Обновление доступно',
            'time': 'Только что',
            'type': 'update',
            'read': false,
          });
        });
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('notifications_all_read', false);
        setState(() { allRead = false; });
      }
    } catch (e) {
      print('Ошибка проверки обновлений: $e');
    }
  }

  // ===== РУЧНАЯ ПРОВЕРКА (ВЫЗЫВАЕТСЯ ИЗ КОЛОКОЛЬЧИКА) =====
  Future<void> _checkForUpdateManually() async {
    final updateInfo = await UpdateService.checkNewVersion();
    if (updateInfo != null) {
      setState(() {
        notifications.add({
          'title': '📢 Новая версия ${updateInfo['version']}',
          'body': updateInfo['whats_new'] ?? 'Обновление доступно',
          'time': 'Только что',
          'type': 'update',
          'read': false,
        });
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notifications_all_read', false);
      setState(() { allRead = false; });
      // Показываем SnackBar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🔄 Обновление найдено: ${updateInfo['version']}'),
          action: SnackBarAction(
            label: 'Скачать',
            onPressed: () {
              // Можно открыть ссылку на APK
            },
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ У вас последняя версия')),
      );
    }
  }

  // ===== МЕТОДЫ ДЛЯ РАБОТЫ С ТРЕНИРОВКАМИ =====
  void _addWorkout(Workout w) {
    setState(() {
      workouts.add(w);
    });
    GoogleSheetsService.appendRow('Тренировки', [
      user!.email,
      w.date,
      w.exercise,
      w.sets,
      w.reps,
      w.weight?.toString() ?? '',
      w.isProhodka ? 'true' : 'false',
      w.weekNumber,
    ]);
  }

  void _updateWorkout(Workout updated) {
    final index = workouts.indexWhere((w) => w.id == updated.id);
    if (index != -1) {
      setState(() {
        workouts[index] = updated;
      });
      GoogleSheetsService.appendRow('Тренировки', [
        user!.email,
        updated.date,
        updated.exercise,
        updated.sets,
        updated.reps,
        updated.weight?.toString() ?? '',
        updated.isProhodka ? 'true' : 'false',
        updated.weekNumber,
      ]);
    }
  }

  void _deleteWorkout(String id) {
    setState(() {
      workouts.removeWhere((w) => w.id == id);
    });
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

  // ===== КНОПКА КАЛЕНДАРЯ =====
  void _showCalendarDialog() {
    showDialog(
      context: context,
      builder: (ctx) => CalendarDialog(
        initialDate: DateTime.now(),
        onDateSelected: (date) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Выбран день: ${date.toLocal().toString().split(' ')[0]}')),
          );
        },
      ),
    );
  }

  // ===== ДИАЛОГ УВЕДОМЛЕНИЙ С КНОПКОЙ ОБНОВЛЕНИЯ =====
  void _showNotificationsDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      useSafeArea: true,
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return child;
      },
      builder: (ctx) {
        // Используем StatefulBuilder, чтобы обновлять содержимое диалога
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final unreadCount = notifications.where((n) => n['read'] == false).length;
            return Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              insetPadding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 400),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A120A).withOpacity(0.88),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: const Color(0xFFFF9800).withOpacity(0.15)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.6),
                      blurRadius: 24,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(32),
                  child: BackdropFilter(
                    filter: const ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Шапка с кнопкой обновления
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    '🔔 Уведомления',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: unreadCount > 0 ? const Color(0xFFFF9800) : const Color(0xFF333333),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      '$unreadCount новых',
                                      style: TextStyle(
                                        color: unreadCount > 0 ? Colors.black : Colors.grey[600],
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  // КНОПКА ОБНОВЛЕНИЯ (круглая стрелка)
                                  IconButton(
                                    icon: const Icon(Icons.refresh, color: Color(0xFFFF9800), size: 24),
                                    onPressed: () async {
                                      // Вызываем ручную проверку и обновляем диалог
                                      await _checkForUpdateManually();
                                      setStateDialog(() {});
                                    },
                                    splashRadius: 20,
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close, color: Color(0xFF888888), size: 26),
                                    onPressed: () => Navigator.pop(context),
                                    splashRadius: 20,
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Список уведомлений
                          if (notifications.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 40),
                              child: Column(
                                children: [
                                  Icon(Icons.notifications_off, size: 48, color: Colors.grey),
                                  SizedBox(height: 12),
                                  Text('Нет уведомлений', style: TextStyle(color: Colors.grey)),
                                ],
                              ),
                            )
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: notifications.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final n = notifications[index];
                                final isRead = n['read'] == true;
                                final type = n['type'] ?? 'update';
                                Color borderColor;
                                String icon;
                                switch (type) {
                                  case 'reminder':
                                    borderColor = const Color(0xFF00BCD4);
                                    icon = '💧';
                                    break;
                                  case 'achievement':
                                    borderColor = const Color(0xFF4CAF50);
                                    icon = '🏆';
                                    break;
                                  case 'water':
                                    borderColor = const Color(0xFF2196F3);
                                    icon = '🚰';
                                    break;
                                  default:
                                    borderColor = const Color(0xFFFF9800);
                                    icon = '📢';
                                }
                                return GestureDetector(
                                  onTap: () {
                                    showDialog(
                                      context: context,
                                      builder: (_) => AlertDialog(
                                        title: Text(n['title'] ?? ''),
                                        content: Text(n['body'] ?? ''),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(_),
                                            child: const Text('Закрыть'),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    decoration: BoxDecoration(
                                      color: isRead
                                          ? Colors.white.withOpacity(0.03)
                                          : Colors.white.withOpacity(0.06),
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border(
                                        left: BorderSide(color: borderColor, width: 5),
                                      ),
                                    ),
                                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.06),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Center(
                                            child: Text(icon, style: const TextStyle(fontSize: 24)),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                n['title'] ?? '',
                                                style: TextStyle(
                                                  color: isRead ? Colors.grey[600] : Colors.white,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                n['body'] ?? '',
                                                style: TextStyle(
                                                  color: isRead ? Colors.grey[600] : Colors.grey[400],
                                                  fontSize: 14,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                n['time'] ?? '',
                                                style: TextStyle(
                                                  color: isRead ? Colors.grey[700] : Colors.grey[600],
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          if (notifications.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(
                                    onPressed: unreadCount == 0 ? null : () async {
                                      setState(() {
                                        for (var n in notifications) {
                                          n['read'] = true;
                                        }
                                      });
                                      final prefs = await SharedPreferences.getInstance();
                                      await prefs.setBool('notifications_all_read', true);
                                      setState(() { allRead = true; });
                                      setStateDialog(() {});
                                    },
                                    style: TextButton.styleFrom(
                                      foregroundColor: unreadCount == 0 ? Colors.grey[600] : const Color(0xFFFF9800),
                                    ),
                                    child: Text(
                                      unreadCount == 0 ? '✔ Всё прочитано' : '✔ Отметить всё прочитанным',
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!isConfigLoaded || !isUserLoaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final appTitle = ConfigService.getValue<String>(config, 'texts.appTitle', '🏋️ Тренировки');
    final unreadCount = notifications.where((n) => n['read'] == false).length;

    return Scaffold(
      appBar: GlassAppBar(
        title: appTitle,
        notificationCount: unreadCount,
        onNotificationTap: _showNotificationsDialog,
        onCalendarTap: _showCalendarDialog,
        config: config,
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          PlanTab(
            workouts: workouts,
            onAddWorkout: _addWorkout,
            onUpdateWorkout: _updateWorkout,
            onDeleteWorkout: _deleteWorkout,
            config: config,
          ),
          ProgressTab(workouts: workouts, config: config),
          ProfileTab(user: user, onUpdate: _updateUser, config: config, workouts: workouts),
        ],
      ),
      bottomNavigationBar: GlassBottomNav(controller: _tabController, config: config),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}