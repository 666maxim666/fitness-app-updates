import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../models/user.dart';
import '../services/ai_import_service.dart';

class ProfileTab extends StatefulWidget {
  final AppUser user;
  final Function(AppUser) onUpdate;
  final Map<String, dynamic> config;

  const ProfileTab({
    super.key,
    required this.user,
    required this.onUpdate,
    this.config = const {},
  });

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  late TextEditingController _nameController;
  late TextEditingController _weightController;
  late TextEditingController _heightController;
  late String _gender;
  late List<int> _trainingDays;

  String _appVersion = '1.0.6';

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _nameController = TextEditingController(text: widget.user.name);
    _weightController = TextEditingController(text: widget.user.weight.toString());
    _heightController = TextEditingController(
      text: (widget.user.height ?? 180).toStringAsFixed(0),
    );
    _gender = widget.user.gender ?? 'male';
    _trainingDays = List.from(widget.user.trainingDays);

    _nameController.addListener(_autoSave);
    _weightController.addListener(_autoSave);
    _heightController.addListener(_autoSave);
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      setState(() {
        _appVersion = info.version;
      });
    } catch (_) {
      setState(() {
        _appVersion = '1.0.6';
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  // ===== АВТОСОХРАНЕНИЕ =====
  void _autoSave() {
    final name = _nameController.text.trim();
    final weight = int.tryParse(_weightController.text.trim()) ?? widget.user.weight;
    final height = double.tryParse(_heightController.text.trim()) ?? widget.user.height;

    // Собираем обновлённого пользователя через copyWith
    final updatedUser = widget.user.copyWith(
      name: name.isNotEmpty ? name : widget.user.name,
      weight: weight,
      height: height,
      gender: _gender,
      trainingDays: _trainingDays,
    );

    _saveToPrefs(updatedUser);
    widget.onUpdate(updatedUser);
    setState(() {});
  }

  Future<void> _saveToPrefs(AppUser user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile_name', user.name);
    await prefs.setInt('profile_weight', user.weight);
    await prefs.setString('profile_height', (user.height ?? 180).toString());
    await prefs.setString('profile_gender', user.gender ?? 'male');
    await prefs.setString('profile_days', user.trainingDays.join(','));
    await prefs.setString('profile_email', user.email);
  }

  // ===== ПЕРЕКЛЮЧЕНИЕ ДНЕЙ =====
  void _toggleDay(int day) {
    setState(() {
      if (_trainingDays.contains(day)) {
        _trainingDays.remove(day);
      } else {
        _trainingDays.add(day);
        _trainingDays.sort();
      }
    });
    _autoSave();
  }

  // ===== ВЫХОД =====
  void _logout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1E26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: const Text(
          'Выход',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Вы уверены, что хотите выйти?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Отмена',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              // Здесь реальный выход:
              // AuthService.signOut();
              // Navigator.pushReplacement(...);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('🚪 Выход... (демо)'),
                  backgroundColor: Colors.orange,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
  }

  // ===== UI =====

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок
          ShaderMask(
            shaderCallback: (bounds) => LinearGradient(
              colors: [Colors.orange, Colors.orangeAccent],
            ).createShader(bounds),
            child: const Text(
              '👤 Профиль',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 16),

          _buildAvatar(),
          _buildFields(),
          _buildAiImportButton(), const SizedBox(height: 16),
          _buildLogoutButton(),
          _buildAboutBlock(),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    final name = _nameController.text.trim().isEmpty
        ? widget.user.name
        : _nameController.text.trim();
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: _glassDecoration(),
      child: Row(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF9800), Color(0xFFF57C00)],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.orange.withOpacity(0.35),
                  blurRadius: 24,
                ),
              ],
            ),
            child: Center(
              child: Text(
                initial,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.user.email,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFields() {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: _glassDecoration(),
      child: Column(
        children: [
          _buildTextField('Имя', _nameController, Icons.person),
          const SizedBox(height: 12),
          _buildTextField('Вес (кг)', _weightController, Icons.monitor_weight, isNumber: true),
          const SizedBox(height: 12),
          _buildTextField('Рост (см)', _heightController, Icons.height, isNumber: true),
          const SizedBox(height: 12),
          _buildGenderSelector(),
          const SizedBox(height: 12),
          _buildDaysSelector(),
        ],
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller,
    IconData icon, {
    bool isNumber = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: Colors.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: isNumber
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: Colors.grey),
            filled: true,
            fillColor: Colors.white.withOpacity(0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Colors.orange, width: 1),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGenderSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Пол',
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(18),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _gender,
              isExpanded: true,
              dropdownColor: const Color(0xFF1A1E26),
              style: const TextStyle(color: Colors.white, fontSize: 16),
              items: const [
                DropdownMenuItem(value: 'male', child: Text('Мужской')),
                DropdownMenuItem(value: 'female', child: Text('Женский')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _gender = value;
                  });
                  _autoSave();
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDaysSelector() {
    const dayNames = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Дни тренировок',
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: List.generate(7, (index) {
            final day = index + 1;
            final isActive = _trainingDays.contains(day);
            return GestureDetector(
              onTap: () => _toggleDay(day),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isActive
                      ? Colors.orange.withOpacity(0.2)
                      : Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: isActive
                        ? Colors.orange
                        : Colors.white.withOpacity(0.06),
                  ),
                ),
                child: Text(
                  dayNames[index],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isActive ? Colors.orange : Colors.grey,
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  void _showImportProgramDialog() {
    final textController = TextEditingController();
    int weeks = 6;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1E26),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: Colors.purpleAccent.withOpacity(0.3)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.6),
                    blurRadius: 40,
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.auto_awesome, color: Colors.purpleAccent),
                        SizedBox(width: 10),
                        Text(
                          'Импорт программы',
                          style: TextStyle(
                            color: Colors.purpleAccent,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Вставь программу от тренера. AI разберёт её и добавит тренировки в план.',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Текст программы:',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: textController,
                      maxLines: 8,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Пример:\n'
                            'Жим лёжа 5x5 80кг\n'
                            'Приседания 5x5 100кг\n'
                            'Становая 5x5 120кг\n'
                            'Прогрессия: +2.5кг каждую неделю',
                        hintStyle: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.04),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text(
                          'Недель:',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                        const SizedBox(width: 12),
                        ...List.generate(3, (index) {
                          final value = [4, 6, 8][index];
                          final isActive = weeks == value;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: GestureDetector(
                              onTap: () => setStateDialog(() => weeks = value),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? Colors.purpleAccent.withOpacity(0.3)
                                      : Colors.white.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isActive
                                        ? Colors.purpleAccent
                                        : Colors.white.withOpacity(0.1),
                                  ),
                                ),
                                child: Text(
                                  '$value',
                                  style: TextStyle(
                                    color: isActive
                                        ? Colors.purpleAccent
                                        : Colors.grey,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text(
                            'Отмена',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () async {
                            final text = textController.text.trim();
                            if (text.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Вставь текст программы'),
                                ),
                              );
                              return;
                            }
                            Navigator.pop(ctx);
                            await _importProgram(text, weeks);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purpleAccent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.auto_awesome, size: 16),
                              SizedBox(width: 6),
                              Text(
                                'Импортировать',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _importProgram(String text, int weeks) async {
    // Показываем модалку загрузки
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: CircularProgressIndicator(color: Colors.purpleAccent),
      ),
    );

    final result = await AiImportService.importProgram(
      email: widget.user.email,
      programText: text,
      weeks: weeks,
    );

    // Закрываем модалку загрузки
    if (mounted) Navigator.of(context).pop();

    if (result['success'] == true) {
      final count = result['count'] ?? 0;
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1E26),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 10),
              Text('Готово!', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: Text(
            'AI добавил $count тренировок.\n\nОткрой вкладку «План», чтобы посмотреть.',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'ОК',
                style: TextStyle(color: Colors.purpleAccent),
              ),
            ),
          ],
        ),
      );
    } else {
      if (!mounted) return;
      final error = result['error']?.toString() ?? 'Неизвестная ошибка';
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1E26),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          title: const Row(
            children: [
              Icon(Icons.error, color: Colors.redAccent),
              SizedBox(width: 10),
              Text('Ошибка', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: Text(
            error,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'ОК',
                style: TextStyle(color: Colors.purpleAccent),
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildAiImportButton() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _showImportProgramDialog,
        icon: const Icon(Icons.auto_awesome, size: 20),
        label: const Text(
          'Импорт программы (AI)',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.purpleAccent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _logout,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.redAccent,
          padding: const EdgeInsets.symmetric(vertical: 16),
          side: const BorderSide(color: Colors.redAccent, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.exit_to_app, size: 20),
            SizedBox(width: 8),
            Text(
              'Выйти',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAboutBlock() {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.04)),
      ),
      child: Column(
        children: [
          Text(
            '📱 Версия $_appVersion',
            style: const TextStyle(
              fontSize: 14,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Разработчик: Максим Бузмаков',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  Colors.orange.withOpacity(0.3),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '📧 maxcimbuzmakov651@gmail.com',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                '💬 Telegram: ',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey,
                ),
              ),
              GestureDetector(
                onTap: () {
                  // Открыть ссылку на Telegram:
                  // launchUrl(Uri.parse('https://t.me/max4n'));
                },
                child: const Text(
                  '@max4n',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF4FC3F7),
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          RichText(
            text: const TextSpan(
              style: TextStyle(
                fontSize: 13,
                color: Colors.white70,
              ),
              children: [
                TextSpan(text: 'Сделано с '),
                TextSpan(
                  text: '❤️',
                  style: TextStyle(color: Color(0xFFFF9800)),
                ),
                TextSpan(text: ' для тренировок'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _glassDecoration() {
    return BoxDecoration(
      color: Colors.white.withOpacity(0.03),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.white.withOpacity(0.06)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.3),
          blurRadius: 32,
        ),
      ],
    );
  }
}