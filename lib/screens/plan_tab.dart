import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/workout.dart';
import '../services/google_sheets_service.dart';

class PlanTab extends StatefulWidget {
  final List<Workout> workouts;
  final Function(Workout) onAddWorkout;
  final Function(Workout) onUpdateWorkout;
  final Function(String) onDeleteWorkout;
  final Map<String, dynamic> config;
  final List<int> trainingDays;
  final DateTime selectedDate;
  final String? userEmail;
  final int? userWeight;
  final String? userGender;

  const PlanTab({
    super.key,
    required this.workouts,
    required this.onAddWorkout,
    required this.onUpdateWorkout,
    required this.onDeleteWorkout,
    this.config = const {},
    this.trainingDays = const [1, 3, 5],
    required this.selectedDate,
    this.userEmail,
    this.userWeight,
    this.userGender,
  });

  @override
  State<PlanTab> createState() => _PlanTabState();
}

class _PlanTabState extends State<PlanTab> with SingleTickerProviderStateMixin {
  late DateTime _currentDate;
  late DateTime _today;
  int _weekOffset = 0;
  int _prohodkaShiftWeeks = 0;

  Map<String, List<Map<String, dynamic>>> _templates = {};
  List<String> _exerciseBase = [];
  Set<String> _restDays = {};

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  DateTime _calendarModalMonth = DateTime.now();
  List<Map<String, dynamic>> _notifications = [];

  final TextEditingController _exNameController = TextEditingController();
  final TextEditingController _exSetsController = TextEditingController();
  final TextEditingController _exRepsController = TextEditingController();
  final TextEditingController _exWeightController = TextEditingController();
  String? _editingWorkoutId;

  // ===== ВОДА И КРЕАТИН =====
  int _waterMl = 0;
  int _creatineG = 0;
  DateTime? _restStart;
  DateTime? _restEnd;
  bool _waterBlockHidden = false;
  int _waterGoal = 2400;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _today = DateTime.now();
    _currentDate = widget.selectedDate;
    _loadLocalData();
    _loadRestDays();
    _loadProhodkaShift();
    _loadNotifications();
    _loadWaterData();
    _recalculateWaterGoal();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(PlanTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedDate != oldWidget.selectedDate) {
      setState(() => _currentDate = widget.selectedDate);
    }
    if (widget.userWeight != oldWidget.userWeight ||
        widget.userGender != oldWidget.userGender) {
      _recalculateWaterGoal();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _exNameController.dispose();
    _exSetsController.dispose();
    _exRepsController.dispose();
    _exWeightController.dispose();
    super.dispose();
  }

  // ===== ПЕРЕСЧЁТ ЦЕЛИ ВОДЫ =====
  void _recalculateWaterGoal() {
    final weight = widget.userWeight;
    final gender = widget.userGender;
    if (weight != null && gender != null) {
      double base = weight * 0.03;
      if (gender == 'male') base += 0.2;
      setState(() => _waterGoal = (base * 1000).round());
    } else {
      SharedPreferences.getInstance().then((prefs) {
        final w = prefs.getInt('profile_weight') ?? 75;
        final g = prefs.getString('profile_gender') ?? 'male';
        double base = w * 0.03;
        if (g == 'male') base += 0.2;
        if (mounted) {
          setState(() => _waterGoal = (base * 1000).round());
        }
      });
    }
  }

  // ===== ДАТЫ =====
  DateTime _getMonday(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final day = d.weekday;
    final diff = d.day - day + (day == 7 ? -6 : 1);
    return DateTime(d.year, d.month, diff);
  }

  bool _isSameDay(DateTime d1, DateTime d2) =>
      d1.year == d2.year && d1.month == d2.month && d1.day == d2.day;

  String _formatDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  int _getWeekNumber(DateTime date) {
    final start = DateTime(date.year, 1, 1);
    final diff = date.difference(start).inDays;
    return ((diff + start.weekday - 1) / 7).floor() + 1;
  }

  List<Workout> _getWorkoutsForDate(DateTime date) {
    final ds = _formatDate(date);
    return widget.workouts.where((w) => w.date == ds).toList();
  }

  bool _isRestDay(DateTime date) => _restDays.contains(_formatDate(date));

