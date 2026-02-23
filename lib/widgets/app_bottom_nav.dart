import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

/// AppBottomNav - Custom bottom navigation bar with 5 items
/// 
/// Features:
/// - Center circular button for apps screen
/// - Consistent #1A3C8B theme color
/// - 5 navigation items: Chat, Starred, Apps, Hub, Profile
/// - Visual feedback for selected state + animated scale on tap
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
            color: Colors.white.withOpacity(0.08),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _AnimatedNavItem(
            assetPath: 'assets/images/message.png',
            index: 0,
            currentIndex: currentIndex,
            onTap: onTap,
          ),
          _AnimatedNavItem(
            assetPath: 'assets/images/alert.png',
            index: 1,
            currentIndex: currentIndex,
            onTap: onTap,
          ),
          _AnimatedCenterButton(
            onTap: () => onTap(2),
            isSelected: currentIndex == 2,
          ),
          _AnimatedNavItem(
            assetPath: 'assets/images/command_center.png',
            index: 3,
            currentIndex: currentIndex,
            onTap: onTap,
          ),
          _AnimatedNavItem(
            icon: Icons.person_outline,
            index: 4,
            currentIndex: currentIndex,
            onTap: onTap,
          ),
        ],
      ),
    );
  }
}

/// Individual animated nav item
class _AnimatedNavItem extends StatefulWidget {
  final String? assetPath;
  final IconData? icon;
  final int index;
  final int currentIndex;
  final Function(int) onTap;

  const _AnimatedNavItem({
    this.assetPath,
    this.icon,
    required this.index,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  State<_AnimatedNavItem> createState() => _AnimatedNavItemState();
}

class _AnimatedNavItemState extends State<_AnimatedNavItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 130),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.80)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.currentIndex == widget.index;

    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap(widget.index);
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              widget.assetPath != null
                  ? Image.asset(
                      widget.assetPath!,
                      width: 26,
                      height: 26,
                      color: isSelected ? AppTheme.primary : Colors.white70,
                    )
                  : Icon(
                      widget.icon,
                      color: isSelected ? AppTheme.primary : Colors.white70,
                      size: 28,
                    ),
              if (isSelected)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(top: 3),
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primary.withOpacity(0.6),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Animated center (apps) button
class _AnimatedCenterButton extends StatefulWidget {
  final VoidCallback onTap;
  final bool isSelected;

  const _AnimatedCenterButton({required this.onTap, required this.isSelected});

  @override
  State<_AnimatedCenterButton> createState() => _AnimatedCenterButtonState();
}

class _AnimatedCenterButtonState extends State<_AnimatedCenterButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 130),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.88)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _glow = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, child) => Transform.translate(
          offset: const Offset(0, -6),
          child: ScaleTransition(
            scale: _scale,
            child: Container(
              padding: const EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: widget.isSelected
                    ? [
                        BoxShadow(
                          color: AppTheme.primary.withOpacity(0.3 + _glow.value * 0.2),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              child: Image.asset(
                'assets/images/dashboard.png',
                width: 45,
                height: 45,
                color: null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
