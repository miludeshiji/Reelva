import 'package:flutter/material.dart';
import 'package:reelva/app/theme/reelva_theme.dart';

/// Reusable empty-state display for clean, honest placeholders across the app.
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.title,
    this.message,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? message;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: ReelvaDesign.space24,
          vertical: ReelvaDesign.space32,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (icon != null) ...[
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.65),
                    shape: BoxShape.circle,
                    border: Border.all(color: ReelvaDesign.glassBorder),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(ReelvaDesign.space20),
                    child: Icon(icon, size: 44, color: colorScheme.primary),
                  ),
                ),
                const SizedBox(height: ReelvaDesign.space24),
              ],
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: ReelvaDesign.space8),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: ReelvaDesign.space24),
                FilledButton(
                  onPressed: onAction,
                  child: Text(actionLabel!, textAlign: TextAlign.center),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
