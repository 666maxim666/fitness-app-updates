import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import '../models/user.dart';
import '../services/ai_chat_service.dart';

class AiChatDialog extends StatefulWidget {
  final AppUser user;
  final int waterToday;
  final int waterGoal;
  final bool creatineToday;
  final bool onRest;
  final int restDaysLeft;
  final int pushupGoal;
  final int pushupToday;
  final int totalWorkouts;
  final int attendancePercent;

  final Function(int ml)? onAddWater;
  final Function(int ml)? onRemoveWater;
  final Function(int ml)? onSetWater;
  final VoidCallback? onMarkCreatine;
  final VoidCallback? onUnmarkCreatine;
  final Function(int days)? onStartRest;
  final Function(int count)? onAddPushups;
  final Function(int count)? onRemovePushups;
  final Function(int count)? onSetPushups;

  const AiChatDialog({
    super.key,
    required this.user,
    this.waterToday = 0,
    this.waterGoal = 2400,
    this.creatineToday = false,
    this.onRest = false,
    this.restDaysLeft = 0,
    this.pushupGoal = 100,
    this.pushupToday = 0,
    this.totalWorkouts = 0,
    this.attendancePercent = 0,
    this.onAddWater,
    this.onRemoveWater,
    this.onSetWater,
    this.onMarkCreatine,
    this.onUnmarkCreatine,
    this.onStartRest,
    this.onAddPushups,
    this.onRemovePushups,
    this.onSetPushups,
  });

  @override
  State<AiChatDialog> createState() => _AiChatDialogState();
}

