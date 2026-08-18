import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
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
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  // Подсчёт статистики
  int get totalWorkouts => widget.workouts.length;
  int get streakDays {
    if (totalWorkouts == 0) return 0;
    final dates = widget.workouts.map((w) => w.date).toList();
    dates.sort((a, b) => b.compareTo(a));
    int streak = 1;
    for (int i = 1; i < dates.length; i++) {
      final diff = dates[i - 1].difference(dates[i]).inDays;
      if (diff == 1) {
        streak++;
      } else if (diff > 1) {
        break;
      }
    }
    return streak;
  }

  double get attendancePercentage {
    // За последние 30 дней считаем, сколько было тренировочных дней (по дням недели)
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 30));
    final plannedDays = <DateTime>[];
    for (int i = 0; i <= 30; i++) {
      final day = start.add(Duration(days: i));
      // Предположим, что тренировочные дни – пн, ср, пт (можно брать из настроек)
      // Для демонстрации используем фиксированный список [1,3,5]
      if ([1, 3, 5].contains(day.weekday)) {
        plannedDays.add(day);
      }
    }
    if (plannedDays.isEmpty) return 0.0;
    int attended = 0;
    for (final day in plannedDays) {
      if (widget.workouts.any((w) =>
          w.date.year == day.year &&
          w.date.month == day.month &&
          w.date.day == day.day)) {
        attended++;
      }
    }
    return (attended / plannedDays.length) * 100;
  }

  // Получение лучших результатов
  Map<String, Map<String, dynamic>> get bestRecords {
    final records = <String, Map<String, dynamic>>{};
    for (final w in widget.workouts) {
      final name = w.exercise;
      if (!records.containsKey(name) || w.weight > records[name]!['weight']) {
        records[name] = {
          'weight': w.weight,
          'date': w.date,
        };
      }
    }
    return records;
  }

  // Данные для графика (посещаемость по неделям)
  List<int> get weeklyAttendance {
    final now = DateTime.now();
    final weeks = <int>[0, 0, 0, 0, 0]; // 5 недель
    for (int i = 0; i < 35; i++) {
      final day = now.subtract(Duration(days: 34 - i));
      final weekIndex = i ~/ 7;
      if (widget.workouts.any((w) =>
          w.date.year == day.year &&
          w.date.month == day.month &&
          w.date.day == day.day)) {
        weeks[weekIndex]++;
      }
    }
    return weeks;
  }

  // Метод "Поделиться"
  void _shareProgress() async {
    final stats =
        '📊 Мой прогресс\n'
        'Тренировок: $totalWorkouts\n'
        'Дней подряд: $streakDays\n'
        'Посещаемость: ${attendancePercentage.toStringAsFixed(0)}%\n'
        '🏆 Рекорды:\n';
    final records = bestRecords;
    final recordsText = records.entries.map((e) {
      final date = (e.value['date'] as DateTime);
      return '${e.key}: ${e.value['weight']} кг (${date.day}.${date.month})';
    }).join('\n');

    await Share.share('$stats$recordsText');
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.config['colors'] ?? {};
    final texts = widget.config['texts'] ?? {};
    final primaryColor = colors['primary'] ?? '#FF9800';
    final textColor = colors['text'] ?? '#FFFFFF';
    final bgColor = colors['background'] ?? '#0A0A0A';
    final surfaceColor = colors['surface'] ?? '#1A120A';

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
            const Text(
              '📊 Прогресс',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 16),

            // Сводка
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

            // Календарь (упрощённо, можно заменить на полноценный календарь)
            _CalendarWidget(
              workouts: widget.workouts,
              primaryColor: primaryColor,
              surfaceColor: surfaceColor,
            ),
            const SizedBox(height: 16),

            // График
            _ChartWidget(
              weekData: weekData,
              maxWeek: maxWeek,
              primaryColor: primaryColor,
              surfaceColor: surfaceColor,
            ),
            const SizedBox(height: 16),

            // Рекорды
            _RecordsWidget(
              records: bestRecords,
              primaryColor: primaryColor,
              surfaceColor: surfaceColor,
              textColor: textColor,
            ),
            const SizedBox(height: 16),

            // Кнопка "Поделиться"
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

  const _SummaryCard({
    required this.label,
    required this.value,
    this.sub,
    required this.primaryColor,
  });

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
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
            if (sub != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  sub!,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF4CAF50)),
                ),
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
  final String surfaceColor;

  const _CalendarWidget({
    required this.workouts,
    required this.primaryColor,
    required this.surfaceColor,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final firstDay = DateTime(now.year, now.month, 1);
    final firstWeekday = firstDay.weekday;
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final today = now.day;

    // Список дней месяца
    final days = <int>[];
    for (int i = 1; i <= daysInMonth; i++) days.add(i);

    // Пустые ячейки до начала месяца
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
              if (index < leadingEmpty) {
                return const SizedBox.shrink();
              }
              final day = days[index - leadingEmpty];
              final date = DateTime(now.year, now.month, day);
              final isWorkout = workouts.any((w) =>
                  w.date.year == date.year &&
                  w.date.month == date.month &&
                  w.date.day == date.day);
              final isToday = day == today;
              return Container(
                decoration: BoxDecoration(
                  color: isWorkout
                      ? Color(int.parse(primaryColor.replaceFirst('#', '0xFF'))).withOpacity(0.35)
                      : Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(8),
                  border: isToday
                      ? Border.all(color: Color(int.parse(primaryColor.replaceFirst('#', '0xFF'))))
                      : null,
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
    const names = [
      'Январь',
      'Февраль',
      'Март',
      'Апрель',
      'Май',
      'Июнь',
      'Июль',
      'Август',
      'Сентябрь',
      'Октябрь',
      'Ноябрь',
      'Декабрь'
    ];
    return names[month - 1];
  }
}

class _ChartWidget extends StatelessWidget {
  final List<int> weekData;
  final int maxWeek;
  final String primaryColor;
  final String surfaceColor;

  const _ChartWidget({
    required this.weekData,
    required this.maxWeek,
    required this.primaryColor,
    required this.surfaceColor,
  });

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
              const Text(
                'Посещаемость по неделям',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
              ),
              const Text(
                '+18%',
                style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w700, fontSize: 16),
              ),
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
                  Text(
                    labels[i],
                    style: const TextStyle(fontSize: 8, color: Colors.grey),
                  ),
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
  final String surfaceColor;
  final String textColor;

  const _RecordsWidget({
    required this.records,
    required this.primaryColor,
    required this.surfaceColor,
    required this.textColor,
  });

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
          const Text(
            '🏆 Рекорды',
            style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 8),
          if (records.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Пока нет рекордов', style: TextStyle(color: Colors.grey)),
              ),
            )
          else
            ...records.entries.map((entry) {
              final name = entry.key;
              final weight = entry.value['weight'] is num ? entry.value['weight'] : 0;
              final date = entry.value['date'] as DateTime;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    Row(
                      children: [
                        Text(
                          '$weight кг',
                          style: TextStyle(
                            color: Color(int.parse(primaryColor.replaceFirst('#', '0xFF'))),
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '• ${date.day}.${date.month}',
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
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