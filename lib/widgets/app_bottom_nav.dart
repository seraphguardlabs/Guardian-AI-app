import 'package:flutter/material.dart';

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
            icon: Icons.chat_bubble_outline,
            index: 0,
            context: context,
          ),
          _buildNavItem(
            icon: Icons.star_border,
            index: 1,
            context: context,
          ),
          _buildCentralButton(context),
          _buildNavItem(
            icon: Icons.hub_outlined,
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
    required IconData icon,
    required int index,
    required BuildContext context,
  }) {
    final isSelected = currentIndex == index;
    
    return GestureDetector(
      onTap: () => onTap(index),
      child: Container(
        padding: const EdgeInsets.all(12),
        child: Icon(
          icon,
          color: isSelected ? const Color(0xFF2196F3) : Colors.white70,
          size: 28,
        ),
      ),
    );
  }

  Widget _buildCentralButton(BuildContext context) {
    final isSelected = currentIndex == 2;
    
    return GestureDetector(
      onTap: () => onTap(2),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: isSelected
              ? const LinearGradient(
                  colors: [Color(0xFF2196F3), Color(0xFF1976D2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          border: Border.all(
            color: isSelected ? const Color(0xFF2196F3) : Colors.white24,
            width: 2,
          ),
          color: isSelected ? null : const Color(0xFF1A1A1A),
        ),
        child: Icon(
          Icons.apps,
          color: isSelected ? Colors.white : Colors.white70,
          size: 28,
        ),
      ),
    );
  }
}