class _AiChatDialogState extends State<AiChatDialog> {
  static const String _historyKey = 'ai_chat_history';

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  bool _isLoading = false;
  bool _historyLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ============================================================
  // ===== ИСТОРИЯ ЧАТА =====
  // ============================================================
  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_historyKey);
    if (data != null) {
      try {
        final List<dynamic> decoded = jsonDecode(data);
        if (mounted) {
          setState(() {
            _messages.addAll(decoded.cast<Map<String, dynamic>>());
            _historyLoaded = true;
          });
        }
        return;
      } catch (e) {
        print('Ошибка загрузки истории: $e');
      }
    }
    // Если истории нет — приветствие
    if (mounted) {
      setState(() {
        _messages.add({
          'role': 'ai',
          'text': 'Привет, ${widget.user.name}! 👋\n\n'
              'Я — твой Gym AI. Могу:\n'
              '• 💧 Управлять водой\n'
              '• 💊 Отметить креатин\n'
              '• 🔔 Поставить напоминание\n'
              '• 🧠 Запомнить что угодно\n'
              '• 📋 Импортировать программу\n'
              '• 📤 Экспортировать историю чата\n\n'
              'Просто скажи, что нужно.',
          'actions': [],
        });
        _historyLoaded = true;
      });
    }
    _saveHistory();
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_historyKey, jsonEncode(_messages));
  }

  Future<void> _clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
    if (!mounted) return;
    setState(() {
      _messages.clear();
      _messages.add({
        'role': 'ai',
        'text': 'История очищена. Чем помочь?',
        'actions': [],
      });
    });
    _saveHistory();
  }

  Future<void> _exportHistory() async {
    if (_messages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('История пуста')),
      );
      return;
    }

    final buf = StringBuffer();
    buf.writeln('Gym Journal — История чата с AI');
    buf.writeln('Пользователь: ${widget.user.name} (${widget.user.email})');
    buf.writeln('Экспортировано: ${DateTime.now().toIso8601String()}');
    buf.writeln('Сообщений: ${_messages.length}');
    buf.writeln('${'═' * 40}\n');

    for (final m in _messages) {
      final role = m['role'] == 'user' ? '👤 Ты' : '✨ Gym AI';
      buf.writeln('$role:');
      buf.writeln(m['text'] ?? '');
      buf.writeln('');
    }

    try {
      await Share.share(
        buf.toString(),
        subject: 'История чата с Gym AI',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка экспорта: $e')),
        );
      }
    }
  }

  // ============================================================
  // ===== ОТПРАВКА СООБЩЕНИЯ =====
  // ============================================================
  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isLoading) return;

    setState(() {
      _messages.add({'role': 'user', 'text': text, 'actions': []});
      _isLoading = true;
    });
    _controller.clear();
    _saveHistory();
    _scrollToBottom();

    // История для контекста (последние 20)
    final history = _messages
        .where((m) => m['role'] == 'user' || m['role'] == 'ai')
        .toList()
        .reversed
        .take(20)
        .toList()
        .reversed
        .map((m) => {
              'role': m['role'] == 'user' ? 'user' : 'ai',
              'text': m['text'] as String,
            })
        .toList();

    final context = AiChatService.buildContext(
      user: widget.user,
      waterToday: widget.waterToday,
      waterGoal: widget.waterGoal,
      creatineToday: widget.creatineToday,
      onRest: widget.onRest,
      restDaysLeft: widget.restDaysLeft,
      pushupGoal: widget.pushupGoal,
      pushupToday: widget.pushupToday,
      totalWorkouts: widget.totalWorkouts,
      attendancePercent: widget.attendancePercent,
    );

    final result = await AiChatService.send(
      email: widget.user.email,
      question: text,
      context: context,
      chatHistory: history,
      timezone: widget.user.timezone,
    );

    if (!mounted) return;

    setState(() {
      _isLoading = false;

      if (result['success'] == true) {
        _messages.add({
          'role': 'ai',
          'text': result['text'] ?? 'Готово',
          'actions': result['actions'] ?? [],
        });
        _handleActions(result['actions'] ?? []);
      } else {
        _messages.add({
          'role': 'ai',
          'text': '⚠️ Ошибка: ${result['error'] ?? 'Неизвестно'}',
          'actions': [],
        });
      }
    });
    _saveHistory();
    _scrollToBottom();
  }

  // ============================================================
  // ===== ОБРАБОТКА ACTIONS =====
  // ============================================================
  void _handleActions(List<dynamic> actions) {
    for (final a in actions) {
      if (a is! Map) continue;
      final type = a['type'] as String?;
      final params = (a['params'] as Map?) ?? {};

      switch (type) {
        case 'add_water':
          final ml = params['ml'] as int? ?? 0;
          if (ml > 0) widget.onAddWater?.call(ml);
          break;
        case 'remove_water':
          final ml = params['ml'] as int? ?? 0;
          if (ml > 0) widget.onRemoveWater?.call(ml);
          break;
        case 'set_water':
          final ml = params['ml'] as int? ?? 0;
          widget.onSetWater?.call(ml);
          break;
        case 'mark_creatine':
          widget.onMarkCreatine?.call();
          break;
        case 'unmark_creatine':
          widget.onUnmarkCreatine?.call();
          break;
        case 'start_rest':
          final days = params['days'] as int? ?? 7;
          widget.onStartRest?.call(days);
          break;
        case 'add_pushups':
          final count = params['count'] as int? ?? 0;
          if (count > 0) widget.onAddPushups?.call(count);
          break;
        case 'remove_pushups':
          final count = params['count'] as int? ?? 0;
          if (count > 0) widget.onRemovePushups?.call(count);
          break;
        case 'set_pushups':
          final count = params['count'] as int? ?? 0;
          widget.onSetPushups?.call(count);
          break;
        case 'export_chat':
          Future.delayed(const Duration(milliseconds: 500), _exportHistory);
          break;
        case 'clear_chat':
          _clearHistory();
          break;
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ============================================================
  // ===== UI =====
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 800),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1c1e28), Color(0xFF14151c)],
          ),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: const Color(0xFFFF9800).withOpacity(0.15)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.9), blurRadius: 60),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            Flexible(child: _buildChatBody()),
            _buildInputArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFa855f7).withOpacity(0.06),
            const Color(0xFFFF9800).withOpacity(0.02),
          ],
        ),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.06)),
        ),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFa855f7), Color(0xFF7c3aed)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFa855f7).withOpacity(0.5),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: const Center(
                  child: Text('✨', style: TextStyle(fontSize: 22)),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4caf50),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF1c1e28), width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Gym AI',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFa855f7).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: const Color(0xFFa855f7).withOpacity(0.3),
                        ),
                      ),
                      child: const Text(
                        'BETA',
                        style: TextStyle(
                          color: Color(0xFFc084fc),
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4caf50),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF4caf50).withOpacity(0.6),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Могу управлять приложением',
                      style: TextStyle(color: Colors.grey[600], fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Кнопка экспорта
          IconButton(
            icon: const Icon(Icons.download_outlined,
                color: Colors.grey, size: 20),
            tooltip: 'Экспорт истории',
            onPressed: _exportHistory,
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.grey, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildChatBody() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 520),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: _messages.length + (_isLoading ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _messages.length) return _buildTypingIndicator();
          final msg = _messages[index];
          return msg['role'] == 'user'
              ? _buildUserMessage(msg)
              : _buildAiMessage(msg);
        },
      ),
    );
  }

  Widget _buildUserMessage(Map<String, dynamic> msg) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 300),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFFFF9800).withOpacity(0.2),
              const Color(0xFFF57C00).withOpacity(0.1),
            ],
          ),
          border: Border.all(color: const Color(0xFFFF9800).withOpacity(0.3)),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(6),
          ),
        ),
        child: Text(
          msg['text'] as String,
          style: const TextStyle(
              color: Colors.white, fontSize: 14, height: 1.5),
        ),
      ),
    );
  }

  Widget _buildAiMessage(Map<String, dynamic> msg) {
    final actions = (msg['actions'] as List?) ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: const BoxConstraints(maxWidth: 320),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(6),
                bottomRight: Radius.circular(18),
              ),
            ),
            child: Text(
              msg['text'] as String,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.55,
              ),
            ),
          ),
        ),
        ...actions.whereType<Map>().map(_buildActionCard),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildActionCard(Map action) {
    final type = action['type'] as String? ?? '';
    final params = (action['params'] as Map?) ?? {};

    String icon = '✓';
    String title = 'Готово';
    String desc = '';
    Color color = const Color(0xFF4caf50);

    switch (type) {
      case 'save_memory':
        icon = '🧠';
        title = 'Запомнено';
        desc = '${params['key']}: ${params['value']}';
        color = const Color(0xFFa855f7);
        break;
      case 'forget_memory':
        icon = '🗑️';
        title = 'Забыто';
        desc = '${params['key']}';
        color = const Color(0xFFa855f7);
        break;
      case 'add_reminder':
        icon = '🔔';
        title = 'Напоминание создано';
        desc = '${params['text']} — ${params['time']}';
        color = const Color(0xFFFF9800);
        break;
      case 'cancel_reminder':
        icon = '🔕';
        title = 'Напоминание удалено';
        desc = 'ID: ${params['id']}';
        color = const Color(0xFFFF9800);
        break;
      case 'add_water':
        icon = '💧';
        title = '+${params['ml']} мл воды';
        desc = 'Добавлено';
        color = const Color(0xFF4fc3f7);
        break;
      case 'remove_water':
        icon = '💧';
        title = '−${params['ml']} мл воды';
        desc = 'Убрано';
        color = const Color(0xFF4fc3f7);
        break;
      case 'set_water':
        icon = '💧';
        title = 'Вода = ${params['ml']} мл';
        desc = 'Установлено';
        color = const Color(0xFF4fc3f7);
        break;
      case 'mark_creatine':
        icon = '💊';
        title = 'Креатин принят';
        desc = '5 г';
        color = const Color(0xFFa855f7);
        break;
      case 'unmark_creatine':
        icon = '💊';
        title = 'Креатин снят';
        desc = 'Отметка убрана';
        color = const Color(0xFFa855f7);
        break;
      case 'start_rest':
        icon = '😴';
        title = 'Отдых запущен';
        desc = '${params['days']} дн.';
        color = const Color(0xFFFF9800);
        break;
      case 'stop_rest':
        icon = '✅';
        title = 'Отдых прекращён';
        desc = '';
        color = const Color(0xFFFF9800);
        break;
      case 'add_pushups':
        icon = '💪';
        title = '+${params['count']} отжиманий';
        desc = 'Добавлено';
        color = const Color(0xFFFF9800);
        break;
      case 'remove_pushups':
        icon = '💪';
        title = '−${params['count']} отжиманий';
        desc = 'Убрано';
        color = const Color(0xFFFF9800);
        break;
      case 'set_pushups':
        icon = '💪';
        title = 'Отжимания = ${params['count']}';
        desc = 'Установлено';
        color = const Color(0xFFFF9800);
        break;
      case 'set_pushup_goal':
        icon = '🎯';
        title = 'Цель отжиманий = ${params['count']}';
        desc = 'Обновлено';
        color = const Color(0xFFFF9800);
        break;
      case 'set_weight':
        icon = '⚖️';
        title = 'Вес = ${params['kg']} кг';
        desc = 'Профиль обновлён';
        color = const Color(0xFF4caf50);
        break;
      case 'set_height':
        icon = '📏';
        title = 'Рост = ${params['cm']} см';
        desc = 'Профиль обновлён';
        color = const Color(0xFF4caf50);
        break;
      case 'set_gender':
        icon = '⚧️';
        title = 'Пол = ${params['gender']}';
        desc = 'Профиль обновлён';
        color = const Color(0xFF4caf50);
        break;
      case 'set_name':
        icon = '👤';
        title = 'Имя = ${params['name']}';
        desc = 'Профиль обновлён';
        color = const Color(0xFF4caf50);
        break;
      case 'add_workout':
        icon = '🏋️';
        title = 'Тренировка добавлена';
        desc = '${params['exercise']} · ${params['date']}';
        color = const Color(0xFF4caf50);
        break;
      case 'export_chat':
        icon = '📤';
        title = 'Экспорт истории';
        desc = 'Открываю меню «Поделиться»';
        color = const Color(0xFF4fc3f7);
        break;
      case 'clear_chat':
        icon = '🗑️';
        title = 'История очищена';
        desc = '';
        color = const Color(0xFFFF9800);
        break;
      default:
        desc = type;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8, left: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      constraints: const BoxConstraints(maxWidth: 300),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        border: Border.all(color: color.withOpacity(0.25)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (desc.isNotEmpty)
                  Text(
                    desc,
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(6),
            bottomRight: Radius.circular(18),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            return TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: Duration(milliseconds: 600 + i * 200),
              builder: (context, v, child) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: const Color(0xFFa855f7)
                        .withOpacity(0.4 + 0.6 * (v % 1)),
                    shape: BoxShape.circle,
                  ),
                );
              },
            );
          }),
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.06)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              maxLines: null,
              minLines: 1,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Скажи что сделать...',
                hintStyle: TextStyle(color: Colors.grey[700]),
                filled: true,
                fillColor: Colors.white.withOpacity(0.04),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide(
                      color: const Color(0xFFa855f7).withOpacity(0.5)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
                ),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _isLoading ? null : _sendMessage,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFa855f7), Color(0xFF7c3aed)],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFa855f7).withOpacity(0.4),
                    blurRadius: 16,
                  ),
                ],
              ),
              child: _isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.send_rounded,
                      color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}