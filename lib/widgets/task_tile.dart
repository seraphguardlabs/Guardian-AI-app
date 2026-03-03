import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

class TaskTile extends StatelessWidget {
  final String title;
  final String description;
  final bool selected;
  final VoidCallback? onTap;

  const TaskTile({
    super.key,
    required this.title,
    required this.description,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: selected ? AppTheme.primary.withOpacity(0.15) : AppTheme.card,
        borderRadius: BorderRadius.circular(AppTheme.radiusL),
        border: Border.all(
          color: selected ? AppTheme.primary : Colors.transparent,
          width: 2,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: AppTheme.primary.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : [],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(
          title,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
        subtitle: Text(
          description,
          style: const TextStyle(
            color: AppTheme.textMuted,
            fontSize: 13,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: selected
            ? const Icon(
                Icons.check_circle,
                color: AppTheme.primary,
                size: 28,
              )
            : const Icon(
                Icons.circle_outlined,
                color: Colors.white24,
                size: 28,
              ),
        onTap: onTap,
      ),
    );
  }
}
