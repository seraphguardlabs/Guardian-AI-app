import 'package:flutter/material.dart';

/// AppBottomNav - Custom bottom navigation bar with 5 items
/// 
/// Features:
/// - Center circular button for apps screen
/// - Consistent #1A3C8B theme color
/// - 5 navigation items: Chat, Starred, Apps, Hub, Profile
/// - Visual feedback for selected state
class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  final bool isParent;

  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.isParent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F0F),
        border: Border(
          top: BorderSide(
            color: Colors.white.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildNavItem(
            assetPath: 'assets/images/message.png',
            index: 0,
            context: context,
          ),
          _buildNavItem(
            assetPath: 'assets/images/alert.png',
            index: 1,
            context: context,
          ),
          _buildCentralButton(context),
          _buildNavItem(
            assetPath: 'assets/images/command_center.png',
            index: 3,
            context: context,
          ),
          _buildNavItem(
            icon: Icons.person_outline,
            index: 4,
            context: context,
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    String? assetPath,
    IconData? icon,
    required int index,
    required BuildContext context,
  }) {
    final isSelected = currentIndex == index;
    
    return GestureDetector(
      onTap: () => onTap(index),
      child: Container(
        padding: const EdgeInsets.all(12),
        child: assetPath != null
            ? Image.asset(
                assetPath,
                width: 26,
                height: 26,
                color: isSelected ? const Color(0xFF1A3C8B) : Colors.white70,
              )
            : Icon(
                icon,
                color: isSelected ? const Color(0xFF1A3C8B) : Colors.white70,
                size: 28,
              ),
      ),
    );
  }

  Widget _buildCentralButton(BuildContext context) {
    // Slightly larger than other icons and gently lifted
    return Transform.translate(
      offset: const Offset(0, -6),
      child: GestureDetector(
        onTap: () => onTap(2),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Image.asset(
            'assets/images/dashboard.png',
            width: 45,
            height: 45,
            color: null,
          ),
        ),
      ),
    );
  }
}
