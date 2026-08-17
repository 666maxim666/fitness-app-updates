import 'package:flutter/material.dart';
import '../models/user.dart';

class ProfileTab extends StatelessWidget {
  final AppUser? user;
  final Function(AppUser) onUpdate;
  final Map<String, dynamic> config;

  const ProfileTab({
    super.key,
    this.user,
    required this.onUpdate,
    this.config = const {},
  });

  @override
  Widget build(BuildContext context) {
    final colors = config['colors'] ?? {};
    final texts = config['texts'] ?? {};
    final profile = config['profile'] ?? {};

    final textColor = colors['text'] ?? '#FFFFFF';
    final primaryColor = colors['primary'] ?? '#FF9800';
    final surfaceColor = colors['surface'] ?? '#1A120A';

    final profileTitle = texts['profileTab'] ?? '👤 Профиль';

    if (user == null) {
      return Center(
        child: Text(
          'Пользователь не загружен',
          style: TextStyle(color: Color(int.parse(textColor.replaceFirst('#', '0xFF')))),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            profileTitle,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(int.parse(textColor.replaceFirst('#', '0xFF'))),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Color(int.parse(surfaceColor.replaceFirst('#', '0xFF'))).withOpacity(0.6),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Color(int.parse(primaryColor.replaceFirst('#', '0xFF'))).withOpacity(0.2),
              ),
            ),
            child: Column(
              children: [
                _infoRow('Email', user!.email, textColor),
                _infoRow('Имя', user!.name, textColor),
                _infoRow('Вес', '${user!.weight} кг', textColor),
                _infoRow('Дни тренировок', user!.trainingDays.join(', '), textColor),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              final updated = AppUser(
                email: user!.email,
                name: 'Новое имя',
                weight: 80,
                trainingDays: user!.trainingDays,
                createdAt: user!.createdAt,
              );
              onUpdate(updated);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(int.parse(primaryColor.replaceFirst('#', '0xFF'))),
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Обновить профиль', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, String textColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Color(int.parse(textColor.replaceFirst('#', '0xFF'))),
            ),
          ),
        ],
      ),
    );
  }
}