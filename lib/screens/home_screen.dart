import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'dart:convert';
import 'dart:ui';
import '../services/google_sheets_service.dart';
import '../services/auth_service.dart';
import '../services/update_service.dart';
import '../services/notification_service.dart';
import '../services/location_service.dart';
import '../models/user.dart';
import '../models/workout.dart';
import 'plan_tab.dart';
import 'progress_tab.dart';
import 'profile_tab.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/glass_app_bar.dart';
import '../widgets/calendar_dialog.dart';
import '../widgets/ai_chat_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  AppUser? user;
  List<Workout> workouts = [];
  List<Map<String, dynamic>> notifications = [];
  Map<String, dynamic> config = {};
  bool isConfigLoaded = false;
  bool isUserLoaded = false;
  bool allRead = false;

  DateTime _selectedDate = DateTime.now();
  int _planTabRefreshKey = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadConfig();
    _loadReadState();
    _loadNotifications();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUser();
    });
    NotificationService.init();
    NotificationService.onNotificationReceived = (data) {
      setState(() {
        notifications.add({
          'title': data['title'],
          'body': data['body'],
          'time': data['time'],
          'type': data['type'],
          'read': data['read'],
          'download_url': data['download_url'],
        });
      });
      _saveNotifications();
      SharedPreferences.getInstance().then((prefs) {
        prefs.setBool('notifications_all_read', false);
      });
      setState(() {
        allRead = false;
      });
    };
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    setState(() {
      config = {};
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

  Future<void> _loadNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('notifications_cache');
    if (data != null) {
      try {
        final List<dynamic> decoded = jsonDecode(data);
        setState(() {
          notifications = decoded.cast<Map<String, dynamic>>().toList();
        });
      } catch (e) {
        print('Ошибка загрузки уведомлений: $e');
      }
    }
  }

  Future<void> _saveNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notifications_cache', jsonEncode(notifications));
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
    List<Workout> loadedWorkouts = [];
    double? userHeight;
    String? userGender;
    int? userPushupGoal;
    int userWeight = 75;
    List<int> userTrainingDays = [1, 3, 5];
    String? userTimezone;

    try {
      userTimezone = await FlutterTimezone.getLocalTimezone();
    } catch (e) {
      userTimezone = 'Europe/Moscow';
    }

    try {
      loadedWorkouts = await GoogleSheetsService.loadWorkouts(
              firebaseUser.email!)
          .timeout(const Duration(seconds: 10));

      final rows = await GoogleSheetsService.getRows('Пользователи');
      for (var row in rows) {
        if (row.length > 0 && row[0].toString() == firebaseUser.email) {
          if (row.length > 2) {
            final weightStr = row[2]?.toString();
            if (weightStr != null && weightStr.isNotEmpty) {
              userWeight = int.tryParse(weightStr) ?? 75;
            }
          }
          if (row.length > 3) {
            final heightStr = row[3]?.toString();
            if (heightStr != null && heightStr.isNotEmpty) {
              userHeight = double.tryParse(heightStr) ?? 180.0;
            }
          }
          if (row.length > 4) {
            final daysStr = row[4]?.toString();
            if (daysStr != null && daysStr.isNotEmpty) {
              final parsed = daysStr
                  .split(',')
                  .map((s) => int.tryParse(s.trim()))
                  .where((n) => n != null)
                  .cast<int>()
                  .toList();
              if (parsed.isNotEmpty) {
                userTrainingDays = parsed;
              }
            }
          }
          if (row.length > 5) {
            final genderStr = row[5]?.toString();
            if (genderStr != null && genderStr.isNotEmpty) {
              userGender = genderStr;
            }
          }
          if (row.length > 6) {
            final goalStr = row[6]?.toString();
            if (goalStr != null && goalStr.isNotEmpty) {
              userPushupGoal = int.tryParse(goalStr) ?? 100;
            }
          }
          if (row.length > 7) {
            final tzStr = row[7]?.toString();
            if (tzStr != null && tzStr.isNotEmpty) {
              userTimezone = tzStr;
            }
          }
        }
      }
    } catch (e) {
      print('Ошибка загрузки данных: $e');
    }

    userHeight ??= 180.0;
    userGender ??= 'male';
    userPushupGoal ??= 100;

    setState(() {
      user = AppUser(
        email: firebaseUser.email!,
        name: firebaseUser.displayName ?? 'Пользователь',
        weight: userWeight,
        height: userHeight,
        gender: userGender,
        pushupGoal: userPushupGoal,
        timezone: userTimezone,
        trainingDays: userTrainingDays,
        createdAt: DateTime.now(),
      );
      workouts = loadedWorkouts;
      isUserLoaded = true;
    });

    GoogleSheetsService.appendRow('Пользователи', [
      user!.email,
      user!.name,
      user!.weight,
      user!.height ?? 0,
      user!.trainingDays.join(','),
      user!.gender ?? 'male',
      user!.pushupGoal ?? 100,
      user!.timezone ?? 'Europe/Moscow',
      user!.createdAt.toIso8601String(),
    ]);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('profile_weight', user!.weight);
    await prefs.setString('profile_gender', user!.gender ?? 'male');
    await prefs.setString('profile_height', (user!.height ?? 180).toString());
    await prefs.setInt('profile_pushup_goal', user!.pushupGoal ?? 100);

    final token = await NotificationService.getFcmToken();
    if (token != null) {
      GoogleSheetsService.appendRow('Токены', [
        firebaseUser.email!,
        token,
      ]);
    }

    _checkForUpdate();

    Future.delayed(const Duration(seconds: 10), () {
      LocationService.logLocation(firebaseUser.email!);
    });
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
            'title': '📢 Новая версия ${updateInfo['version']}',
            'body': updateInfo['whats_new'] ?? 'Обновление доступно',
            'time': 'Только что',
            'type': 'update',
            'read': false,
            'download_url': updateInfo['download_url'] ?? '',
          });
        });
        _saveNotifications();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('notifications_all_read', false);
        setState(() {
          allRead = false;
        });
      }
    } catch (e) {
      print('Ошибка проверки обновлений: $e');
    }
  }

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
          'download_url': updateInfo['download_url'] ?? '',
        });
      });
      _saveNotifications();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notifications_all_read', false);
      setState(() {
        allRead = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🔔 Обновление найдено: ${updateInfo['version']}'),
          action: SnackBarAction(
            label: 'Скачать',
            onPressed: () =>
                UpdateService.openDownloadUrl(updateInfo['download_url']!),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ У вас последняя версия')),
      );
    }
  }

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
      newUser.height ?? 0,
      newUser.trainingDays.join(','),
      newUser.gender ?? 'male',
      newUser.pushupGoal ?? 100,
      newUser.timezone ?? 'Europe/Moscow',
      newUser.createdAt.toIso8601String(),
    ]);

    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt('profile_weight', newUser.weight);
      prefs.setString('profile_gender', newUser.gender ?? 'male');
      prefs.setString('profile_height', (newUser.height ?? 180).toString());
      prefs.setInt('profile_pushup_goal', newUser.pushupGoal ?? 100);
    });
  }

  void _showCalendarDialog() {
    showDialog(
      context: context,
      builder: (ctx) => CalendarDialog(
        initialDate: _selectedDate,
        onDateSelected: (date) {
          setState(() {
            _selectedDate = date;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    'Выбран день: ${date.toLocal().toString().split(' ')[0]}')),
          );
        },
      ),
    );
  }

  // ============================================================
  // ===== AI ЧАТ =====
  // ============================================================
  Future<void> _showAiChat() async {
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    final todayKey = _formatDate(DateTime.now());
    final waterToday = prefs.getInt('water_$todayKey') ?? 0;
    final creatineG = prefs.getInt('creatine_$todayKey') ?? 0;

    final restEndStr = prefs.getString('creatine_rest_end');
    DateTime? restEnd;
    if (restEndStr != null) restEnd = DateTime.tryParse(restEndStr);
    final onRest = restEnd != null && restEnd.isAfter(DateTime.now());
    final restDaysLeft =
        onRest ? restEnd.difference(DateTime.now()).inDays + 1 : 0;

    double base = (user!.weight * 0.03);
    if ((user!.gender ?? 'male') == 'male') base += 0.2;
    final waterGoal = (base * 1000).round();

    final pushupData = prefs.getString('pushup_data');
    int pushupTotal = 0;
    if (pushupData != null) {
      try {
        final decoded = jsonDecode(pushupData);
        final entries = decoded['entries'] as List?;
        if (entries != null) {
          pushupTotal = entries.fold<int>(
              0, (sum, e) => sum + ((e['count'] as int?) ?? 0));
        }
      } catch (_) {}
    }

    int attended = 0;
    final planDays = [1, 3, 5];
    for (int i = 0; i <= 30; i++) {
      final day = DateTime.now().subtract(Duration(days: i));
      if (planDays.contains(day.weekday)) {
        final key =
            '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
        if (workouts.any((w) => w.date == key)) attended++;
      }
    }
    final plannedTotal = (30 / 7 * 3).round();
    final attendancePercent =
        plannedTotal > 0 ? ((attended / plannedTotal) * 100).round() : 0;

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AiChatDialog(
        user: user!,
        waterToday: waterToday,
        waterGoal: waterGoal,
        creatineToday: creatineG > 0,
        onRest: onRest,
        restDaysLeft: restDaysLeft,
        pushupGoal: user!.pushupGoal ?? 100,
        pushupToday: pushupTotal,
        totalWorkouts: workouts.length,
        attendancePercent: attendancePercent,
        // ⬇⬇⬇ ВСЕ КОЛБЭКИ ⬇⬇⬇
        onAddWater: _aiAddWater,
        onRemoveWater: _aiRemoveWater,
        onSetWater: _aiSetWater,
        onMarkCreatine: _aiMarkCreatine,
        onUnmarkCreatine: _aiUnmarkCreatine,
        onStartRest: _aiStartRest,
        onAddPushups: _aiAddPushups,
        onRemovePushups: _aiRemovePushups,
        onSetPushups: _aiSetPushups,
      ),
    );
  }

  // ============ AI WATER ============
  Future<void> _aiAddWater(int ml) async {
    final prefs = await SharedPreferences.getInstance();
    final todayKey = _formatDate(DateTime.now());
    final current = prefs.getInt('water_$todayKey') ?? 0;
    final newVal = current + ml;
    await prefs.setInt('water_$todayKey', newVal);

    if (user?.email != null) {
      final creatine = prefs.getInt('creatine_$todayKey') ?? 0;
      GoogleSheetsService.saveWaterAndCreatine(
        email: user!.email,
        date: todayKey,
        waterMl: newVal,
        creatineG: creatine,
      );
    }

    setState(() => _planTabRefreshKey++);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('💧 AI добавил $ml мл воды'),
          backgroundColor: Colors.blue,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _aiRemoveWater(int ml) async {
    final prefs = await SharedPreferences.getInstance();
    final todayKey = _formatDate(DateTime.now());
    final current = prefs.getInt('water_$todayKey') ?? 0;
    final newVal = (current - ml).clamp(0, 999999);
    await prefs.setInt('water_$todayKey', newVal);

    if (user?.email != null) {
      final creatine = prefs.getInt('creatine_$todayKey') ?? 0;
      GoogleSheetsService.saveWaterAndCreatine(
        email: user!.email,
        date: todayKey,
        waterMl: newVal,
        creatineG: creatine,
      );
    }

    setState(() => _planTabRefreshKey++);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('💧 AI убрал $ml мл воды'),
          backgroundColor: Colors.blueGrey,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _aiSetWater(int ml) async {
    final prefs = await SharedPreferences.getInstance();
    final todayKey = _formatDate(DateTime.now());
    final newVal = ml.clamp(0, 999999);
    await prefs.setInt('water_$todayKey', newVal);

    if (user?.email != null) {
      final creatine = prefs.getInt('creatine_$todayKey') ?? 0;
      GoogleSheetsService.saveWaterAndCreatine(
        email: user!.email,
        date: todayKey,
        waterMl: newVal,
        creatineG: creatine,
      );
    }

    setState(() => _planTabRefreshKey++);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('💧 Вода установлена: $newVal мл'),
          backgroundColor: Colors.blue,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // ============ AI CREATINE ============
  Future<void> _aiMarkCreatine() async {
    final prefs = await SharedPreferences.getInstance();
    final todayKey = _formatDate(DateTime.now());
    await prefs.setInt('creatine_$todayKey', 5);

    if (user?.email != null) {
      final water = prefs.getInt('water_$todayKey') ?? 0;
      GoogleSheetsService.saveWaterAndCreatine(
        email: user!.email,
        date: todayKey,
        waterMl: water,
        creatineG: 5,
      );
    }

    setState(() => _planTabRefreshKey++);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('💊 AI отметил креатин (5 г)'),
          backgroundColor: Colors.purple,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _aiUnmarkCreatine() async {
    final prefs = await SharedPreferences.getInstance();
    final todayKey = _formatDate(DateTime.now());
    await prefs.setInt('creatine_$todayKey', 0);

    if (user?.email != null) {
      final water = prefs.getInt('water_$todayKey') ?? 0;
      GoogleSheetsService.saveWaterAndCreatine(
        email: user!.email,
        date: todayKey,
        waterMl: water,
        creatineG: 0,
      );
    }

    setState(() => _planTabRefreshKey++);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('💊 Отметка креатина снята'),
          backgroundColor: Colors.purple,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // ============ AI REST ============
  Future<void> _aiStartRest(int days) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now();
    final todayKey = _formatDate(today);
    final start = DateTime(today.year, today.month, today.day);
    final end = start.add(Duration(days: days));

    await prefs.setString('creatine_rest_start', start.toIso8601String());
    await prefs.setString('creatine_rest_end', end.toIso8601String());
    await prefs.setInt('creatine_$todayKey', 0);

    for (int i = 0; i <= days; i++) {
      final date = start.add(Duration(days: i));
      await prefs.setBool('creatine_rest_${_formatDate(date)}', true);
    }

    if (user?.email != null) {
      final water = prefs.getInt('water_$todayKey') ?? 0;
      GoogleSheetsService.saveWaterAndCreatine(
        email: user!.email,
        date: todayKey,
        waterMl: water,
        creatineG: 0,
      );
    }

    setState(() => _planTabRefreshKey++);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('😴 AI запустил отдых на $days дн.'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // ============ AI PUSHUPS ============
  Future<void> _aiAddPushups(int count) async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('pushup_data');
    List<Map<String, dynamic>> entries = [];
    if (data != null) {
      try {
        final decoded = jsonDecode(data);
        final list = decoded['entries'] as List?;
        if (list != null) {
          entries = list.cast<Map<String, dynamic>>().toList();
        }
      } catch (_) {}
    }
    entries.add({
      'id': DateTime.now().millisecondsSinceEpoch,
      'count': count,
    });
    await prefs.setString('pushup_data', jsonEncode({'entries': entries}));

    setState(() => _planTabRefreshKey++);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('💪 AI добавил $count отжиманий'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _aiRemovePushups(int count) async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('pushup_data');
    List<Map<String, dynamic>> entries = [];
    if (data != null) {
      try {
        final decoded = jsonDecode(data);
        final list = decoded['entries'] as List?;
        if (list != null) {
          entries = list.cast<Map<String, dynamic>>().toList();
        }
      } catch (_) {}
    }

    int remaining = count;
    while (remaining > 0 && entries.isNotEmpty) {
      final last = entries.last;
      final lastCount = (last['count'] as int?) ?? 0;
      if (lastCount <= remaining) {
        entries.removeLast();
        remaining -= lastCount;
      } else {
        last['count'] = lastCount - remaining;
        remaining = 0;
      }
    }

    await prefs.setString('pushup_data', jsonEncode({'entries': entries}));

    setState(() => _planTabRefreshKey++);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('💪 AI убрал $count отжиманий'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _aiSetPushups(int count) async {
    final prefs = await SharedPreferences.getInstance();
    final entries = <Map<String, dynamic>>[];
    if (count > 0) {
      entries.add({
        'id': DateTime.now().millisecondsSinceEpoch,
        'count': count,
      });
    }
    await prefs.setString('pushup_data', jsonEncode({'entries': entries}));

    setState(() => _planTabRefreshKey++);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('💪 Отжимания = $count'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  String _formatDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  void _showNotificationsDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      useSafeArea: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final unreadCount =
                notifications.where((n) => n['read'] == false).length;
            return Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              insetPadding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 400),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A120A).withOpacity(0.88),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                      color: const Color(0xFFFF9800).withOpacity(0.15)),
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
                    filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '🔔 Уведомления${unreadCount > 0 ? ' ($unreadCount)' : ''}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Row(
                                children: [
                                  if (unreadCount > 0)
                                    TextButton(
                                      onPressed: () {
                                        setState(() {
                                          for (var n in notifications) {
                                            n['read'] = true;
                                          }
                                          allRead = true;
                                        });
                                        _saveNotifications();
                                        SharedPreferences.getInstance()
                                            .then((prefs) {
                                          prefs.setBool(
                                              'notifications_all_read', true);
                                        });
                                        setStateDialog(() {});
                                      },
                                      child: const Text(
                                        'Все прочитаны',
                                        style: TextStyle(
                                            color: Colors.orange, fontSize: 14),
                                      ),
                                    ),
                                  IconButton(
                                    icon: const Icon(Icons.refresh,
                                        color: Colors.orange, size: 22),
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      _checkForUpdateManually();
                                    },
                                    tooltip: 'Проверить обновления',
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close,
                                        color: Colors.grey),
                                    onPressed: () => Navigator.pop(ctx),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (notifications.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 30),
                              child: Text(
                                'Нет уведомлений',
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          else
                            Flexible(
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: notifications.length,
                                itemBuilder: (ctx, index) {
                                  final n = notifications[index];
                                  final type = n['type'] ?? 'update';
                                  String icon;
                                  switch (type) {
                                    case 'reminder':
                                      icon = '💧';
                                      break;
                                    case 'achievement':
                                      icon = '🏆';
                                      break;
                                    case 'water':
                                      icon = '🚰';
                                      break;
                                    case 'prohodka':
                                      icon = '⚡';
                                      break;
                                    default:
                                      icon = '📢';
                                  }
                                  return GestureDetector(
                                    onTap: () {
                                      showDialog(
                                        context: context,
                                        builder: (ctx2) => AlertDialog(
                                          backgroundColor:
                                              const Color(0xFF1A120A),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(28),
                                          ),
                                          title: Text(
                                            n['title'] ?? '',
                                            style: const TextStyle(
                                                color: Colors.white),
                                          ),
                                          content: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                n['body'] ?? '',
                                                style: const TextStyle(
                                                    color: Colors.white70),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                n['time'] ?? '',
                                                style: const TextStyle(
                                                    color: Colors.grey,
                                                    fontSize: 12),
                                              ),
                                            ],
                                          ),
                                          actions: [
                                            if (n['download_url'] != null &&
                                                n['download_url'].isNotEmpty)
                                              TextButton(
                                                onPressed: () {
                                                  Navigator.pop(ctx2);
                                                  UpdateService.openDownloadUrl(
                                                      n['download_url']);
                                                },
                                                child: const Text(
                                                  'Скачать',
                                                  style: TextStyle(
                                                      color: Colors.orange),
                                                ),
                                              ),
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx2),
                                              child: const Text(
                                                'Закрыть',
                                                style: TextStyle(
                                                    color: Colors.grey),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (!(n['read'] ?? false)) {
                                        setState(() {
                                          n['read'] = true;
                                          allRead = notifications.every(
                                              (e) => e['read'] == true);
                                        });
                                        _saveNotifications();
                                        SharedPreferences.getInstance()
                                            .then((prefs) {
                                          prefs.setBool(
                                              'notifications_all_read', allRead);
                                        });
                                        setStateDialog(() {});
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      decoration: BoxDecoration(
                                        border: Border(
                                          bottom: BorderSide(
                                              color: Colors.white
                                                  .withOpacity(0.06)),
                                        ),
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (!(n['read'] ?? false))
                                            Container(
                                              margin: const EdgeInsets.only(
                                                  right: 10, top: 4),
                                              width: 8,
                                              height: 8,
                                              decoration: const BoxDecoration(
                                                color: Colors.orange,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          Container(
                                            margin: const EdgeInsets.only(
                                                right: 10),
                                            child: Text(icon,
                                                style: const TextStyle(
                                                    fontSize: 20)),
                                          ),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  n['title'] ?? '',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight:
                                                        FontWeight.w600,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  n['body'] ?? '',
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: Colors.grey,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  n['time'] ?? '',
                                                  style: const TextStyle(
                                                    color: Colors.grey,
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
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      appBar: GlassAppBar(
        title: 'Gym Journal',
        onNotificationTap: _showNotificationsDialog,
        onCalendarTap: _showCalendarDialog,
        onAiTap: _showAiChat,
        notificationCount:
            notifications.where((n) => n['read'] == false).length,
        config: config,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.2,
            colors: [
              Color(0xFF1A120A),
              Color(0xFF0A0A0A),
            ],
          ),
        ),
        child: isUserLoaded
            ? TabBarView(
                controller: _tabController,
                children: [
                  PlanTab(
                    key: ValueKey('plan_$_planTabRefreshKey'),
                    workouts: workouts,
                    onAddWorkout: _addWorkout,
                    onUpdateWorkout: _updateWorkout,
                    onDeleteWorkout: _deleteWorkout,
                    config: config,
                    trainingDays: user?.trainingDays ?? [1, 3, 5],
                    selectedDate: _selectedDate,
                    userEmail: user?.email,
                    userWeight: user?.weight,
                    userGender: user?.gender,
                  ),
                  ProgressTab(
                    workouts: workouts,
                    config: config,
                    user: user,
                  ),
                  ProfileTab(
                    user: user!,
                    onUpdate: _updateUser,
                    config: config,
                  ),
                ],
              )
            : const Center(
                child: CircularProgressIndicator(
                  color: Colors.orange,
                ),
              ),
      ),
      bottomNavigationBar: GlassBottomNav(
        controller: _tabController,
        config: config,
      ),
    );
  }
}