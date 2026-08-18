import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/workout.dart';

class PlanTab extends StatefulWidget {
  final List<Workout> workouts;
  final Function(Workout) onAddWorkout;
  final Function(Workout) onUpdateWorkout;
  final Function(String) onDeleteWorkout;
  final Map<String, dynamic> config;

  const PlanTab({
    super.key,
    required this.workouts,
    required this.onAddWorkout,
    required this.onUpdateWorkout,
    required this.onDeleteWorkout,
    this.config = const {},
  });

  @override
  State<PlanTab> createState() => _PlanTabState();
}

class _PlanTabState extends State<PlanTab> {
  late DateTime _selectedDate;
  late DateTime _today;
  int _weekOffset = 0;

  // Шаблоны для автодублирования
  Map<String, List<Map<String, dynamic>>> _templates = {};
  List<String> _exerciseBase = [];

  @override
  void initState() {
    super.initState();
    _today = DateTime.now();
    _selectedDate = DateTime(_today.year, _today.month, _today.day);
    _loadLocalData();
  }

  // ===== ЛОКАЛЬНОЕ ХРАНЕНИЕ =====
  Future<void> _loadLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    final templatesStr = prefs.getString('gym_templates');
    if (templatesStr != null) {
      _templates = Map<String, List<Map<String, dynamic>>>.from(
        jsonDecode(templatesStr) as Map,
      );
    }
    final baseStr = prefs.getString('gym_exercise_base');
    if (baseStr != null) {
      _exerciseBase = List<String>.from(jsonDecode(baseStr) as List);
    }
    setState(() {});
  }

  Future<void> _saveLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gym_templates', jsonEncode(_templates));
    await prefs.setString('gym_exercise_base', jsonEncode(_exerciseBase));
  }

  // ===== ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ =====
  DateTime _getMonday(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final day = d.weekday;
    final diff = d.day - day + (day == 7 ? -6 : 1);
    return DateTime(d.year, d.month, diff);
  }

  bool _isSameDay(DateTime d1, DateTime d2) {
    return d1.year == d2.year && d1.month == d2.month && d1.day == d2.day;
  }

  String _formatDate(DateTime d) {
    return DateFormat('yyyy-MM-dd').format(d);
  }

  int _getWeekNumber(DateTime date) {
    final start = DateTime(date.year, 1, 1);
    final diff = date.difference(start).inDays;
    return ((diff + start.weekday - 1) / 7).floor() + 1;
  }

  List<Workout> _getWorkoutsForDate(DateTime date) {
    final dateStr = _formatDate(date);
    return widget.workouts.where((w) => w.date == dateStr).toList();
  }

  // ===== АВТОДУБЛИРОВАНИЕ И ПРОХОДКИ =====
  void _applyTemplates(DateTime date) {
    final dayKey = 'day_${date.weekday}';
    if (!_templates.containsKey(dayKey)) return;

    final existing = _getWorkoutsForDate(date);
    final weekNum = _getWeekNumber(date);
    final isProhodka = (weekNum % 3 == 0);

    for (final t in _templates[dayKey]!) {
      final exists = existing.any((w) =>
          w.exercise == t['exercise'] &&
          w.sets == t['sets'] &&
          w.reps == t['reps'] &&
          (w.weight == t['weight'] || (w.weight == 'проходка' && isProhodka)));
      if (!exists) {
        final weightVal = isProhodka ? 'проходка' : t['weight'];
        final newWorkout = Workout(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          date: _formatDate(date),
          exercise: t['exercise'],
          sets: t['sets'],
          reps: t['reps'],
          weight: weightVal,
          isProhodka: isProhodka,
          weekNumber: weekNum,
        );
        widget.onAddWorkout(newWorkout);
      }
    }
  }

  // ===== КАЛЕНДАРЬ =====
  Widget _buildCalendar() {
    final colors = widget.config['colors'] ?? {};
    final primaryColor = colors['primary'] ?? '#FF9800';
    final baseMonday = _getMonday(_today);
    baseMonday.add(Duration(days: _weekOffset * 7));

    final children = <Widget>[];
    for (int i = 0; i < 7; i++) {
      final date = baseMonday.add(Duration(days: i));
      final isToday = _isSameDay(date, _today);
      final isActive = _isSameDay(date, _selectedDate);
      final hasWorkout = _getWorkoutsForDate(date).isNotEmpty;

      children.add(
        GestureDetector(
          onTap: () {
            setState(() {
              _selectedDate = date;
              _applyTemplates(date);
            });
          },
          child: Container(
            decoration: BoxDecoration(
              color: isActive
                  ? Color(int.parse(primaryColor.replaceFirst('#', '0xFF'))).withOpacity(0.25)
                  : isToday
                      ? Color(int.parse(primaryColor.replaceFirst('#', '0xFF'))).withOpacity(0.15)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: isToday
                  ? Border.all(color: Color(int.parse(primaryColor.replaceFirst('#', '0xFF'))), width: 2)
                  : null,
              boxShadow: isToday
                  ? [
                      BoxShadow(
                        color: Color(int.parse(primaryColor.replaceFirst('#', '0xFF'))).withOpacity(0.3),
                        blurRadius: 12,
                      ),
                    ]
                  : null,
            ),
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'][i],
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isActive || isToday
                        ? Color(int.parse(primaryColor.replaceFirst('#', '0xFF')))
                        : Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${date.day}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isActive || isToday
                        ? Color(int.parse(primaryColor.replaceFirst('#', '0xFF')))
                        : Colors.white,
                  ),
                ),
                if (hasWorkout)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Color(int.parse(primaryColor.replaceFirst('#', '0xFF'))),
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.orange),
          onPressed: () {
            setState(() {
              _weekOffset -= 1;
              final baseMonday2 = _getMonday(_today).add(Duration(days: _weekOffset * 7));
              for (int i = 0; i < 7; i++) {
                _applyTemplates(baseMonday2.add(Duration(days: i)));
              }
            });
          },
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: children,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right, color: Colors.orange),
          onPressed: () {
            setState(() {
              _weekOffset += 1;
              final baseMonday2 = _getMonday(_today).add(Duration(days: _weekOffset * 7));
              for (int i = 0; i < 7; i++) {
                _applyTemplates(baseMonday2.add(Duration(days: i)));
              }
            });
          },
        ),
      ],
    );
  }

  // ===== СПИСОК УПРАЖНЕНИЙ =====
  Widget _buildWorkoutList() {
    final list = _getWorkoutsForDate(_selectedDate);
    if (list.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Text('Нет упражнений за этот день', style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: list.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
      itemBuilder: (ctx, index) {
        final w = list[index];
        final detail = '${w.sets}×${w.reps}' +
            (w.weight != null && w.weight != 'проходка' ? ' @ ${w.weight} кг' : '');
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          title: Text(
            w.exercise,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            detail,
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (w.isProhodka)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '🏆 проходка',
                    style: TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.w600),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.edit, color: Colors.orange, size: 20),
                onPressed: () => _showEditModal(w),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                onPressed: () => _deleteWorkout(w.id),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        );
      },
    );
  }

  // ===== ДОБАВЛЕНИЕ =====
  void _showAddModal() {
    final nameCtrl = TextEditingController();
    final setsCtrl = TextEditingController();
    final repsCtrl = TextEditingController();
    final weightCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateModal) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1A120A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              title: const Text('➕ Добавить упражнение', style: TextStyle(color: Colors.orange)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RawAutocomplete<String>(
                    textEditingController: nameCtrl,
                    optionsBuilder: (TextEditingValue value) {
                      if (value.text.isEmpty) return const Iterable<String>.empty();
                      return _exerciseBase.where((ex) =>
                          ex.toLowerCase().contains(value.text.toLowerCase()));
                    },
                    onSelected: (String selection) {
                      nameCtrl.text = selection;
                    },
                    fieldViewBuilder: (context, ctrl, focusNode, onFieldSubmitted) {
                      return TextField(
                        controller: ctrl,
                        focusNode: focusNode,
                        decoration: const InputDecoration(
                          labelText: 'Название',
                          labelStyle: TextStyle(color: Colors.grey),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.orange),
                          ),
                        ),
                        style: const TextStyle(color: Colors.white),
                      );
                    },
                    optionsViewBuilder: (context, onSelected, options) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          color: const Color(0xFF2A1A0A),
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            height: 120,
                            child: ListView.builder(
                              itemCount: options.length,
                              itemBuilder: (ctx, i) {
                                final option = options.elementAt(i);
                                return ListTile(
                                  title: Text(option, style: const TextStyle(color: Colors.white)),
                                  onTap: () => onSelected(option),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: setsCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Подходы',
                      labelStyle: TextStyle(color: Colors.grey),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.orange)),
                    ),
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: repsCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Повторы',
                      labelStyle: TextStyle(color: Colors.grey),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.orange)),
                    ),
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: weightCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Вес (кг) – необязательно',
                      labelStyle: TextStyle(color: Colors.grey),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.orange)),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Если вес не указан, он не будет отображаться',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: () {
                    final name = nameCtrl.text.trim();
                    final sets = int.tryParse(setsCtrl.text);
                    final reps = int.tryParse(repsCtrl.text);
                    final weight = weightCtrl.text.trim();

                    if (name.isEmpty || sets == null || reps == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Заполните все поля корректно')),
                      );
                      return;
                    }

                    if (!_exerciseBase.contains(name)) {
                      _exerciseBase.add(name);
                      _saveLocalData();
                    }

                    final dayKey = 'day_${_selectedDate.weekday}';
                    if (!_templates.containsKey(dayKey)) {
                      _templates[dayKey] = [];
                    }
                    final templateExists = _templates[dayKey]!.any((t) =>
                        t['exercise'] == name &&
                        t['sets'] == sets &&
                        t['reps'] == reps &&
                        t['weight'] == (weight.isNotEmpty ? double.parse(weight) : null));
                    if (!templateExists) {
                      _templates[dayKey]!.add({
                        'exercise': name,
                        'sets': sets,
                        'reps': reps,
                        'weight': weight.isNotEmpty ? double.parse(weight) : null,
                      });
                      _saveLocalData();
                    }

                    final newWorkout = Workout(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      date: _formatDate(_selectedDate),
                      exercise: name,
                      sets: sets,
                      reps: reps,
                      weight: weight.isNotEmpty ? double.parse(weight) : null,
                      isProhodka: false,
                      weekNumber: _getWeekNumber(_selectedDate),
                    );
                    widget.onAddWorkout(newWorkout);
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.black,
                  ),
                  child: const Text('Сохранить'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ===== РЕДАКТИРОВАНИЕ =====
  void _showEditModal(Workout workout) {
    final nameCtrl = TextEditingController(text: workout.exercise);
    final setsCtrl = TextEditingController(text: workout.sets.toString());
    final repsCtrl = TextEditingController(text: workout.reps.toString());
    final weightCtrl = TextEditingController(
      text: (workout.weight != null && workout.weight != 'проходка') ? workout.weight.toString() : '',
    );

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A120A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          title: const Text('✎ Редактировать', style: TextStyle(color: Colors.orange)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Название',
                  labelStyle: TextStyle(color: Colors.grey),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.orange)),
                ),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: setsCtrl,
                decoration: const InputDecoration(
                  labelText: 'Подходы',
                  labelStyle: TextStyle(color: Colors.grey),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.orange)),
                ),
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: repsCtrl,
                decoration: const InputDecoration(
                  labelText: 'Повторы',
                  labelStyle: TextStyle(color: Colors.grey),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.orange)),
                ),
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: weightCtrl,
                decoration: const InputDecoration(
                  labelText: 'Вес (кг) – необязательно',
                  labelStyle: TextStyle(color: Colors.grey),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.orange)),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                final sets = int.tryParse(setsCtrl.text);
                final reps = int.tryParse(repsCtrl.text);
                final weight = weightCtrl.text.trim();

                if (name.isEmpty || sets == null || reps == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Заполните все поля корректно')),
                  );
                  return;
                }

                final updated = Workout(
                  id: workout.id,
                  date: workout.date,
                  exercise: name,
                  sets: sets,
                  reps: reps,
                  weight: weight.isNotEmpty ? double.parse(weight) : null,
                  isProhodka: false,
                  weekNumber: workout.weekNumber,
                );
                widget.onUpdateWorkout(updated);
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.black,
              ),
              child: const Text('Сохранить'),
            ),
          ],
        );
      },
    );
  }

  // ===== УДАЛЕНИЕ =====
  void _deleteWorkout(String id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A120A),
        title: const Text('Удалить упражнение?'),
        content: const Text('Это действие нельзя отменить.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              widget.onDeleteWorkout(id);
              Navigator.pop(ctx);
            },
            child: const Text('Удалить', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  // ===== BUILD =====
  @override
  Widget build(BuildContext context) {
    final colors = widget.config['colors'] ?? {};
    final primaryColor = colors['primary'] ?? '#FF9800';
    final bgColor = colors['background'] ?? '#0A0A0A';

    return Container(
      color: Color(int.parse(bgColor.replaceFirst('#', '0xFF'))),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '📅 План',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(int.parse(primaryColor.replaceFirst('#', '0xFF'))),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add, color: Colors.orange),
                  onPressed: _showAddModal,
                  tooltip: 'Добавить упражнение',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _buildCalendar(),
          ),
          const Divider(height: 16, color: Colors.white10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _buildWorkoutList(),
            ),
          ),
        ],
      ),
    );
  }
}