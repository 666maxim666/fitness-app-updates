import 'package:flutter/material.dart';
import '../models/workout.dart';

class PlanTab extends StatelessWidget {
  final List<Workout> workouts;
  final Function(Workout) onAddWorkout;
  final Map<String, dynamic> config;

  const PlanTab({
    super.key,
    required this.workouts,
    required this.onAddWorkout,
    this.config = const {},
  });

  @override
  Widget build(BuildContext context) {
    final texts = config['texts'] ?? {};
    final colors = config['colors'] ?? {};
    final buttons = config['buttons'] ?? {};
    final calendar = config['calendar'] ?? {};

    final primaryColor = colors['primary'] ?? '#FF9800';
    final textColor = colors['text'] ?? '#FFFFFF';
    final bgColor = colors['background'] ?? '#0A0A0A';

    final buttonHeight = (buttons['height'] ?? 48).toDouble();
    final buttonRadius = (buttons['borderRadius'] ?? 12).toDouble();
    final buttonFontSize = (buttons['fontSize'] ?? 14).toDouble();

    final planTitle = texts['planTab'] ?? '📅 План тренировок';
    final addButtonText = texts['addExercise'] ?? '+ Добавить упражнение';

    final daySize = (calendar['daySize'] ?? 52).toDouble();
    final dayRadius = (calendar['dayRadius'] ?? 14).toDouble();
    final dayFontSize = (calendar['fontSize'] ?? 18).toDouble();
    final activeColor = calendar['activeColor'] ?? '#FF9800';

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            planTitle,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(int.parse(textColor.replaceFirst('#', '0xFF'))),
            ),
          ),
          const SizedBox(height: 16),
          // Календарь (заглушка, потом заменим на реальный)
          Container(
            height: 80,
            decoration: BoxDecoration(
              color: Color(int.parse(bgColor.replaceFirst('#', '0xFF'))).withOpacity(0.3),
              borderRadius: BorderRadius.circular(dayRadius),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(7, (i) {
                final isActive = i == 2;
                return Container(
                  width: daySize,
                  height: daySize,
                  decoration: BoxDecoration(
                    color: isActive
                        ? Color(int.parse(activeColor.replaceFirst('#', '0xFF'))).withOpacity(0.2)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(dayRadius),
                    border: Border.all(
                      color: isActive
                          ? Color(int.parse(activeColor.replaceFirst('#', '0xFF')))
                          : Colors.grey.withOpacity(0.2),
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'][i],
                        style: TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                      Text(
                        '${10 + i}',
                        style: TextStyle(
                          fontSize: dayFontSize,
                          fontWeight: FontWeight.bold,
                          color: isActive
                              ? Color(int.parse(activeColor.replaceFirst('#', '0xFF')))
                              : Colors.white,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: workouts.isEmpty
                ? Center(
                    child: Text(
                      'Нет тренировок',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: workouts.length,
                    itemBuilder: (ctx, i) => ListTile(
                      title: Text(
                        workouts[i].exercise,
                        style: TextStyle(color: Color(int.parse(textColor.replaceFirst('#', '0xFF')))),
                      ),
                      subtitle: Text(
                        '${workouts[i].sets}×${workouts[i].reps} @ ${workouts[i].weight} кг',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
          ),
          ElevatedButton(
            onPressed: () {
              // Новая логика с проходками
              final now = DateTime.now();
              final isProhodka = Workout.isProhodkaWeek(now);
              final weight = isProhodka ? 'проходка' : 80;
              onAddWorkout(Workout(
                id: DateTime.now().toString(),
                date: now,
                exercise: 'Жим лёжа',
                sets: 5,
                reps: 5,
                weight: weight,
                isProhodka: isProhodka,
                weekNumber: Workout.getWeekNumber(now),
              ));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(int.parse(primaryColor.replaceFirst('#', '0xFF'))),
              minimumSize: Size(double.infinity, buttonHeight),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(buttonRadius)),
              textStyle: TextStyle(fontSize: buttonFontSize, fontWeight: FontWeight.w600),
            ),
            child: Text(addButtonText, style: const TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }
}