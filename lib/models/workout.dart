class Workout {
  final String id;
  final DateTime date;
  final String exercise;
  final int sets;
  final int reps;
  final dynamic weight; // число или 'проходка'
  final bool isProhodka;
  final int weekNumber;

  Workout({
    required this.id,
    required this.date,
    required this.exercise,
    required this.sets,
    required this.reps,
    required this.weight,
    this.isProhodka = false,
    required this.weekNumber,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'exercise': exercise,
        'sets': sets,
        'reps': reps,
        'weight': weight,
        'isProhodka': isProhodka,
        'weekNumber': weekNumber,
      };

  factory Workout.fromJson(Map<String, dynamic> json) => Workout(
        id: json['id'],
        date: DateTime.parse(json['date']),
        exercise: json['exercise'],
        sets: json['sets'],
        reps: json['reps'],
        weight: json['weight'],
        isProhodka: json['isProhodka'] ?? false,
        weekNumber: json['weekNumber'] ?? 1,
      );

  // ----- НОВЫЕ МЕТОДЫ ДЛЯ ПРОХОДОК -----
  static int getWeekNumber(DateTime date) {
    final start = DateTime(date.year, 1, 1);
    final diff = date.difference(start).inDays;
    return (diff / 7).floor() + 1;
  }

  static bool isProhodkaWeek(DateTime date) {
    return getWeekNumber(date) % 3 == 0; // каждая 3-я неделя
  }
}