  // ===== ЗАГРУЗКА =====
  Future<void> _loadLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    final t = prefs.getString('gym_templates');
    if (t != null) {
      _templates =
          Map<String, List<Map<String, dynamic>>>.from(jsonDecode(t));
    }
    final b = prefs.getString('gym_exercise_base');
    if (b != null) _exerciseBase = List<String>.from(jsonDecode(b));
    setState(() {});
  }

  Future<void> _saveLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gym_templates', jsonEncode(_templates));
    await prefs.setString('gym_exercise_base', jsonEncode(_exerciseBase));
  }

  Future<void> _loadRestDays() async {
    final prefs = await SharedPreferences.getInstance();
    final r = prefs.getString('rest_days');
    if (r != null) _restDays = Set<String>.from(jsonDecode(r));
  }

  Future<void> _saveRestDays() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('rest_days', jsonEncode(_restDays.toList()));
  }

  Future<void> _loadProhodkaShift() async {
    final prefs = await SharedPreferences.getInstance();
    _prohodkaShiftWeeks = prefs.getInt('prohodka_shift_weeks') ?? 0;
  }

  Future<void> _saveProhodkaShift() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('prohodka_shift_weeks', _prohodkaShiftWeeks);
  }

  Future<void> _loadNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('notifications_cache');
    if (data != null) {
      try {
        final List<dynamic> decoded = jsonDecode(data);
        setState(() => _notifications =
            decoded.cast<Map<String, dynamic>>().toList());
      } catch (e) {
        print('Ошибка загрузки уведомлений: $e');
      }
    }
  }

  // ===== ВОДА: ЗАГРУЗКА =====
  Future<void> _loadWaterData() async {
    final prefs = await SharedPreferences.getInstance();
    final todayKey = _formatDate(_today);

    _waterMl = prefs.getInt('water_$todayKey') ?? 0;
    _creatineG = prefs.getInt('creatine_$todayKey') ?? 0;
    _waterBlockHidden = prefs.getBool('water_block_hidden') ?? false;

    final rs = prefs.getString('creatine_rest_start');
    final re = prefs.getString('creatine_rest_end');
    if (rs != null) _restStart = DateTime.tryParse(rs);
    if (re != null) _restEnd = DateTime.tryParse(re);

    setState(() {});
  }

  Future<void> _saveWaterLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final todayKey = _formatDate(_today);
    await prefs.setInt('water_$todayKey', _waterMl);
    await prefs.setInt('creatine_$todayKey', _creatineG);
    await prefs.setBool('water_block_hidden', _waterBlockHidden);
    if (_restStart != null) {
      await prefs.setString(
          'creatine_rest_start', _restStart!.toIso8601String());
    }
    if (_restEnd != null) {
      await prefs.setString('creatine_rest_end', _restEnd!.toIso8601String());
    }
  }

  Future<void> _syncWaterToSheet() async {
    if (widget.userEmail == null) {
      print('⚠️ userEmail не задан — синхронизация воды пропущена. '
          'Данные сохранены только локально.');
      return;
    }
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      final todayKey = _formatDate(_today);
      await GoogleSheetsService.saveWaterAndCreatine(
        email: widget.userEmail!,
        date: todayKey,
        waterMl: _waterMl,
        creatineG: _creatineG,
      );
    } catch (e) {
      print('Ошибка синхронизации воды: $e');
    } finally {
      _isSyncing = false;
    }
  }

  // ===== ОТДЫХ =====
  bool _isInRest(DateTime date) {
    if (_restStart == null || _restEnd == null) return false;
    final d = DateTime(date.year, date.month, date.day);
    final s = DateTime(_restStart!.year, _restStart!.month, _restStart!.day);
    final e = DateTime(_restEnd!.year, _restEnd!.month, _restEnd!.day);
    return !d.isBefore(s) && !d.isAfter(e);
  }

  int _restDaysLeft() {
    if (_restEnd == null) return 0;
    final e = DateTime(_restEnd!.year, _restEnd!.month, _restEnd!.day);
    final diff = e
        .difference(DateTime(_today.year, _today.month, _today.day))
        .inDays;
    return diff > 0 ? diff : 0;
  }

  /// Старт отдыха от креатина.
  /// Ставит флаг `creatine_rest_YYYY-MM-DD = true` на каждый день периода,
  /// чтобы `ProgressTab` мог точно посчитать все периоды отдыха (в прошлом тоже).
  Future<void> _startRest(int days) async {
    final start = DateTime(_today.year, _today.month, _today.day);
    final end = start.add(Duration(days: days));
    final prefs = await SharedPreferences.getInstance();

    // Ставим флаги на все дни периода (start..end включительно)
    for (int i = 0; i <= days; i++) {
      final date = start.add(Duration(days: i));
      final key = 'creatine_rest_${_formatDate(date)}';
      await prefs.setBool(key, true);
    }

    setState(() {
      _restStart = start;
      _restEnd = end;
      _creatineG = 0;
    });
    await _saveWaterLocal();
    await _syncWaterToSheet();
    _showToast('😴 Отдых $days дн. начат');
  }

  /// Прекращение отдыха.
  /// Снимает флаги **только** с сегодняшнего и будущих дней.
  /// Прошлые дни (которые уже были отдыхом) остаются помеченными —
  /// они остаются в статистике ProgressTab.
  Future<void> _stopRest() async {
    final prefs = await SharedPreferences.getInstance();
    final todayKey = _formatDate(_today);

    // Снимаем флаги с сегодня и будущего
    if (_restStart != null && _restEnd != null) {
      final start = DateTime(_restStart!.year, _restStart!.month, _restStart!.day);
      final end = DateTime(_restEnd!.year, _restEnd!.month, _restEnd!.day);
      final today = DateTime(_today.year, _today.month, _today.day);

      // Проходим по всем дням периода
      var current = start;
      while (!current.isAfter(end)) {
        // Снимаем флаг только если день сегодня или в будущем
        if (!current.isBefore(today)) {
          final key = 'creatine_rest_${_formatDate(current)}';
          await prefs.remove(key);
        }
        current = current.add(const Duration(days: 1));
      }
    }

    // Убираем сам факт отдыха
    await prefs.remove('creatine_rest_start');
    await prefs.remove('creatine_rest_end');

    setState(() {
      _restStart = null;
      _restEnd = null;
    });
    _showToast('✅ Отдых прекращён');
  }

  // ===== АВТОДУБЛИРОВАНИЕ =====
  void _applyTemplates(DateTime date) {
    if (_isRestDay(date)) return;
    final dayKey = 'day_${date.weekday}';
    if (!_templates.containsKey(dayKey)) return;
    final existing = _getWorkoutsForDate(date);
    final weekNum = _getWeekNumber(date);
    final adjustedWeek = weekNum - _prohodkaShiftWeeks;
    final isProhodka = adjustedWeek > 0 && adjustedWeek % 3 == 0;

    for (final t in _templates[dayKey]!) {
      final exists = existing.any((w) =>
          w.exercise == t['exercise'] &&
          w.sets == t['sets'] &&
          w.reps == t['reps'] &&
          (w.weight == t['weight'] || (w.isProhodka && isProhodka)));
      if (!exists) {
        final weightVal = isProhodka ? null : (t['weight'] as num?)?.toDouble();
        widget.onAddWorkout(Workout(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          date: _formatDate(date),
          exercise: t['exercise'],
          sets: t['sets'],
          reps: t['reps'],
          weight: weightVal,
          isProhodka: isProhodka,
          weekNumber: weekNum,
        ));
      }
    }
  }

  void _recalculateFutureProhodka() {
    final now = DateTime.now();
    for (final w in List<Workout>.from(widget.workouts)) {
      final date = DateTime.tryParse(w.date);
      if (date == null || !date.isAfter(now)) continue;
      final templates = _templates['day_${date.weekday}'];
      if (templates == null) continue;
      final mt = templates.firstWhere(
        (t) =>
            t['exercise'] == w.exercise &&
            t['sets'] == w.sets &&
            t['reps'] == w.reps,
        orElse: () => {},
      );
      if (mt.isEmpty) continue;
      final weekNum = _getWeekNumber(date);
      final adjustedWeek = weekNum - _prohodkaShiftWeeks;
      final newIsProhodka = adjustedWeek > 0 && adjustedWeek % 3 == 0;
      if (newIsProhodka != w.isProhodka) {
        widget.onUpdateWorkout(Workout(
          id: w.id,
          date: w.date,
          exercise: w.exercise,
          sets: w.sets,
          reps: w.reps,
          weight:
              newIsProhodka ? null : (mt['weight'] as num?)?.toDouble(),
          isProhodka: newIsProhodka,
          weekNumber: weekNum,
        ));
      }
    }
  }

  void _toggleRestDay(DateTime date) {
    final dateStr = _formatDate(date);
    setState(() {
      if (_restDays.contains(dateStr)) {
        _restDays.remove(dateStr);
      } else {
        _restDays.add(dateStr);
      }
    });
    _saveRestDays();
  }

  // ===== TOAST =====
  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.orange,
      duration: const Duration(milliseconds: 1500),
    ));
  }

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          _buildWeekRow(),
          const SizedBox(height: 16),
          _buildWorkoutList(),
          const SizedBox(height: 12),
          _buildAddButton(),
          const SizedBox(height: 12),
          _buildWaterCreatineBlock(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Colors.orange, Colors.orangeAccent],
          ).createShader(bounds),
          child: const Text(
            '📅 План',
            style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: Colors.white),
          ),
        ),
        Row(children: [
          IconButton(
            icon: const Icon(Icons.notifications,
                color: Colors.orange, size: 24),
            onPressed: _showNotificationsModal,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.calendar_month,
                color: Colors.orange, size: 24),
            onPressed: _showCalendarModal,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ]),
      ],
    );
  }

  Widget _buildWeekRow() {
    final primaryColor = '#FF9800';
    final baseMonday =
        _getMonday(_today).add(Duration(days: _weekOffset * 7));
    final children = <Widget>[];
    for (int i = 0; i < 7; i++) {
      final date = baseMonday.add(Duration(days: i));
      final isToday = _isSameDay(date, _today);
      final isActive = _isSameDay(date, _currentDate);
      final hasWorkout = _getWorkoutsForDate(date).isNotEmpty;
      final isTrainingDay = widget.trainingDays.contains(date.weekday);
      final isRest = _isRestDay(date);

      children.add(Expanded(
        child: GestureDetector(
          onTap: () {
            setState(() => _currentDate = date);
            if (!isRest) _applyTemplates(date);
          },
          onLongPress: () => _toggleRestDay(date),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: isRest
                  ? Colors.grey[800]!.withOpacity(0.4)
                  : isActive
                      ? Color(int.parse(primaryColor.replaceFirst('#', '0xFF')))
                          .withOpacity(0.35)
                      : isToday
                          ? Color(int.parse(
                                  primaryColor.replaceFirst('#', '0xFF')))
                              .withOpacity(0.2)
                          : isTrainingDay
                              ? Color(int.parse(primaryColor
                                      .replaceFirst('#', '0xFF')))
                                  .withOpacity(0.1)
                              : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: isToday
                  ? Border.all(
                      color: Color(
                          int.parse(primaryColor.replaceFirst('#', '0xFF'))),
                      width: 2)
                  : isActive
                      ? Border.all(
                          color: Color(int.parse(
                              primaryColor.replaceFirst('#', '0xFF'))),
                          width: 1)
                      : null,
            ),
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'][i],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isRest
                        ? Colors.grey[600]
                        : isActive || isToday
                            ? Color(int.parse(
                                primaryColor.replaceFirst('#', '0xFF')))
                            : isTrainingDay
                                ? Colors.white70
                                : Colors.grey[500],
                  )),
              const SizedBox(height: 2),
              Text('${date.day}',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: isRest
                        ? Colors.grey[600]
                        : isActive || isToday
                            ? Color(int.parse(
                                primaryColor.replaceFirst('#', '0xFF')))
                            : Colors.white,
                  )),
              if (hasWorkout && !isRest)
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Color(
                        int.parse(primaryColor.replaceFirst('#', '0xFF'))),
                    shape: BoxShape.circle,
                  ),
                ),
              if (isRest)
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.block, color: Colors.grey, size: 12),
                ),
            ]),
          ),
        ),
      ));
    }

    return Row(children: [
      IconButton(
        icon: const Icon(Icons.chevron_left, color: Colors.orange, size: 28),
        onPressed: () {
          setState(() {
            _weekOffset -= 1;
            final nm =
                _getMonday(_today).add(Duration(days: _weekOffset * 7));
            for (int i = 0; i < 7; i++) {
              _applyTemplates(nm.add(Duration(days: i)));
            }
          });
        },
      ),
      Expanded(
        child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: children),
      ),
      IconButton(
        icon: const Icon(Icons.chevron_right, color: Colors.orange, size: 28),
        onPressed: () {
          setState(() {
            _weekOffset += 1;
            final nm =
                _getMonday(_today).add(Duration(days: _weekOffset * 7));
            for (int i = 0; i < 7; i++) {
              _applyTemplates(nm.add(Duration(days: i)));
            }
          });
        },
      ),
    ]);
  }

  Widget _buildWorkoutList() {
    final list = _getWorkoutsForDate(_currentDate);
    if (list.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 30),
        child: Center(
          child: Text('Нет упражнений за этот день',
              style: TextStyle(color: Colors.grey, fontSize: 15)),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: list.length,
      itemBuilder: (ctx, index) {
        final w = list[index];
        final icon = _getIconForExercise(w.exercise);
        final weightStr = w.weight != null ? '@ ${w.weight} кг' : '';
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                w.isProhodka
                    ? Colors.orange.withOpacity(0.08)
                    : Colors.white.withOpacity(0.04),
                Colors.white.withOpacity(0.01),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: w.isProhodka
                  ? Colors.orange.withOpacity(0.3)
                  : Colors.white.withOpacity(0.06),
            ),
          ),
          child: Row(children: [
            SizedBox(
              width: 36,
              child: Text(icon, style: const TextStyle(fontSize: 22)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(w.exercise,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 16)),
                    if (w.isProhodka)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: Colors.orange.withOpacity(0.3)),
                        ),
                        child: const Text('ПРОХОДКА',
                            style: TextStyle(
                                color: Colors.orange,
                                fontSize: 9,
                                fontWeight: FontWeight.w700)),
                      ),
                  ]),
                  Text('${w.sets}×${w.reps} $weightStr',
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 13)),
                ],
              ),
            ),
            Row(children: [
              IconButton(
                icon: const Icon(Icons.edit, color: Colors.orange, size: 20),
                onPressed: () => _openEditModal(w),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              IconButton(
                icon:
                    const Icon(Icons.close, color: Colors.redAccent, size: 20),
                onPressed: () => widget.onDeleteWorkout(w.id),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ]),
          ]),
        );
      },
    );
  }

  String _getIconForExercise(String exercise) {
    const icons = {
      'Жим': '🏋️',
      'Приседания': '🏋️',
      'Тяга': '🏋️',
      'Подтягивания': '🤸',
      'Скручивания': '💪',
      'Отжимания': '💪',
      'Становая': '🏋️',
      'Выпады': '🏋️',
      'Бицепс': '💪',
      'Трицепс': '💪',
      'Плечи': '🏋️',
    };
    for (final entry in icons.entries) {
      if (exercise.contains(entry.key)) return entry.value;
    }
    return '🏋️';
  }

  Widget _buildAddButton() {
    return Column(children: [
      AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) =>
            Transform.scale(scale: _pulseAnimation.value, child: child),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _openAddModal,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(40)),
              elevation: 8,
              shadowColor: Colors.orange.withOpacity(0.6),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add, size: 20),
                SizedBox(width: 8),
                Text('Добавить упражнение',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 17)),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _showExtendCycleDialog,
          icon: const Icon(Icons.timer, color: Colors.orange, size: 18),
          label: const Text('Отложить проходку',
              style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.w600,
                  fontSize: 14)),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Colors.orange.withOpacity(0.3)),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(40)),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    ]);
  }

  // ==================== ВОДА И КРЕАТИН ====================
  Widget _buildWaterCreatineBlock() {
    return Column(children: [
      GestureDetector(
        onTap: () async {
          setState(() => _waterBlockHidden = !_waterBlockHidden);
          await _saveWaterLocal();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(children: [
                Text('💧', style: TextStyle(fontSize: 18)),
                SizedBox(width: 8),
                Text('Вода и креатин',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
              ]),
              Icon(
                _waterBlockHidden ? Icons.visibility_off : Icons.visibility,
                color: Colors.orange,
                size: 20,
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
      AnimatedCrossFade(
        duration: const Duration(milliseconds: 300),
        crossFadeState: _waterBlockHidden
            ? CrossFadeState.showSecond
            : CrossFadeState.showFirst,
        firstChild: _buildWaterCreatineContent(),
        secondChild: const SizedBox.shrink(),
      ),
    ]);
  }

  Widget _buildWaterCreatineContent() {
    final percent =
        _waterGoal > 0 ? (_waterMl / _waterGoal).clamp(0.0, 1.0) : 0.0;
    final inRest = _isInRest(_today);
    final left = _restDaysLeft();
    final creatineActive = !inRest && _creatineG > 0;

    return Column(children: [
      // ВОДА
      Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.blue.withOpacity(0.05),
              Colors.blue.withOpacity(0.01),
            ],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.blue.withOpacity(0.15)),
        ),
        child: Row(children: [
          SizedBox(
            width: 90,
            height: 90,
            child: Stack(alignment: Alignment.center, children: [
              CircularProgressIndicator(
                value: percent,
                backgroundColor: Colors.white.withOpacity(0.08),
                valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF4FC3F7)),
                strokeWidth: 8,
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${(_waterMl / 1000).toStringAsFixed(1)}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700)),
                Text('из ${(_waterGoal / 1000).toStringAsFixed(1)} л',
                    style: TextStyle(
                        color: Colors.grey[500], fontSize: 10)),
              ]),
            ]),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('💧 Вода сегодня',
                      style: TextStyle(
                          color: Color(0xFF4FC3F7),
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('${(_waterMl / 1000).toStringAsFixed(2)} л',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800)),
                  Text('Цель: ${(_waterGoal / 1000).toStringAsFixed(1)} л',
                      style:
                          TextStyle(color: Colors.grey[500], fontSize: 12)),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _showAddWaterModal,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [
                          Color(0xFF4FC3F7),
                          Color(0xFF0288D1)
                        ]),
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.blue.withOpacity(0.3),
                              blurRadius: 12)
                        ],
                      ),
                      child: const Text('+ Добавить',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13)),
                    ),
                  ),
                ]),
          ),
        ]),
      ),
      // КРЕАТИН
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.purple.withOpacity(0.06),
              Colors.purple.withOpacity(0.01),
            ],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.purple.withOpacity(0.15)),
        ),
        child: Column(children: [
          Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.purple.withOpacity(0.2)),
              ),
              child: const Center(
                  child: Text('💊', style: TextStyle(fontSize: 22))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Креатин',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    Text(
                      inRest
                          ? 'Отдых до ${_restEnd!.day}.${_restEnd!.month}'
                          : creatineActive
                              ? '✓ 5 г принято'
                              : '5 г сегодня',
                      style: TextStyle(
                        color: inRest
                            ? Colors.orange
                            : creatineActive
                                ? Colors.purple
                                : Colors.grey[500],
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ]),
            ),
            GestureDetector(
              onTap: () async {
                if (inRest) {
                  _showToast('😴 Сегодня отдых от креатина');
                  return;
                }
                setState(() => _creatineG = _creatineG > 0 ? 0 : 5);
                await _saveWaterLocal();
                await _syncWaterToSheet();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 50,
                height: 28,
                decoration: BoxDecoration(
                  color: inRest
                      ? Colors.grey.withOpacity(0.2)
                      : creatineActive
                          ? Colors.purple.withOpacity(0.5)
                          : Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: creatineActive && !inRest
                        ? Colors.purple
                        : Colors.white.withOpacity(0.1),
                  ),
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 250),
                  alignment: creatineActive
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    width: 22,
                    height: 22,
                    margin: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                        color: Colors.white, shape: BoxShape.circle),
                  ),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          if (inRest)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.orange.withOpacity(0.25)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('😴 Осталось $left дн.',
                      style: const TextStyle(
                          color: Colors.orange,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                  GestureDetector(
                    onTap: _stopRest,
                    child: const Text('Прекратить',
                        style: TextStyle(
                            color: Colors.redAccent,
                            fontSize: 12,
                            decoration: TextDecoration.underline)),
                  ),
                ],
              ),
            )
          else
            GestureDetector(
              onTap: _showRestModal,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.orange.withOpacity(0.2)),
                ),
                child: const Center(
                  child: Text('😴 Уйти на отдых',
                      style: TextStyle(
                          color: Colors.orange,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ),
        ]),
      ),
    ]);
  }

  // ==================== МОДАЛКИ ВОДЫ И ОТДЫХА ====================
  void _showAddWaterModal() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1E26),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: Colors.blue.withOpacity(0.2)),
          ),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('💧 Добавить воду',
                    style: TextStyle(
                        color: Color(0xFF4FC3F7),
                        fontSize: 22,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text('Выберите объём или введите своё число',
                    style:
                        TextStyle(color: Colors.grey[400], fontSize: 13)),
                const SizedBox(height: 16),
                Row(children: [
                  for (final ml in [200, 300, 500])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: GestureDetector(
                          onTap: () async {
                            Navigator.pop(ctx);
                            await _addWater(ml);
                          },
                          child: Container(
                            padding:
                                const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: Colors.blue.withOpacity(0.2)),
                            ),
                            child: Center(
                                child: Text('$ml мл',
                                    style: const TextStyle(
                                        color: Color(0xFF4FC3F7),
                                        fontWeight: FontWeight.w700))),
                          ),
                        ),
                      ),
                    ),
                ]),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    hintText: 'Своё число (мл)',
                    hintStyle: TextStyle(color: Colors.grey[600]),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.04),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 20),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Отмена',
                        style: TextStyle(color: Colors.grey)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      final ml = int.tryParse(controller.text);
                      if (ml == null || ml < 1) {
                        _showToast('⚠️ Введите число');
                        return;
                      }
                      Navigator.pop(ctx);
                      await _addWater(ml);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4FC3F7),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                    ),
                    child: const Text('Добавить',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ]),
              ]),
        ),
      ),
    );
  }

  Future<void> _addWater(int ml) async {
    setState(() => _waterMl += ml);
    await _saveWaterLocal();
    await _syncWaterToSheet();
    _showToast('💧 +$ml мл');
  }

  void _showRestModal() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1E26),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: Colors.orange.withOpacity(0.2)),
          ),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('😴 Отдых от креатина',
                    style: TextStyle(
                        color: Colors.orange,
                        fontSize: 22,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                    'Укажите, на сколько дней сделать перерыв. Начнётся с сегодня.',
                    style:
                        TextStyle(color: Colors.grey[400], fontSize: 13)),
                const SizedBox(height: 16),
                Row(children: [
                  for (final d in [7, 14, 30])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: GestureDetector(
                          onTap: () {
                            Navigator.pop(ctx);
                            _startRest(d);
                          },
                          child: Container(
                            padding:
                                const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: Colors.orange.withOpacity(0.2)),
                            ),
                            child: Center(
                                child: Text('$d дн.',
                                    style: const TextStyle(
                                        color: Colors.orange,
                                        fontWeight: FontWeight.w700))),
                          ),
                        ),
                      ),
                    ),
                ]),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    hintText: 'Своё число дней',
                    hintStyle: TextStyle(color: Colors.grey[600]),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.04),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 20),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Отмена',
                        style: TextStyle(color: Colors.grey)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      final d = int.tryParse(controller.text);
                      if (d == null || d < 1) {
                        _showToast('⚠️ Введите число дней');
                        return;
                      }
                      Navigator.pop(ctx);
                      _startRest(d);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                    ),
                    child: const Text('Начать отдых',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ]),
              ]),
        ),
      ),
    );
  }

  // ==================== МОДАЛКИ УПРАЖНЕНИЙ ====================
  void _openAddModal() {
    _editingWorkoutId = null;
    _exNameController.clear();
    _exSetsController.clear();
    _exRepsController.clear();
    _exWeightController.clear();
    _showAddEditModal(isEdit: false);
  }

  void _openEditModal(Workout w) {
    _editingWorkoutId = w.id;
    _exNameController.text = w.exercise;
    _exSetsController.text = w.sets.toString();
    _exRepsController.text = w.reps.toString();
    _exWeightController.text = w.weight?.toString() ?? '';
    _showAddEditModal(isEdit: true);
  }

  void _showAddEditModal({required bool isEdit}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1E26),
              borderRadius: BorderRadius.circular(36),
              border: Border.all(color: Colors.orange.withOpacity(0.15)),
            ),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(isEdit ? '✎ Редактировать' : '➕ Новое упражнение',
                      style: const TextStyle(
                          color: Colors.orange,
                          fontSize: 22,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 16),
                  _buildInput(_exNameController, 'Название упражнения'),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                        child: _buildInput(_exSetsController, 'Подходы',
                            isNumber: true)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _buildInput(_exRepsController, 'Повторы',
                            isNumber: true)),
                  ]),
                  const SizedBox(height: 12),
                  _buildInput(_exWeightController, 'Вес (кг) – необязательно',
                      isNumber: true, decimal: true),
                  const SizedBox(height: 20),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Отмена',
                          style: TextStyle(color: Colors.grey)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        final name = _exNameController.text.trim();
                        final sets = int.tryParse(_exSetsController.text);
                        final reps = int.tryParse(_exRepsController.text);
                        final w = _exWeightController.text.trim().isNotEmpty
                            ? double.tryParse(_exWeightController.text)
                            : null;

                        if (name.isEmpty || sets == null || reps == null) {
                          _showToast(
                              'Заполните название, подходы и повторы');
                          return;
                        }
                        if (_editingWorkoutId != null) {
                          widget.onUpdateWorkout(Workout(
                            id: _editingWorkoutId!,
                            date: _formatDate(_currentDate),
                            exercise: name,
                            sets: sets,
                            reps: reps,
                            weight: w,
                            isProhodka: false,
                            weekNumber: _getWeekNumber(_currentDate),
                          ));
                        } else {
                          widget.onAddWorkout(Workout(
                            id: DateTime.now()
                                .millisecondsSinceEpoch
                                .toString(),
                            date: _formatDate(_currentDate),
                            exercise: name,
                            sets: sets,
                            reps: reps,
                            weight: w,
                            isProhodka: false,
                            weekNumber: _getWeekNumber(_currentDate),
                          ));
                        }
                        Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30)),
                      ),
                      child: const Text('Сохранить',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ]),
          ),
        ),
      ),
    );
  }

  Widget _buildInput(TextEditingController c, String hint,
      {bool isNumber = false, bool decimal = false}) {
    return TextField(
      controller: c,
      keyboardType: isNumber
          ? (decimal
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.number)
          : TextInputType.text,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.grey),
        filled: true,
        fillColor: Colors.white10,
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  // ==================== МОДАЛКА ПРОХОДКИ ====================
  void _showExtendCycleDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          int weeks = 1;
          return Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1E26),
                borderRadius: BorderRadius.circular(36),
                border: Border.all(color: Colors.orange.withOpacity(0.15)),
              ),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('⏳ Отложить проходку',
                        style: TextStyle(
                            color: Colors.orange,
                            fontSize: 22,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    const Text(
                        'Проходка происходит каждые 3 недели. На сколько недель сдвинуть?',
                        style: TextStyle(
                            color: Colors.white70, fontSize: 15)),
                    const SizedBox(height: 20),
                    Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle,
                                color: Colors.orange, size: 32),
                            onPressed: () {
                              if (weeks > 1) {
                                setStateDialog(() => weeks--);
                              }
                            },
                          ),
                          SizedBox(
                            width: 60,
                            child: Center(
                              child: Text('$weeks',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 32,
                                      fontWeight: FontWeight.w700)),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle,
                                color: Colors.orange, size: 32),
                            onPressed: () {
                              if (weeks < 12) {
                                setStateDialog(() => weeks++);
                              }
                            },
                          ),
                        ]),
                    const SizedBox(height: 16),
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Отмена',
                            style: TextStyle(color: Colors.grey)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          setState(() => _prohodkaShiftWeeks += weeks);
                          _saveProhodkaShift();
                          _recalculateFutureProhodka();
                          Navigator.pop(ctx);
                          _showToast(
                              '✅ Проходка сдвинута на $weeks недель');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30)),
                        ),
                        child: const Text('Применить',
                            style:
                                TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ]),
                  ]),
            ),
          );
        },
      ),
    );
  }

  // ==================== МОДАЛКА КАЛЕНДАРЯ ====================
  void _showCalendarModal() {
    _calendarModalMonth = DateTime(_currentDate.year, _currentDate.month, 1);
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1E26),
              borderRadius: BorderRadius.circular(36),
              border: Border.all(color: Colors.orange.withOpacity(0.15)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('📅 Выберите день',
                        style: TextStyle(
                            color: Colors.orange,
                            fontSize: 22,
                            fontWeight: FontWeight.w700)),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.grey),
                      onPressed: () => Navigator.pop(ctx),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ]),
              const SizedBox(height: 12),
              Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left,
                          color: Colors.orange, size: 28),
                      onPressed: () => setStateDialog(() {
                        _calendarModalMonth = DateTime(
                            _calendarModalMonth.year,
                            _calendarModalMonth.month - 1,
                            1);
                      }),
                    ),
                    Text(
                        DateFormat('MMMM yyyy', 'ru')
                            .format(_calendarModalMonth),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600)),
                    IconButton(
                      icon: const Icon(Icons.chevron_right,
                          color: Colors.orange, size: 28),
                      onPressed: () => setStateDialog(() {
                        _calendarModalMonth = DateTime(
                            _calendarModalMonth.year,
                            _calendarModalMonth.month + 1,
                            1);
                      }),
                    ),
                  ]),
              const SizedBox(height: 8),
              _buildCalendarGrid(ctx, setStateDialog),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    final now = DateTime.now();
                    setState(() => _currentDate =
                        DateTime(now.year, now.month, now.day));
                    Navigator.pop(ctx);
                  },
                  child: const Text('Сегодня',
                      style: TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildCalendarGrid(
      BuildContext dialogCtx, StateSetter setStateDialog) {
    final year = _calendarModalMonth.year;
    final month = _calendarModalMonth.month;
    final firstDay = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final leadingEmpty = firstDay.weekday - 1;
    final cells = <Widget>[];
    const weekDays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    for (final d in weekDays) {
      cells.add(Center(
          child: Text(d,
              style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.w700))));
    }
    for (int i = 0; i < leadingEmpty; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (int d = 1; d <= daysInMonth; d++) {
      final date = DateTime(year, month, d);
      final isToday = _isSameDay(date, _today);
      final isSelected = _isSameDay(date, _currentDate);
      final hasWorkout = _getWorkoutsForDate(date).isNotEmpty;
      cells.add(GestureDetector(
        onTap: () {
          setState(() => _currentDate = date);
          Navigator.pop(dialogCtx);
        },
        child: Container(
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.orange.withOpacity(0.35)
                : hasWorkout
                    ? Colors.orange.withOpacity(0.1)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: isToday
                ? Border.all(color: Colors.orange, width: 2)
                : isSelected
                    ? Border.all(color: Colors.orange, width: 1)
                    : null,
          ),
          child: Stack(children: [
            Center(
              child: Text('$d',
                  style: TextStyle(
                    color: isSelected || isToday
                        ? Colors.orange
                        : hasWorkout
                            ? Colors.white
                            : Colors.grey[500],
                    fontWeight: isSelected || isToday
                        ? FontWeight.bold
                        : FontWeight.normal,
                    fontSize: 16,
                  )),
            ),
            if (hasWorkout)
              Positioned(
                bottom: 4,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(
                        color: Colors.orange, shape: BoxShape.circle),
                  ),
                ),
              ),
          ]),
        ),
      ));
    }
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 7,
      childAspectRatio: 1,
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      children: cells,
    );
  }

  // ==================== МОДАЛКА УВЕДОМЛЕНИЙ ====================
  void _showNotificationsModal() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1E26),
            borderRadius: BorderRadius.circular(36),
            border: Border.all(color: Colors.orange.withOpacity(0.15)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('🔔 Уведомления',
                      style: TextStyle(
                          color: Colors.orange,
                          fontSize: 22,
                          fontWeight: FontWeight.w700)),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.pop(ctx),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ]),
            const SizedBox(height: 12),
            if (_notifications.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text('Нет уведомлений',
                    style: TextStyle(color: Colors.grey)),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _notifications.length,
                itemBuilder: (ctx, i) {
                  final n = _notifications[i];
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(
                          bottom: BorderSide(
                              color: Colors.white.withOpacity(0.06))),
                    ),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(n['title'] ?? '',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(n['body'] ?? '',
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 14)),
                          const SizedBox(height: 2),
                          Text(n['time'] ?? '',
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 12)),
                        ]),
                  );
                },
              ),
          ]),
        ),
      ),
    );
  }
}