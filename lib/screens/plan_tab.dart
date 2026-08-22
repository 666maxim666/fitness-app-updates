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
  final List<int> trainingDays;
  final DateTime selectedDate;

  const PlanTab({
    super.key,
    required this.workouts,
    required this.onAddWorkout,
    required this.onUpdateWorkout,
    required this.onDeleteWorkout,
    this.config = const {},
    this.trainingDays = const [1, 3, 5],
    required this.selectedDate,
  });

  @override
  State<PlanTab> createState() => _PlanTabState();
}

class _PlanTabState extends State<PlanTab> {
  late DateTime _currentDate;
  late DateTime _today;
  int _weekOffset = 0;
  int _prohodkaShiftWeeks = 0;

  Map<String, List<Map<String, dynamic>>> _templates = {};
  List<String> _exerciseBase = [];
  Set<String> _restDays = {};

  @override
  void initState() {
    super.initState();
    _today = DateTime.now();
    _currentDate = widget.selectedDate;
    _loadLocalData();
    _loadRestDays();
    _loadProhodkaShift();
  }

  @override
  void didUpdateWidget(PlanTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedDate != oldWidget.selectedDate) {
      setState(() {
        _currentDate = widget.selectedDate;
      });
    }
  }

  // ===== ЗАГРУЗКА ДАННЫХ =====
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

  Future<void> _loadRestDays() async {
    final prefs = await SharedPreferences.getInstance();
    final restStr = prefs.getString('rest_days');
    if (restStr != null) {
      _restDays = Set<String>.from(jsonDecode(restStr) as List);
    }
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

  // ===== ВСПОМОГАТЕЛЬНЫЕ =====
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

  bool _isRestDay(DateTime date) {
    return _restDays.contains(_formatDate(date));
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

  // ===== ПЕРЕСЧЁТ БУДУЩИХ ПРОХОДОК =====
  Future<void> _recalculateFutureProhodka() async {
    final now = DateTime.now();
    for (final w in List<Workout>.from(widget.workouts)) {
      final date = DateTime.tryParse(w.date);
      if (date == null) continue;
      if (!date.isAfter(now)) continue; // трогаем только будущие дни

      final dayKey = 'day_${date.weekday}';
      final templates = _templates[dayKey];
      if (templates == null) continue;

      // ищем шаблон, из которого эта тренировка была сгенерирована
      final matchingTemplate = templates.firstWhere(
        (t) => t['exercise'] == w.exercise && t['sets'] == w.sets && t['reps'] == w.reps,
        orElse: () => {},
      );
      if (matchingTemplate.isEmpty) continue;

      final weekNum = _getWeekNumber(date);
      final adjustedWeek = weekNum - _prohodkaShiftWeeks;
      final newIsProhodka = adjustedWeek > 0 && adjustedWeek % 3 == 0;

      if (newIsProhodka != w.isProhodka) {
        final updated = Workout(
          id: w.id,
          date: w.date,
          exercise: w.exercise,
          sets: w.sets,
          reps: w.reps,
          weight: newIsProhodka ? null : (matchingTemplate['weight'] as num?)?.toDouble(),
          isProhodka: newIsProhodka,
          weekNumber: weekNum,
        );
        widget.onUpdateWorkout(updated);
      }
    }
  }

  // ===== КАЛЕНДАРЬ =====
  Widget _buildCalendar() {
    final colors = widget.config['colors'] ?? {};
    final primaryColor = colors['primary'] ?? '#FF9800';
    final baseMonday = _getMonday(_today).add(Duration(days: _weekOffset * 7));

    final children = <Widget>[];
    for (int i = 0; i < 7; i++) {
      final date = baseMonday.add(Duration(days: i));
      final isToday = _isSameDay(date, _today);
      final isActive = _isSameDay(date, _currentDate);
      final hasWorkout = _getWorkoutsForDate(date).isNotEmpty;
      final isTrainingDay = widget.trainingDays.contains(date.weekday);
      final isRest = _isRestDay(date);

      children.add(
        GestureDetector(
          onTap: () {
            setState(() {
              _currentDate = date;
            });
            if (!isRest) {
              _applyTemplates(date);
            }
          },
          child: Container(
            decoration: BoxDecoration(
              color: isRest
                  ? Colors.grey[800]!.withOpacity(0.3)
                  : isActive
                      ? Color(int.parse(primaryColor.replaceFirst('#', '0xFF'))).withOpacity(0.35)
                      : isToday
                          ? Color(int.parse(primaryColor.replaceFirst('#', '0xFF'))).withOpacity(0.2)
                          : isTrainingDay
                              ? Color(int.parse(primaryColor.replaceFirst('#', '0xFF'))).withOpacity(0.1)
                              : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: isToday
                  ? Border.all(color: Color(int.parse(primaryColor.replaceFirst('#', '0xFF'))), width: 2)
                  : isActive
                      ? Border.all(color: Color(int.parse(primaryColor.replaceFirst('#', '0xFF'))), width: 1)
                      : null,
              boxShadow: isToday
                  ? [BoxShadow(color: Color(int.parse(primaryColor.replaceFirst('#', '0xFF'))).withOpacity(0.3), blurRadius: 12)]
                  : null,
            ),
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'][i],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isRest
                        ? Colors.grey[600]
                        : isActive || isToday
                            ? Color(int.parse(primaryColor.replaceFirst('#', '0xFF')))
                            : isTrainingDay
                                ? Colors.white70
                                : Colors.grey[500],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${date.day}',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: isRest
                        ? Colors.grey[600]
                        : isActive || isToday
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
                      color: isRest ? Colors.grey[600] : Color(int.parse(primaryColor.replaceFirst('#', '0xFF'))),
                      shape: BoxShape.circle,
                    ),
                  ),
                if (isRest)
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.block, color: Colors.grey, size: 12),
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
          icon: const Icon(Icons.chevron_left, color: Colors.orange, size: 28),
          onPressed: () {
            setState(() {
              _weekOffset -= 1;
              final newMonday = _getMonday(_today).add(Duration(days: _weekOffset * 7));
              for (int i = 0; i < 7; i++) {
                _applyTemplates(newMonday.add(Duration(days: i)));
              }
            });
          },
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: children.map((child) => Expanded(child: child)).toList(),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right, color: Colors.orange, size: 28),
          onPressed: () {
            setState(() {
              _weekOffset += 1;
              final newMonday = _getMonday(_today).add(Duration(days: _weekOffset * 7));
              for (int i = 0; i < 7; i++) {
                _applyTemplates(newMonday.add(Duration(days: i)));
              }
            });
          },
        ),
      ],
    );
  }

  // ===== СПИСОК УПРАЖНЕНИЙ =====
  Widget _buildWorkoutList() {
    final list = _getWorkoutsForDate(_currentDate);
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
        final isProhodka = w.isProhodka;
        final detail = '${w.sets}×${w.reps}' +
            (w.weight != null ? ' @ ${w.weight} кг' : '');
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
              if (isProhodka)
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
              IconButton(
                icon: const Icon(Icons.more_vert, color: Colors.grey, size: 20),
                onPressed: () => _showExtendCycleDialog(w),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        );
      },
    );
  }

  // ===== ДИАЛОГ ПРОДЛЕНИЯ ЦИКЛА =====
  void _showExtendCycleDialog(Workout workout) {
    final controller = TextEditingController(text: '1');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A120A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: const Text('Отложить проходку', style: TextStyle(color: Colors.orange)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('На сколько недель отложить проходку?', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: '1',
                hintStyle: TextStyle(color: Colors.grey),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.orange)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              final weeks = int.tryParse(controller.text) ?? 1;
              if (weeks < 1) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Введите число больше 0')),
                );
                return;
              }
              setState(() {
                _prohodkaShiftWeeks += weeks;
              });
              await _saveProhodkaShift();
              await _recalculateFutureProhodka(); // пересчёт будущих тренировок
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Проходка отложена на $weeks нед.')),
              );
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.black,
            ),
            child: const Text('Отложить'),
          ),
        ],
      ),
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

                    final dayKey = 'day_${_currentDate.weekday}';
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
                      date: _formatDate(_currentDate),
                      exercise: name,
                      sets: sets,
                      reps: reps,
                      weight: weight.isNotEmpty ? double.parse(weight) : null,
                      isProhodka: false,
                      weekNumber: _getWeekNumber(_currentDate),
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
      text: workout.weight != null ? workout.weight.toString() : '',
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

  // ===== ТОГГЛ ВЫХОДНОГО ДНЯ =====
  void _toggleRestDay() {
    final dateStr = _formatDate(_currentDate);
    setState(() {
      if (_restDays.contains(dateStr)) {
        _restDays.remove(dateStr);
      } else {
        _restDays.add(dateStr);
        final toRemove = widget.workouts.where((w) => w.date == dateStr).toList();
        for (var w in toRemove) {
          widget.onDeleteWorkout(w.id);
        }
      }
    });
    _saveRestDays();
  }

  // ===== BUILD =====
  @override
  Widget build(BuildContext context) {
    final colors = widget.config['colors'] ?? {};
    final primaryColor = colors['primary'] ?? '#FF9800';
    final bgColor = colors['background'] ?? '#0A0A0A';
    final isRest = _isRestDay(_currentDate);

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
                Row(
                  children: [
                    IconButton(
                      icon: Icon(isRest ? Icons.check_circle : Icons.block,
                          color: isRest ? Colors.green : Colors.grey),
                      onPressed: _toggleRestDay,
                      tooltip: isRest ? 'Отменить выходной' : 'Отметить выходной',
                    ),
                    IconButton(
                      icon: const Icon(Icons.add, color: Colors.orange),
                      onPressed: _showAddModal,
                      tooltip: 'Добавить упражнение',
                    ),
                  ],
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