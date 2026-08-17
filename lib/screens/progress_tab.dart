import 'package:flutter/material.dart';
import '../models/workout.dart';

class ProgressTab extends StatelessWidget {
  final List<Workout> workouts;
  final Map<String, dynamic> config;

  const ProgressTab({super.key, required this.workouts, this.config = const {}});

  @override
  Widget build(BuildContext context) {
    final colors = config['colors'] ?? {};
    final texts = config['texts'] ?? {};
    final textColor = colors['text'] ?? '#FFFFFF';
    final primaryColor = colors['primary'] ?? '#FF9800';

    final totalWorkouts = workouts.length;
    final totalSets = workouts.fold<int>(0, (sum, w) => sum + w.sets);
    final totalVolume = workouts.fold<double>(
      0,
      (sum, w) => sum + (w.sets * w.reps * (w.weight is num ? w.weight : 0)),
    );

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '📊 Прогресс',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(int.parse(textColor.replaceFirst('#', '0xFF'))),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _StatCard(label: 'Тренировок', value: '$totalWorkouts', primaryColor: primaryColor),
              const SizedBox(width: 12),
              _StatCard(label: 'Подходов', value: '$totalSets', primaryColor: primaryColor),
              const SizedBox(width: 12),
              _StatCard(label: 'Объём, кг', value: '${totalVolume.toInt()}', primaryColor: primaryColor),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'История упражнений',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(int.parse(textColor.replaceFirst('#', '0xFF'))),
            ),
          ),
          const SizedBox(height: 8),
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
                    itemBuilder: (ctx, i) {
                      final w = workouts[i];
                      return ListTile(
                        title: Text(
                          w.exercise,
                          style: TextStyle(color: Color(int.parse(textColor.replaceFirst('#', '0xFF')))),
                        ),
                        subtitle: Text(
                          '${w.sets}×${w.reps} @ ${w.weight} кг',
                          style: const TextStyle(color: Colors.grey),
                        ),
                        trailing: Text(
                          w.date.toLocal().toString().split(' ')[0],
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String primaryColor;

  const _StatCard({required this.label, required this.value, required this.primaryColor});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Color(int.parse(primaryColor.replaceFirst('#', '0xFF'))).withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Color(int.parse(primaryColor.replaceFirst('#', '0xFF'))).withOpacity(0.3),
          ),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(int.parse(primaryColor.replaceFirst('#', '0xFF'))),
              ),
            ),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}