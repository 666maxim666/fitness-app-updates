import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert'; // ← добавлен импорт
import '../models/workout.dart';

class ProgressTab extends StatefulWidget {
  final List<Workout> workouts;
  final Map<String, dynamic> config;

  const ProgressTab({super.key, required this.workouts, this.config = const {}});

  @override
  State<ProgressTab> createState() => _ProgressTabState();
}

class _ProgressTabState extends State<ProgressTab> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // ===== ДАННЫЕ ОТЖИМАНИЙ =====
  int _pushupGoal = 50;
  List<Map<String, dynamic>> _todayPushups = [];
  final TextEditingController _countController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );
    _animationController.forward();

    _loadPushupData();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _countController.dispose();
    super.dispose();
  }

  // ===== ЗАГРУЗКА ДАННЫХ =====
  Future<void> _loadPushupData() async {
    final prefs = await SharedPreferences.getInstance();
    final goal = prefs.getInt('pushup_goal');
    if (goal != null) {
      setState(() {
        _pushupGoal = goal;
      });
    }

    final today = DateTime.now().toIso8601String().split('T')[0];
    final data = prefs.getString('pushup_today');
    if (data != null) {
      final List<dynamic> decoded = jsonDecode(data);
      setState(() {
        _todayPushups = decoded.where((item) => item['date'] == today).cast<Map<String, dynamic>>().toList();
      });
    } else {
      setState(() {
        _todayPushups = [];
      });
    }
  }

  Future<void> _savePushupData() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T')[0];
    final allData = _todayPushups.where((item) => item['date'] == today).toList();
    await prefs.setString('pushup_today', jsonEncode(allData));
  }

  // ===== ДОБАВЛЕНИЕ =====
  void _addPushup() {
    final count = int.tryParse(_countController.text);
    if (count == null || count < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите корректное количество')),
      );
      return;
    }

    final today = DateTime.now().toIso8601String().split('T')[0];
    setState(() {
      _todayPushups.add({
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'count': count,
        'date': today,
      });
    });
    _savePushupData();
    _countController.clear();
  }

  void _deletePushup(String id) {
    setState(() {
      _todayPushups.removeWhere((item) => item['id'] == id);
    });
    _savePushupData();
  }

  // ===== ОСТАЛЬНАЯ СТАТИСТИКА =====
  int get totalWorkouts => widget.workouts.length;

  int get streakDays {
    if (totalWorkouts == 0) return 0;
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

  double get attendancePercentage {
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 30));
    final plannedDays = <DateTime>[];
    for (int i = 0; i <= 30; i++) {
      final day = start.add(Duration(days: i));
      if ([1, 3, 5].contains(day.weekday)) {
        plannedDays.add(day);
      }
    }
    if (plannedDays.isEmpty) return 0.0;
    int attended = 0;
    for (final day in plannedDays) {
      final dateStr = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      if (widget.workouts.any((w) => w.date == dateStr)) {
        attended++;
      }
    }
    return (attended / plannedDays.length) * 100;
  }

  // ===== ИСПРАВЛЕННЫЙ BEST RECORDS =====
  Map<String, Map<String, dynamic>> get bestRecords {
    final records = <String, Map<String, dynamic>>{};
    for (final w in widget.workouts) {
      if (w.weight == null) continue; // проходки пропускаем
      final name = w.exercise;
      final currentBest = records[name]?['weight'] as double?;
      if (currentBest == null || w.weight! > currentBest) {
        records[name] = {
          'weight': w.weight,
          'date': w.date,
        };
      }
    }
    return records;
  }

  List<int> get weeklyAttendance {
    final now = DateTime.now();
    final weeks = <int>[0, 0, 0, 0, 0];
    for (int i = 0; i < 35; i++) {
      final day = now.subtract(Duration(days: 34 - i));
      final dateStr = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      final weekIndex = i ~/ 7;
      if (widget.workouts.any((w) => w.date == dateStr)) {
        weeks[weekIndex]++;
      }
    }
    return weeks;
  }

  void _shareProgress() async {
    final stats =
        '📊 Мой прогресс\n'
        'Тренировок: $totalWorkouts\n'
        'Дней подряд: $streakDays\n'
        'Посещаемость: ${attendancePercentage.toStringAsFixed(0)}%\n'
        '🏆 Рекорды:\n';
    final records = bestRecords;
    final recordsText = records.entries.map((e) {
      final date = e.value['date'] as String;
      return '${e.key}: ${e.value['weight']} кг (${date.substring(8, 10)}.${date.substring(5, 7)})';
    }).join('\n');
    await Share.share('$stats$recordsText');
  }

  // ===== ВИДЖЕТ ОТЖИМАНИЙ =====
  Widget _buildPushupSection() {
    final today = DateTime.now().toIso8601String().split('T')[0];
    final done = _todayPushups
        .where((item) => item['date'] == today)
        .fold<int>(0, (sum, item) => sum + (item['count'] as int));
    final percent = _pushupGoal > 0 ? (done / _pushupGoal).clamp(0.0, 1.0) : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '🔥 Отжимания сегодня',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
              ),
              IconButton(
                icon: const Icon(Icons.add, color: Colors.orange),
                onPressed: _showAddPushupDialog,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // Круговая диаграмма
              SizedBox(
                width: 80,
                height: 80,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: percent,
                      backgroundColor: Colors.white.withOpacity(0.1),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        percent >= 0.8 ? Colors.green : percent >= 0.5 ? Colors.orange : Colors.redAccent,
                      ),
                      strokeWidth: 8,
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${(percent * 100).toInt()}%',
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '$done / $_pushupGoal',
                          style: const TextStyle(color: Colors.grey, fontSize: 11),
                        ),
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
                    const Text('Цель на день', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    Text('$_pushupGoal раз', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    const Text('Сделано', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    Text('$done раз', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          if (_todayPushups.isNotEmpty) ...[
            const Divider(height: 24, color: Colors.white10),
            const Text('Записи', style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 4),
            ..._todayPushups.map((item) {
              final count = item['count'] as int;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('$count раз', style: const TextStyle(color: Colors.white, fontSize: 14)),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.redAccent, size: 18),
                      onPressed: () => _deletePushup(item['id']),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  void _showAddPushupDialog() {
    _countController.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A120A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: const Text('➕ Добавить отжимания', style: TextStyle(color: Colors.orange)),
        content: TextField(
          controller: _countController,
          keyboardType: TextInputType.number,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Количество раз',
            hintStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.orange)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              _addPushup();
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.black,
            ),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.config['colors'] ?? {};
    final primaryColor = colors['primary'] ?? '#FF9800';
    final textColor = colors['text'] ?? '#FFFFFF';
    final total = totalWorkouts;
    final streak = streakDays;
    final attendance = attendancePercentage;
    final weekData = weeklyAttendance;
    final maxWeek = weekData.isNotEmpty ? weekData.reduce((a, b) => a > b ? a : b) : 1;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('📊 Прогресс', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 16),
            // ===== ОТЖИМАНИЯ =====
            _buildPushupSection(),
            // ===== СТАТИСТИКА ТРЕНИРОВОК =====
            Row(
              children: [
                _SummaryCard(label: 'Тренировок', value: '$total', primaryColor: primaryColor),
                const SizedBox(width: 10),
                _SummaryCard(label: 'Дней подряд', value: '$streak', primaryColor: primaryColor),
                const SizedBox(width: 10),
                _SummaryCard(
                  label: 'Посещаемость',
                  value: '${attendance.toStringAsFixed(0)}%',
                  primaryColor: primaryColor,
                  sub: '▲ +5%',
                ),
              ],
            ),
            const SizedBox(height: 16),
            _CalendarWidget(workouts: widget.workouts, primaryColor: primaryColor),
            const SizedBox(height: 16),
            _ChartWidget(weekData: weekData, maxWeek: maxWeek, primaryColor: primaryColor),
            const SizedBox(height: 16),
            _RecordsWidget(records: bestRecords, primaryColor: primaryColor),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _shareProgress,
                icon: const Icon(Icons.share, color: Colors.black),
                label: const Text('📤 Поделиться прогрессом', style: TextStyle(color: Colors.black)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(int.parse(primaryColor.replaceFirst('#', '0xFF'))),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===== ВСПОМОГАТЕЛЬНЫЕ ВИДЖЕТЫ =====
class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final String primaryColor;
  const _SummaryCard({required this.label, required this.value, this.sub, required this.primaryColor});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Color(int.parse(primaryColor.replaceFirst('#', '0xFF'))).withOpacity(0.15)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Color(int.parse(primaryColor.replaceFirst('#', '0xFF'))),
              ),
            ),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
            if (sub != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(sub!, style: const TextStyle(fontSize: 12, color: Color(0xFF4CAF50))),
              ),
          ],
        ),
      ),
    );
  }
}

