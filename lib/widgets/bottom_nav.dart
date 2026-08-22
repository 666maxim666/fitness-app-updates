import 'package:flutter/material.dart';

class GlassBottomNav extends StatelessWidget {
  final TabController controller;
  final Map<String, dynamic> config;

  const GlassBottomNav({super.key, required this.controller, this.config = const {}});

  @override
  Widget build(BuildContext context) {
    final nav = config['bottomNav'] ?? {};
    final texts = config['texts'] ?? {};
    final colors = config['colors'] ?? {};

    final height = (nav['height'] ?? 48).toDouble();
    final iconSize = (nav['iconSize'] ?? 20).toDouble();
    final fontSize = (nav['fontSize'] ?? 11).toDouble();
    final paddingV = (nav['paddingVertical'] ?? 4).toDouble();
    final marginBottom = (nav['marginBottom'] ?? 10).toDouble();
    final borderRadius = (nav['borderRadius'] ?? 24).toDouble();
    final bgColor = nav['backgroundColor'] ?? '#1A120A';
    final activeColor = nav['activeColor'] ?? '#FF9800';
    final inactiveColor = nav['inactiveColor'] ?? '#FFFFFF';

    final planLabel = texts['planTab'] ?? 'План';
    final progressLabel = texts['progressTab'] ?? 'Прогресс';
    final profileLabel = texts['profileTab'] ?? 'Профиль';

    return Container(
      margin: EdgeInsets.fromLTRB(16, 0, 16, marginBottom),
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: paddingV),
      height: height + 16,
      decoration: BoxDecoration(
        color: Color(int.parse(bgColor.replaceFirst('#', '0xFF'))).withOpacity(0.8),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: Color(int.parse(activeColor.replaceFirst('#', '0xFF'))).withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Color(int.parse(activeColor.replaceFirst('#', '0xFF'))).withOpacity(0.1),
            blurRadius: 12,
          ),
        ],
      ),
      child: TabBar(
        controller: controller,
        indicator: BoxDecoration(
          color: Color(int.parse(activeColor.replaceFirst('#', '0xFF'))).withOpacity(0.2),
          borderRadius: BorderRadius.circular(borderRadius - 8),
        ),
        indicatorSize: TabBarIndicatorSize.tab, // ← полная подсветка всей кнопки
        indicatorPadding: const EdgeInsets.all(3),
        dividerColor: Colors.transparent,
        tabs: [
          Tab(icon: Icon(Icons.calendar_month, size: iconSize), text: planLabel),
          Tab(icon: Icon(Icons.analytics, size: iconSize), text: progressLabel),
          Tab(icon: Icon(Icons.person, size: iconSize), text: profileLabel),
        ],
        labelColor: Color(int.parse(activeColor.replaceFirst('#', '0xFF'))),
        unselectedLabelColor: Color(int.parse(inactiveColor.replaceFirst('#', '0xFF'))).withOpacity(0.5),
        labelStyle: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: fontSize),
      ),
    );
  }
}