import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:convert';
import '../models/workout.dart';
import '../models/user.dart';
import '../services/google_sheets_service.dart';

class ProgressTab extends StatefulWidget {
  final List<Workout> workouts;
  final Map<String, dynamic> config;
  final AppUser? user;

  const ProgressTab({
    super.key,
    required this.workouts,
    this.config = const {},
    this.user,
  });

  @override
  State<ProgressTab> createState() => _ProgressTabState();
}

class _ProgressTabState extends State<ProgressTab> {
  // ===== ПОСЕЩАЕМОСТЬ =====
  final List<int> planDays = [1, 3, 5];
  Map<String, bool> attendanceData = {};
  DateTime currentMonth = DateTime.now();

  // ===== ОТЖИМАНИЯ =====
  int _pushupGoal = 100;
  List<Map<String, dynamic>> pushupEntries = [];
  int pushupTotal = 0;

  // ===== ГРАФИК ВЕСА =====
  String weightChartPeriod = 'week';

  // ===== ВОДА И КРЕАТИН =====
  int waterPeriodDays = 7;
  List<Map<String, dynamic>> _waterHistory = [];

  // ===== ВЕС =====
  List<double> _weightHistory = [];

  // ===== ОТДЫХ ОТ КРЕАТИНА =====
  DateTime? _restStart;              // начало текущего периода отдыха
  DateTime? _restEnd;                // конец текущего периода отдыха
  Set<String> _restDatesSet = {};    // даты, отмеченные как отдых (по флагам)

  @override
  void initState() {
    super.initState();
    _loadAttendance();
    _loadPushups();
    _loadPushupGoal();
    _loadRestData();
    _loadWaterHistory();
    _loadWeightHistory();
  }

