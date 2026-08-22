class Workout {
  final String id;
  final String date;
  final String exercise;
  final int sets;
  final int reps;
  final double? weight; // null = проходка
  final bool isProhodka;
  final int weekNumber;

  Workout({
    required this.id,
    required this.date,
    required this.exercise,
    required this.sets,
    required this.reps,
    this.weight,
    this.isProhodka = false,
    required this.weekNumber,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date,
    'exercise': exercise,
    'sets': sets,
    'reps': reps,
    'weight': weight,
    'isProhodka': isProhodka,
    'weekNumber': weekNumber,
  };

  factory Workout.fromJson(Map<String, dynamic> json) => Workout(
    id: json['id'],
    date: json['date'],
    exercise: json['exercise'],
    sets: json['sets'],
    reps: json['reps'],
    weight: json['weight'] as double?,
    isProhodka: json['isProhodka'] ?? false,
    weekNumber: json['weekNumber'] ?? 1,
  );
}