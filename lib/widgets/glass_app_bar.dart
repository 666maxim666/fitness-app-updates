import 'package:flutter/material.dart';

class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final VoidCallback? onNotificationTap;
  final VoidCallback? onCalendarTap;
  final VoidCallback? onAiTap; // ← НОВОЕ
  final int notificationCount;
  final Map<String, dynamic> config;

  const GlassAppBar({
    super.key,
    required this.title,
    this.onNotificationTap,
    this.onCalendarTap,
    this.onAiTap,
    this.notificationCount = 0,
    this.config = const {},
  });

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final colors = config['colors'] ?? {};
    final bell = config['notifications'] ?? {};
    final bgColor = colors['surface'] ?? '#1A120A';
    final iconColor = bell['iconColor'] ?? '#FF9800';
    final iconSize = (bell['iconSize'] ?? 24).toDouble();
    final badgeColor = bell['badgeColor'] ?? '#FF0000';
    final badgeTextColor = bell['badgeTextColor'] ?? '#FFFFFF';
    final badgeSize = (bell['badgeSize'] ?? 18).toDouble();

    return AppBar(
      title: Text(title, style: const TextStyle(color: Colors.white)),
      backgroundColor: Colors.transparent,
      elevation: 0,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(int.parse(bgColor.replaceFirst('#', '0xFF'))),
              Color(int.parse(bgColor.replaceFirst('#', '0xFF')))
                  .withOpacity(0.6),
            ],
          ),
        ),
      ),
      actions: [
        // Иконка календаря
        IconButton(
          icon: Icon(
            Icons.calendar_month,
            color: Color(int.parse(iconColor.replaceFirst('#', '0xFF'))),
            size: iconSize,
          ),
          onPressed: onCalendarTap,
        ),
        // Иконка колокольчика
        Stack(
          children: [
            IconButton(
              icon: Icon(
                Icons.notifications,
                color: Color(int.parse(iconColor.replaceFirst('#', '0xFF'))),
                size: iconSize,
              ),
              onPressed: onNotificationTap,
            ),
            if (notificationCount > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Color(int.parse(badgeColor.replaceFirst('#', '0xFF'))),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$notificationCount',
                    style: TextStyle(
                      fontSize: badgeSize * 0.6,
                      color: Color(
                          int.parse(badgeTextColor.replaceFirst('#', '0xFF'))),
                    ),
                  ),
                ),
              ),
          ],
        ),
        // ===== AI КНОПКА =====
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: onAiTap,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFa855f7).withOpacity(0.2),
                    const Color(0xFF7c3aed).withOpacity(0.1),
                  ],
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFa855f7).withOpacity(0.3),
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFa855f7).withOpacity(0.25),
                    blurRadius: 16,
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Text('✨', style: TextStyle(fontSize: 18)),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4caf50),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF4caf50).withOpacity(0.8),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}