class AppUser {
  final String email;
  String name;
  int weight;
  double? height;
  String? gender;
  int? pushupGoal;
  String? timezone; // ← НОВОЕ (Europe/Moscow)
  List<int> trainingDays;
  final DateTime createdAt;

  AppUser({
    required this.email,
    required this.name,
    required this.weight,
    this.height,
    this.gender,
    this.pushupGoal,
    this.timezone,
    required this.trainingDays,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'email': email,
        'name': name,
        'weight': weight,
        'height': height,
        'gender': gender,
        'pushup_goal': pushupGoal,
        'timezone': timezone,
        'training_days': trainingDays.join(','),
        'created_at': createdAt.toIso8601String(),
      };

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        email: json['email'] ?? '',
        name: json['name'] ?? 'Пользователь',
        weight: json['weight'] is int
            ? json['weight']
            : (json['weight'] is String
                ? int.tryParse(json['weight']) ?? 75
                : 75),
        height: json['height'] != null
            ? double.tryParse(json['height'].toString())
            : null,
        gender: json['gender']?.toString(),
        pushupGoal: json['pushup_goal'] != null
            ? int.tryParse(json['pushup_goal'].toString())
            : null,
        timezone: json['timezone']?.toString(),
        trainingDays: (json['training_days'] is String)
            ? (json['training_days'] as String)
                .split(',')
                .where((s) => s.trim().isNotEmpty)
                .map((s) => int.tryParse(s.trim()) ?? 0)
                .where((i) => i > 0)
                .toList()
            : [1, 3, 5],
        createdAt: json['created_at'] != null
            ? DateTime.tryParse(json['created_at'].toString()) ??
                DateTime.now()
            : DateTime.now(),
      );

  AppUser copyWith({
    String? name,
    int? weight,
    double? height,
    String? gender,
    int? pushupGoal,
    String? timezone,
    List<int>? trainingDays,
    DateTime? createdAt,
  }) {
    return AppUser(
      email: this.email,
      name: name ?? this.name,
      weight: weight ?? this.weight,
      height: height ?? this.height,
      gender: gender ?? this.gender,
      pushupGoal: pushupGoal ?? this.pushupGoal,
      timezone: timezone ?? this.timezone,
      trainingDays: trainingDays ?? this.trainingDays,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}