  // ===== ЗАГРУЗКА / СОХРАНЕНИЕ ПОСЕЩАЕМОСТИ =====
  Future<void> _loadAttendance() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('attendance_data');
    if (data != null) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(data);
        attendanceData =
            decoded.map((key, value) => MapEntry(key, value as bool));
      } catch (e) {}
    }
    setState(() {});
  }

  Future<void> _saveAttendance() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('attendance_data', jsonEncode(attendanceData));
  }

  // ===== ЗАГРУЗКА / СОХРАНЕНИЕ ОТЖИМАНИЙ =====
  Future<void> _loadPushups() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('pushup_data');
    if (data != null) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(data);
        final entries = decoded['entries'] as List<dynamic>?;
        if (entries != null) {
          pushupEntries = entries.cast<Map<String, dynamic>>().toList();
          pushupTotal =
              pushupEntries.fold(0, (sum, e) => sum + (e['count'] as int));
        }
      } catch (e) {}
    }
    setState(() {});
  }

  Future<void> _savePushups() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pushup_data', jsonEncode({
      'entries': pushupEntries,
    }));
  }

  // ===== ЗАГРУЗКА ЦЕЛИ ОТЖИМАНИЙ =====
  Future<void> _loadPushupGoal() async {
    final prefs = await SharedPreferences.getInstance();
    final goal = prefs.getInt('profile_pushup_goal');
    if (goal != null && goal > 0) {
      setState(() => _pushupGoal = goal);
    } else if (widget.user?.pushupGoal != null &&
        widget.user!.pushupGoal! > 0) {
      setState(() => _pushupGoal = widget.user!.pushupGoal!);
    }
  }

  Future<void> _savePushupGoal(int goal) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('profile_pushup_goal', goal);
  }

  // ===== ЗАГРУЗКА ПЕРИОДА ОТДЫХА =====
  /// Читает текущий период отдыха (start / end) и флаги по датам.
  /// Флаги `creatine_rest_YYYY-MM-DD` могут быть установлены plan_tab.
  Future<void> _loadRestData() async {
    final prefs = await SharedPreferences.getInstance();
    final rs = prefs.getString('creatine_rest_start');
    final re = prefs.getString('creatine_rest_end');
    if (rs != null) _restStart = DateTime.tryParse(rs);
    if (re != null) _restEnd = DateTime.tryParse(re);

    // Собираем все ключи, начинающиеся с `creatine_rest_`
    final restDates = <String>{};
    for (final key in prefs.getKeys()) {
      if (key.startsWith('creatine_rest_') &&
          key.length > 'creatine_rest_'.length &&
          !key.endsWith('start') &&
          !key.endsWith('end')) {
        final datePart = key.substring('creatine_rest_'.length);
        // Формат YYYY-MM-DD
        if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(datePart)) {
          if (prefs.getBool(key) == true) {
            restDates.add(datePart);
          }
        }
      }
    }
    setState(() => _restDatesSet = restDates);
  }

  /// Проверяет, является ли дата днём отдыха от креатина.
  /// Возвращает true, если:
  ///   1) дата попадает в текущий период [_restStart, _restEnd], ИЛИ
  ///   2) для даты установлен флаг `creatine_rest_YYYY-MM-DD` = true.
  bool _isRestDate(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);

    // Проверка 1: попадает в текущий период отдыха
    if (_restStart != null && _restEnd != null) {
      final s = DateTime(_restStart!.year, _restStart!.month, _restStart!.day);
      final e = DateTime(_restEnd!.year, _restEnd!.month, _restEnd!.day);
      if (!d.isBefore(s) && !d.isAfter(e)) return true;
    }

    // Проверка 2: есть флаг по дате
    final key = DateFormat('yyyy-MM-dd').format(d);
    if (_restDatesSet.contains(key)) return true;

    return false;
  }

  // ===== ЗАГРУЗКА ИСТОРИИ ВОДЫ =====
  Future<void> _loadWaterHistory() async {
    if (widget.user?.email == null) {
      await _loadWaterFromPrefs();
      return;
    }
    try {
      final data =
          await GoogleSheetsService.loadDailyIntake(widget.user!.email, 30);
      if (data.isNotEmpty) {
        setState(() => _waterHistory = data);
      } else {
        await _loadWaterFromPrefs();
      }
    } catch (e) {
      print('Ошибка загрузки воды из Sheets: $e');
      await _loadWaterFromPrefs();
    }
  }

  Future<void> _loadWaterFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now();
    final history = <Map<String, dynamic>>[];
    for (int i = 29; i >= 0; i--) {
      final d = today.subtract(Duration(days: i));
      final key = DateFormat('yyyy-MM-dd').format(d);
      final water = prefs.getInt('water_$key') ?? 0;
      final creatine = prefs.getInt('creatine_$key') ?? 0;
      history.add({
        'date': key,
        'water': water,
        'creatine': creatine,
      });
    }
    setState(() => _waterHistory = history);
  }

  // ===== ЗАГРУЗКА ИСТОРИИ ВЕСА =====
  Future<void> _loadWeightHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('weight_history');
    if (data != null) {
      try {
        final List<dynamic> decoded = jsonDecode(data);
        setState(() {
          _weightHistory =
              decoded.cast<num>().map((e) => e.toDouble()).toList();
        });
        return;
      } catch (e) {}
    }
    setState(() {
      _weightHistory = List.filled(7, (widget.user?.weight ?? 75).toDouble());
    });
  }

  // ===== ВСПОМОГАТЕЛЬНЫЕ =====
  String _toLocalDateStr(DateTime date) =>
      DateFormat('yyyy-MM-dd').format(date);

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<Workout> _getWorkoutsForDate(DateTime date) {
    final ds = _toLocalDateStr(date);
    return widget.workouts.where((w) => w.date == ds).toList();
  }

  bool _isAttended(DateTime date) {
    final ds = _toLocalDateStr(date);
    final wd = date.weekday;
    final isPlanDay = planDays.contains(wd);
    return attendanceData[ds] ?? isPlanDay;
  }

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Colors.orange, Colors.orangeAccent],
            ).createShader(bounds),
            child: const Text(
              '📊 Прогресс',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildStatsRow(),
          _buildAttendanceSection(),
          _buildWaterCreatineSection(),
          _buildPushupSection(),
          _buildRecordsSection(),
          _buildWeightChartSection(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ===== 3 КАРТОЧКИ =====
  Widget _buildStatsRow() {
    final totalWorkouts = widget.workouts.length;
    final streak = _calculateStreak();
    final attendancePercent = _calculateAttendancePercent();

    return Row(
      children: [
        _statCard(totalWorkouts.toString(), 'Тренировки'),
        _statCard(streak.toString(), 'Дней подряд'),
        _statCard('${attendancePercent.toStringAsFixed(0)}%', 'Посещаемость'),
      ],
    );
  }

  Widget _statCard(String number, String label) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Column(
          children: [
            Text(number,
                style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Colors.orange)),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }

  int _calculateStreak() {
    if (widget.workouts.isEmpty) return 0;
    final dates = widget.workouts.map((w) => w.date).toList();
    dates.sort((a, b) => b.compareTo(a));
    int streak = 1;
    for (int i = 1; i < dates.length; i++) {
      final prev = DateTime.parse(dates[i - 1]);
      final curr = DateTime.parse(dates[i]);
      final diff = prev.difference(curr).inDays;
      if (diff == 1) {
        streak++;
      } else if (diff > 1) {
        break;
      }
    }
    return streak;
  }

  double _calculateAttendancePercent() {
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 30));
    final planned = <DateTime>[];
    for (int i = 0; i <= 30; i++) {
      final day = start.add(Duration(days: i));
      if (planDays.contains(day.weekday)) planned.add(day);
    }
    if (planned.isEmpty) return 0.0;
    int attended = 0;
    for (final day in planned) {
      if (_isAttended(day)) attended++;
    }
    return (attended / planned.length) * 100;
  }

  // ===== ПОСЕЩАЕМОСТЬ =====
  Widget _buildAttendanceSection() {
    return _glassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('📅 Посещаемость',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left, color: Colors.orange),
                    onPressed: () {
                      setState(() {
                        currentMonth = DateTime(
                            currentMonth.year, currentMonth.month - 1, 1);
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  Text(
                    DateFormat('MMMM yyyy', 'ru').format(currentMonth),
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, color: Colors.orange),
                    onPressed: () {
                      setState(() {
                        currentMonth = DateTime(
                            currentMonth.year, currentMonth.month + 1, 1);
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildAttendanceGrid(),
          const SizedBox(height: 8),
          _buildAttendanceStats(),
          const SizedBox(height: 12),
          _buildAttendanceBarChart(),
        ],
      ),
    );
  }

  Widget _buildAttendanceGrid() {
    final year = currentMonth.year;
    final month = currentMonth.month;
    final today = DateTime.now();
    final todayStr = _toLocalDateStr(today);

    final firstDay = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final leadingEmpty = firstDay.weekday - 1;

    final cells = <Widget>[];
    const weekDays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    for (final dayName in weekDays) {
      cells.add(Container(
        alignment: Alignment.center,
        child: Text(dayName,
            style: TextStyle(
                color: Colors.grey[600],
                fontSize: 10,
                fontWeight: FontWeight.w600)),
      ));
    }
    for (int i = 0; i < leadingEmpty; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (int d = 1; d <= daysInMonth; d++) {
      final date = DateTime(year, month, d);
      final dateStr = _toLocalDateStr(date);
      final isToday = dateStr == todayStr;
      final attended = _isAttended(date);

      cells.add(GestureDetector(
        onTap: () {
          setState(() {
            attendanceData[dateStr] = !attended;
          });
          _saveAttendance();
        },
        child: Container(
          decoration: BoxDecoration(
            color: attended
                ? Colors.orange.withOpacity(0.3)
                : Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(12),
            border: isToday
                ? Border.all(color: Colors.orange, width: 2)
                : null,
          ),
          child: Center(
            child: Text('$d',
                style: TextStyle(
                    color: attended ? Colors.orange : Colors.grey[500],
                    fontWeight:
                        attended ? FontWeight.bold : FontWeight.normal,
                    fontSize: 14)),
          ),
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

  Widget _buildAttendanceStats() {
    final year = currentMonth.year;
    final month = currentMonth.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    int plan = 0, attended = 0, missed = 0;
    for (int d = 1; d <= daysInMonth; d++) {
      final date = DateTime(year, month, d);
      if (planDays.contains(date.weekday)) {
        plan++;
        if (_isAttended(date)) {
          attended++;
        } else {
          missed++;
        }
      }
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _statLabel('План', '$plan дн.'),
        _statLabel('Посещено', '$attended дн.'),
        _statLabel('Пропущено', '$missed дн.'),
      ],
    );
  }

  Widget _statLabel(String label, String value) {
    return Text('$label: $value',
        style: TextStyle(fontSize: 13, color: Colors.grey[400]));
  }

  Widget _buildAttendanceBarChart() {
    final data = _buildAttendanceChartData();
    if (data.isEmpty) {
      return const SizedBox(
        height: 80,
        child: Center(
          child: Text('Нет данных для графика',
              style: TextStyle(color: Colors.grey)),
        ),
      );
    }
    return SizedBox(
      height: 80,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: data
                  .map((e) => e.barRods[0].toY)
                  .reduce((a, b) => a > b ? a : b) +
              1,
          barTouchData: BarTouchData(enabled: false),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index >= 0 && index < data.length) {
                    return Text('${index + 1} нед',
                        style:
                            const TextStyle(fontSize: 9, color: Colors.grey));
                  }
                  return const Text('');
                },
              ),
            ),
            leftTitles:
                AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barGroups: data,
        ),
      ),
    );
  }

  List<BarChartGroupData> _buildAttendanceChartData() {
    final year = currentMonth.year;
    final month = currentMonth.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;

    final weeklySums = <int>[];
    var week = <int>[];
    for (int d = 1; d <= daysInMonth; d++) {
      final date = DateTime(year, month, d);
      final wd = date.weekday;
      if (planDays.contains(wd)) {
        week.add(_isAttended(date) ? 1 : 0);
      }
      if (wd == 6 || d == daysInMonth) {
        if (week.isNotEmpty) {
          weeklySums.add(week.fold(0, (a, b) => a + b));
          week = [];
        }
      }
    }
    if (week.isNotEmpty) {
      weeklySums.add(week.fold(0, (a, b) => a + b));
    }

    return weeklySums.asMap().entries.map((entry) {
      return BarChartGroupData(
        x: entry.key,
        barRods: [
          BarRodData(
            toY: entry.value.toDouble(),
            color: Colors.orange,
            width: 16,
            borderRadius: BorderRadius.circular(4),
          )
        ],
      );
    }).toList();
  }

  // ===== ВОДА И КРЕАТИН =====
  Widget _buildWaterCreatineSection() {
    return _glassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('💧 Вода и креатин',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
              Row(
                children: [
                  _periodButton('7 дней', 7),
                  const SizedBox(width: 6),
                  _periodButton('30 дней', 30),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildWaterStats(),
          const SizedBox(height: 12),
          _buildWaterChart(),
          const SizedBox(height: 10),
          _buildWaterLegend(),
          const SizedBox(height: 8),
          _buildRestStat(),
        ],
      ),
    );
  }

  Widget _periodButton(String label, int days) {
    final isActive = waterPeriodDays == days;
    return GestureDetector(
      onTap: () {
        setState(() => waterPeriodDays = days);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: isActive
              ? Colors.blue.withOpacity(0.2)
              : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: isActive ? Colors.blue : Colors.white.withOpacity(0.06),
          ),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isActive ? Colors.blue : Colors.grey)),
      ),
    );
  }

  Widget _buildWaterStats() {
    final data = _waterHistory.length > waterPeriodDays
        ? _waterHistory.sublist(_waterHistory.length - waterPeriodDays)
        : _waterHistory;

    final avg = data.isEmpty
        ? 0.0
        : data.fold<int>(0, (s, d) => s + (d['water'] as int)) /
            data.length /
            1000;
    final daysNorm = data.where((d) => (d['water'] as int) >= 2400).length;
    final daysCreatine = data.where((d) => (d['creatine'] as int) > 0).length;

    return Row(
      children: [
        _waterStat('${avg.toStringAsFixed(1)}', 'л/день', Colors.lightBlue),
        const SizedBox(width: 8),
        _waterStat('$daysNorm', 'дней нормы', Colors.lightBlue),
        const SizedBox(width: 8),
        _waterStat('$daysCreatine', 'дней креатина', Colors.purple),
      ],
    );
  }

  Widget _waterStat(String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.04)),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: color)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 9,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildWaterChart() {
    final data = _waterHistory.length > waterPeriodDays
        ? _waterHistory.sublist(_waterHistory.length - waterPeriodDays)
        : _waterHistory;

    if (data.isEmpty) {
      return const SizedBox(
        height: 120,
        child: Center(
          child: Text('Нет данных',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
        ),
      );
    }

    return SizedBox(
      height: 120,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: 3.5,
          barTouchData: BarTouchData(enabled: false),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index >= 0 && index < data.length) {
                    final date = data[index]['date'] as String;
                    if (waterPeriodDays == 7) {
                      return Text(
                        date.substring(8, 10),
                        style: const TextStyle(
                            fontSize: 9, color: Colors.grey),
                      );
                    } else {
                      if (index % 5 == 0) {
                        return Text(
                          date.substring(8, 10),
                          style: const TextStyle(
                              fontSize: 8, color: Colors.grey),
                        );
                      }
                      return const Text('');
                    }
                  }
                  return const Text('');
                },
              ),
            ),
            leftTitles:
                AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 1,
            getDrawingHorizontalLine: (value) => FlLine(
              color: Colors.white.withOpacity(0.04),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: data.asMap().entries.map((entry) {
            final d = entry.value;
            final dateStr = d['date'] as String;
            final date = DateTime.tryParse(dateStr);
            final water = (d['water'] as int) / 1000.0;
            final creatine = (d['creatine'] as int) > 0;
            final isRest = date != null && _isRestDate(date);

            // Цвет по приоритету:
            // 1) Отдых — серый
            // 2) Креатин — фиолетовый
            // 3) Вода > 0 — голубой
            // 4) Иначе — серый (нет данных)
            Color color;
            if (isRest) {
              color = Colors.grey.withOpacity(0.5);
            } else if (creatine) {
              color = Colors.purple.withOpacity(0.7);
            } else if (water > 0) {
              color = Colors.lightBlue.withOpacity(0.7);
            } else {
              color = Colors.grey.withOpacity(0.3);
            }

            return BarChartGroupData(
              x: entry.key,
              barRods: [
                BarRodData(
                  toY: water,
                  color: color,
                  width: waterPeriodDays == 7 ? 16 : 6,
                  borderRadius: BorderRadius.circular(4),
                )
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildWaterLegend() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _legendItem(Colors.lightBlue, 'Обычный'),
        const SizedBox(width: 12),
        _legendItem(Colors.purple, 'Креатин'),
        const SizedBox(width: 12),
        _legendItem(Colors.grey, 'Отдых'),
      ],
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(fontSize: 10, color: Colors.grey[600])),
      ],
    );
  }

  // ===== ИСПРАВЛЕННЫЙ ПОДСЧЁТ ДНЕЙ ОТДЫХА =====
  /// Считает дни отдыха от креатина **точно** — по датам:
  ///   - попадает в текущий период [_restStart, _restEnd], ИЛИ
  ///   - есть флаг `creatine_rest_YYYY-MM-DD = true`.
  ///
  /// Больше НЕ считает "вода=0 И креатин=0" как отдых.
  Widget _buildRestStat() {
    final data = _waterHistory.length > waterPeriodDays
        ? _waterHistory.sublist(_waterHistory.length - waterPeriodDays)
        : _waterHistory;

    int restDays = 0;
    for (final d in data) {
      final dateStr = d['date'] as String;
      final date = DateTime.tryParse(dateStr);
      if (date == null) continue;
      if (_isRestDate(date)) restDays++;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('😴 Отдых от креатина',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          Text('$restDays дн.',
              style: const TextStyle(
                  color: Colors.orange,
                  fontSize: 15,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  // ===== ОТЖИМАНИЯ =====
  Widget _buildPushupSection() {
    final done = pushupTotal;
    final percent =
        _pushupGoal > 0 ? (done / _pushupGoal).clamp(0.0, 1.0) : 0.0;
    final isComplete = done >= _pushupGoal;
    final overGoal = done > _pushupGoal ? done - _pushupGoal : 0;

    return _glassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('🔥 Отжимания сегодня',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
              GestureDetector(
                onTap: _showAddPushupDialog,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Colors.orange, Colors.orangeAccent],
                    ),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.orange.withOpacity(0.3),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: const Center(
                      child:
                          Icon(Icons.add, color: Colors.black, size: 22)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 84,
                height: 84,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: percent,
                      backgroundColor: Colors.white.withOpacity(0.08),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isComplete ? Colors.green : Colors.orange,
                      ),
                      strokeWidth: 8,
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('$done',
                            style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Colors.white)),
                        Text('из $_pushupGoal',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[600])),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Цель: $_pushupGoal раз',
                            style: TextStyle(
                                fontSize: 14, color: Colors.grey[400])),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: _showEditGoalDialog,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.edit,
                              color: Colors.orange,
                              size: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'Сделано: $done${overGoal > 0 ? ' (+$overGoal)' : ''}',
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Colors.orange),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (pushupEntries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: Text('Нет записей',
                    style: TextStyle(color: Colors.grey)),
              ),
            )
          else
            Container(
              constraints: const BoxConstraints(maxHeight: 120),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: pushupEntries.length,
                itemBuilder: (ctx, index) {
                  final entry = pushupEntries[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('+${entry['count']} раз',
                            style: const TextStyle(
                                color: Colors.white70)),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              pushupEntries.removeAt(index);
                              pushupTotal = pushupEntries.fold(
                                  0, (sum, e) => sum + (e['count'] as int));
                              _savePushups();
                            });
                          },
                          child: const Icon(Icons.close,
                              color: Colors.redAccent, size: 18),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  void _showEditGoalDialog() {
    final controller =
        TextEditingController(text: _pushupGoal.toString());
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
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
              const Text('✏️ Изменить цель',
                  style: TextStyle(
                      color: Colors.orange,
                      fontSize: 22,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('Текущая цель: $_pushupGoal раз',
                  style: TextStyle(color: Colors.grey[400], fontSize: 13)),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Новая цель',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.04),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Отмена',
                        style: TextStyle(color: Colors.grey)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      final newGoal = int.tryParse(controller.text);
                      if (newGoal == null || newGoal < 1) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Введите число больше 0')),
                        );
                        return;
                      }
                      setState(() => _pushupGoal = newGoal);
                      await _savePushupGoal(newGoal);
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('✅ Цель: $newGoal раз'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                    ),
                    child: const Text('Сохранить',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddPushupDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
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
              const Text('➕ Добавить отжимания',
                  style: TextStyle(
                      color: Colors.orange,
                      fontSize: 22,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Количество',
                  hintStyle: TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: Colors.white10,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Отмена',
                        style: TextStyle(color: Colors.grey)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      final count = int.tryParse(controller.text);
                      if (count == null || count < 1) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Введите число больше 0')),
                        );
                        return;
                      }
                      setState(() {
                        pushupEntries.add({
                          'id': DateTime.now().millisecondsSinceEpoch,
                          'count': count,
                        });
                        pushupTotal += count;
                        _savePushups();
                      });
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
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===== РЕКОРДЫ =====
  Widget _buildRecordsSection() {
    final records = <String, Map<String, dynamic>>{};
    for (final w in widget.workouts) {
      if (w.weight == null) continue;
      final name = w.exercise;
      final currentBest = records[name]?['weight'] as double?;
      if (currentBest == null || w.weight! > currentBest) {
        records[name] = {
          'weight': w.weight,
          'date': w.date,
        };
      }
    }

    return _glassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🏆 Лучшие рекорды',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Colors.white)),
          const SizedBox(height: 8),
          if (records.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Нет записей',
                  style: TextStyle(color: Colors.grey)),
            )
          else
            ...records.entries.map((entry) {
              final exercise = entry.key;
              final weight = entry.value['weight'];
              final date = entry.value['date'] as String;
              final dateFormatted =
                  DateFormat('dd MMM', 'ru').format(DateTime.parse(date));
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(exercise,
                        style: const TextStyle(color: Colors.white)),
                    Row(
                      children: [
                        Text('${weight.toStringAsFixed(1)} кг',
                            style: const TextStyle(
                                color: Colors.orange,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(width: 8),
                        Text(dateFormatted,
                            style: TextStyle(
                                color: Colors.grey[600], fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
        ],
      ),
    );
  }

  // ===== ГРАФИК ВЕСА И РОСТА =====
  Widget _buildWeightChartSection() {
    final spotsWeight = _getWeightSpots(weightChartPeriod);
    final spotsHeight = _getHeightSpots(weightChartPeriod);
    final labels = _getWeightLabels(weightChartPeriod);

    return _glassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('📈 Вес и рост',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
              Row(
                children: [
                  _weightPeriodButton('Неделя', 'week'),
                  const SizedBox(width: 6),
                  _weightPeriodButton('Месяц', 'month'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 170,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: (spotsWeight.length - 1).toDouble(),
                lineTouchData: LineTouchData(enabled: false),
                gridData: FlGridData(
                  show: true,
                  drawHorizontalLine: true,
                  drawVerticalLine: false,
                  horizontalInterval: 1,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.white.withOpacity(0.04),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index >= 0 && index < labels.length) {
                          return Text(labels[index],
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey[500]));
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        return Text(value.toInt().toString(),
                            style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey[500]));
                      },
                    ),
                  ),
                  topTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spotsWeight,
                    isCurved: true,
                    color: Colors.orange,
                    barWidth: 2,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) =>
                          FlDotCirclePainter(
                        radius: 4,
                        color: Colors.orange,
                        strokeColor: Colors.orange,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.orange.withOpacity(0.08),
                    ),
                  ),
                  LineChartBarData(
                    spots: spotsHeight,
                    isCurved: false,
                    color: Colors.lightBlueAccent,
                    barWidth: 2,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) =>
                          FlDotCirclePainter(
                        radius: 3,
                        color: Colors.lightBlueAccent,
                        strokeColor: Colors.lightBlueAccent,
                      ),
                    ),
                    dashArray: [5, 5],
                    belowBarData: BarAreaData(show: false),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _weightPeriodButton(String label, String period) {
    final isActive = weightChartPeriod == period;
    return GestureDetector(
      onTap: () {
        setState(() => weightChartPeriod = period);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: isActive
              ? Colors.orange.withOpacity(0.2)
              : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: isActive ? Colors.orange : Colors.white.withOpacity(0.06),
          ),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isActive ? Colors.orange : Colors.grey)),
      ),
    );
  }

  List<FlSpot> _getWeightSpots(String period) {
    if (_weightHistory.isEmpty) {
      return [FlSpot(0, (widget.user?.weight ?? 75).toDouble())];
    }
    if (period == 'week') {
      final data = _weightHistory.length >= 7
          ? _weightHistory.sublist(_weightHistory.length - 7)
          : _weightHistory;
      return data
          .asMap()
          .entries
          .map((e) => FlSpot(e.key.toDouble(), e.value))
          .toList();
    } else {
      if (_weightHistory.length < 4) {
        return _weightHistory
            .asMap()
            .entries
            .map((e) => FlSpot(e.key.toDouble(), e.value))
            .toList();
      }
      final monthData = <double>[];
      for (int i = 0; i < 4; i++) {
        final start = i * (_weightHistory.length ~/ 4);
        final end = (i + 1) * (_weightHistory.length ~/ 4);
        final slice = _weightHistory.sublist(
            start, end > _weightHistory.length ? _weightHistory.length : end);
        if (slice.isNotEmpty) {
          monthData.add(slice.reduce((a, b) => a + b) / slice.length);
        }
      }
      return monthData
          .asMap()
          .entries
          .map((e) => FlSpot(e.key.toDouble(), e.value))
          .toList();
    }
  }

  List<FlSpot> _getHeightSpots(String period) {
    final height = (widget.user?.height ?? 180).toDouble();
    final count = period == 'week' ? 7 : 4;
    return List.generate(count, (i) => FlSpot(i.toDouble(), height));
  }

  List<String> _getWeightLabels(String period) {
    if (period == 'week') {
      return ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    }
    return ['1 нед', '2 нед', '3 нед', '4 нед'];
  }

  // ===== ОБЩИЙ КОНТЕЙНЕР =====
  Widget _glassContainer({required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 32,
          ),
        ],
      ),
      child: child,
    );
  }
}