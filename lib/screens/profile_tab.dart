import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
// import 'package:share_plus/share_plus.dart';   // временно отключено
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import '../models/user.dart';
import '../models/workout.dart';

class ProfileTab extends StatefulWidget {
  final AppUser? user;
  final Function(AppUser) onUpdate;
  final Map<String, dynamic> config;
  final List<Workout> workouts;

  const ProfileTab({
    super.key,
    this.user,
    required this.onUpdate,
    this.config = const {},
    this.workouts = const [],
  });

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  String? _avatarPath;
  final ImagePicker _picker = ImagePicker();

  int get totalWorkouts => widget.workouts.length;
  int get streakDays {
    if (totalWorkouts == 0) return 0;
    final dates = widget.workouts.map((w) => w.date).toList();
    dates.sort((a, b) => b.compareTo(a));
    int streak = 1;
    for (int i = 1; i < dates.length; i++) {
      final prev = DateTime.parse(dates[i - 1]);
      final curr = DateTime.parse(dates[i]);
      final diff = prev.difference(curr).inDays;
      if (diff == 1) {
        streak++;
      } else if (diff > 1) {
        break;
      }
    }
    return streak;
  }

  @override
  void initState() {
    super.initState();
    _loadAvatar();
  }

  void _loadAvatar() async {
    if (widget.user != null) {
      final appDir = await getApplicationDocumentsDirectory();
      final path = '${appDir.path}/avatar_${widget.user!.email}.png';
      if (File(path).existsSync()) {
        setState(() {
          _avatarPath = path;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.config['colors'] ?? {};
    final primaryColor = colors['primary'] ?? '#FF9800';
    final textColor = colors['text'] ?? '#FFFFFF';

    if (widget.user == null) {
      return Center(
        child: Text('Пользователь не загружен', style: TextStyle(color: Color(int.parse(textColor.replaceFirst('#', '0xFF'))))),
      );
    }

    final user = widget.user!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('👤 Профиль', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Color(int.parse(primaryColor.replaceFirst('#', '0xFF'))).withOpacity(0.08)),
            ),
            child: Row(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: Color(int.parse(primaryColor.replaceFirst('#', '0xFF'))).withOpacity(0.15),
                      backgroundImage: _avatarPath != null ? FileImage(File(_avatarPath!)) : null,
                      child: _avatarPath == null ? const Icon(Icons.person, size: 32, color: Colors.white70) : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: _pickAvatar,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Color(int.parse(primaryColor.replaceFirst('#', '0xFF'))),
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(4),
                          child: const Icon(Icons.camera_alt, size: 16, color: Colors.black),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
                      Text(user.email, style: const TextStyle(fontSize: 14, color: Colors.grey)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text('🏋️ ', style: TextStyle(color: Color(int.parse(primaryColor.replaceFirst('#', '0xFF'))))),
                          Text('$totalWorkouts', style: TextStyle(fontWeight: FontWeight.w700, color: Color(int.parse(primaryColor.replaceFirst('#', '0xFF'))))),
                          const Text(' тренировок', style: TextStyle(color: Colors.grey, fontSize: 12)),
                          const SizedBox(width: 16),
                          Text('🔥 ', style: TextStyle(color: Color(int.parse(primaryColor.replaceFirst('#', '0xFF'))))),
                          Text('$streakDays', style: TextStyle(fontWeight: FontWeight.w700, color: Color(int.parse(primaryColor.replaceFirst('#', '0xFF'))))),
                          const Text(' дней подряд', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(0.04)),
            ),
            child: Column(
              children: [
                _buildProfileField('📧', 'Email', user.email, isEditable: false),
                _buildProfileField('👤', 'Имя', user.name, onSave: (val) {
                  final updated = AppUser(
                    email: user.email,
                    name: val,
                    weight: user.weight,
                    trainingDays: user.trainingDays,
                    createdAt: user.createdAt,
                  );
                  widget.onUpdate(updated);
                }),
                _buildProfileField('⚖️', 'Вес (кг)', user.weight.toString(), onSave: (val) {
                  final updated = AppUser(
                    email: user.email,
                    name: user.name,
                    weight: double.tryParse(val)?.round() ?? user.weight,
                    trainingDays: user.trainingDays,
                    createdAt: user.createdAt,
                  );
                  widget.onUpdate(updated);
                }),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text('📅 Дни тренировок', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white70)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: List.generate(7, (index) {
              final day = index + 1;
              final isActive = user.trainingDays.contains(day);
              return GestureDetector(
                onTap: () {
                  final newDays = List<int>.from(user.trainingDays);
                  if (newDays.contains(day)) newDays.remove(day);
                  else newDays.add(day);
                  newDays.sort();
                  final updated = AppUser(
                    email: user.email,
                    name: user.name,
                    weight: user.weight,
                    trainingDays: newDays,
                    createdAt: user.createdAt,
                  );
                  widget.onUpdate(updated);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isActive ? Color(int.parse(primaryColor.replaceFirst('#', '0xFF'))).withOpacity(0.2) : Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: isActive ? Color(int.parse(primaryColor.replaceFirst('#', '0xFF'))) : Colors.white.withOpacity(0.06)),
                  ),
                  child: Text(
                    ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'][index],
                    style: TextStyle(
                      color: isActive ? Color(int.parse(primaryColor.replaceFirst('#', '0xFF'))) : Colors.grey,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _exportData,
              icon: const Icon(Icons.download, color: Colors.black),
              label: const Text('📥 Экспортировать данные', style: TextStyle(color: Colors.black)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(int.parse(primaryColor.replaceFirst('#', '0xFF'))),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Выход'),
                    content: const Text('Вы уверены, что хотите выйти?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Выход выполнен')),
                          );
                        },
                        child: const Text('Выйти', style: TextStyle(color: Colors.redAccent)),
                      ),
                    ],
                  ),
                );
              },
              icon: const Icon(Icons.logout, color: Colors.redAccent),
              label: const Text('🚪 Выйти из аккаунта', style: TextStyle(color: Colors.redAccent)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.redAccent, width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileField(String icon, String label, String value, {bool isEditable = true, Function(String)? onSave}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Text('$icon ', style: const TextStyle(fontSize: 16)),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
          const Spacer(),
          if (!isEditable)
            Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14))
          else
            GestureDetector(
              onTap: () => _showEditDialog(label, value, onSave),
              child: Text(
                value,
                style: TextStyle(
                  color: Color(int.parse(widget.config['colors']?['primary'] ?? '#FF9800'.replaceFirst('#', '0xFF'))),
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showEditDialog(String label, String currentValue, Function(String)? onSave) {
    final controller = TextEditingController(text: currentValue);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A120A),
        title: Text('Редактировать $label', style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: label,
            hintStyle: const TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(int.parse(widget.config['colors']?['primary'] ?? '#FF9800'.replaceFirst('#', '0xFF')))),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена', style: TextStyle(color: Colors.grey))),
          TextButton(
            onPressed: () {
              if (onSave != null) onSave(controller.text.trim());
              Navigator.pop(ctx);
            },
            child: Text('Сохранить', style: TextStyle(color: Color(int.parse(widget.config['colors']?['primary'] ?? '#FF9800'.replaceFirst('#', '0xFF'))))),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAvatar() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        final appDir = await getApplicationDocumentsDirectory();
        final path = '${appDir.path}/avatar_${widget.user!.email}.png';
        final file = File(image.path);
        await file.copy(path);
        setState(() { _avatarPath = path; });
      }
    } catch (e) {
      print('Ошибка загрузки аватара: $e');
    }
  }

  Future<void> _exportData() async {
    try {
      final data = {
        'user': widget.user?.toJson(),
        'workouts': widget.workouts.map((w) => w.toJson()).toList(),
        'export_date': DateTime.now().toIso8601String(),
      };
      final jsonString = jsonEncode(data);
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/gym_data_${DateTime.now().millisecondsSinceEpoch}.json');
      await file.writeAsString(jsonString);
      // временно отключено:
      // await Share.shareXFiles([XFile(file.path)], text: '📊 Мои данные тренировок');
      print('📊 Данные экспортированы: ${file.path}');
      // Можно показать SnackBar, что файл создан
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Данные сохранены в временной папке')),
        );
      }
    } catch (e) {
      print('Ошибка экспорта: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось экспортировать данные')),
        );
      }
    }
  }
}