class _CalendarWidget extends StatelessWidget {
  final List<Workout> workouts;
  final String primaryColor;
  const _CalendarWidget({required this.workouts, required this.primaryColor});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final firstDay = DateTime(now.year, now.month, 1);
    final firstWeekday = firstDay.weekday;
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final today = now.day;

    final days = List.generate(daysInMonth, (i) => i + 1);
    final leadingEmpty = firstWeekday - 1;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Color(int.parse(primaryColor.replaceFirst('#', '0xFF'))).withOpacity(0.06)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_monthName(now.month)} ${now.year}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
              ),
              Row(
                children: [
                  Icon(Icons.chevron_left, color: Color(int.parse(primaryColor.replaceFirst('#', '0xFF')))),
                  Icon(Icons.chevron_right, color: Color(int.parse(primaryColor.replaceFirst('#', '0xFF')))),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: leadingEmpty + days.length,
            itemBuilder: (context, index) {
              if (index < leadingEmpty) return const SizedBox.shrink();
              final day = days[index - leadingEmpty];
              final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
              final isWorkout = workouts.any((w) => w.date == dateStr);
              final isToday = day == today;
              return Container(
                decoration: BoxDecoration(
                  color: isWorkout
                      ? Color(int.parse(primaryColor.replaceFirst('#', '0xFF'))).withOpacity(0.35)
                      : Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(8),
                  border: isToday ? Border.all(color: Color(int.parse(primaryColor.replaceFirst('#', '0xFF')))) : null,
                ),
                child: Center(
                  child: Text(
                    '$day',
                    style: TextStyle(
                      color: isWorkout ? Colors.white : Colors.grey[500],
                      fontSize: 12,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  String _monthName(int month) {
    const names = ['Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь', 'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'];
    return names[month - 1];
  }
}

class _ChartWidget extends StatelessWidget {
  final List<int> weekData;
  final int maxWeek;
  final String primaryColor;
  const _ChartWidget({required this.weekData, required this.maxWeek, required this.primaryColor});

  @override
  Widget build(BuildContext context) {
    final labels = ['1 нед', '2 нед', '3 нед', '4 нед', '5 нед'];
    final maxHeight = 80.0;
    final percent = maxWeek > 0 ? weekData.map((v) => v / maxWeek).toList() : [0.0, 0.0, 0.0, 0.0, 0.0];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Color(int.parse(primaryColor.replaceFirst('#', '0xFF'))).withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Посещаемость по неделям', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
              const Text('+18%', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w700, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(5, (i) {
              final height = maxHeight * percent[i];
              return Column(
                children: [
                  Container(
                    width: 20,
                    height: height < 2 ? 2 : height,
                    decoration: BoxDecoration(
                      color: Color(int.parse(primaryColor.replaceFirst('#', '0xFF'))),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(labels[i], style: const TextStyle(fontSize: 8, color: Colors.grey)),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _RecordsWidget extends StatelessWidget {
  final Map<String, Map<String, dynamic>> records;
  final String primaryColor;
  const _RecordsWidget({required this.records, required this.primaryColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Color(int.parse(primaryColor.replaceFirst('#', '0xFF'))).withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🏆 Рекорды', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 8),
          if (records.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('Пока нет рекордов', style: TextStyle(color: Colors.grey))))
          else
            ...records.entries.map((entry) {
              final name = entry.key;
              final weight = entry.value['weight'] is num ? entry.value['weight'] : 0;
              final date = entry.value['date'] as String;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(name, style: const TextStyle(color: Colors.white, fontSize: 14)),
                    Row(
                      children: [
                        Text('$weight кг', style: TextStyle(color: Color(int.parse(primaryColor.replaceFirst('#', '0xFF'))), fontWeight: FontWeight.w700, fontSize: 14)),
                        const SizedBox(width: 6),
                        Text('• ${date.substring(8, 10)}.${date.substring(5, 7)}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}