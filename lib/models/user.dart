class AppUser {
  final String email;
  String name;
  int weight;
  List<int> trainingDays;
  final DateTime createdAt;

  AppUser({
    required this.email,
    required this.name,
    required this.weight,
    required this.trainingDays,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'email': email,
        'name': name,
        'weight': weight,
        'training_days': trainingDays.join(','),
        'created_at': createdAt.toIso8601String(),
      };

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        email: json['email'],
        name: json['name'],
        weight: json['weight'],
        trainingDays: (json['training_days'] as String).split(',').map(int.parse).toList(),
        createdAt: DateTime.parse(json['created_at']),
      );
}