import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:reelva/app/theme/reelva_theme.dart';

export 'package:reelva/app/theme/reelva_theme.dart' show ReelvaDesign;

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.margin,
    this.borderRadius,
    this.color,
    this.onTap,
    this.blur = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;
  final Color? color;
  final VoidCallback? onTap;
  final bool blur;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = borderRadius ?? BorderRadius.circular(ReelvaDesign.radius);
    Widget content = Padding(padding: padding, child: child);
    if (onTap != null) {
      content = Material(
        type: MaterialType.transparency,
        child: InkWell(onTap: onTap, borderRadius: radius, child: content),
      );
    }
    content = DecoratedBox(
      decoration: BoxDecoration(
        color:
            color ??
            (isDark ? ReelvaDesign.playerGlassFill : ReelvaDesign.glassFill),
        borderRadius: radius,
        border: Border.all(
          color: isDark
              ? ReelvaDesign.playerGlassBorder
              : ReelvaDesign.glassBorder,
          width: 1.2,
        ),
      ),
      child: content,
    );
    if (blur) {
      content = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: content,
      );
    }
    content = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A283D66),
            blurRadius: 24,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(borderRadius: radius, child: content),
    );
    return margin == null ? content : Padding(padding: margin!, child: content);
  }
}

class GlassButton extends StatelessWidget {
  const GlassButton({
    super.key,
    required this.child,
    this.icon,
    this.onPressed,
    this.primary = false,
    this.tooltip,
    this.style,
  });

  final Widget child;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool primary;
  final String? tooltip;
  final ButtonStyle? style;

  @override
  Widget build(BuildContext context) {
    final Widget button;
    if (primary) {
      button = icon == null
          ? FilledButton(onPressed: onPressed, style: style, child: child)
          : FilledButton.icon(
              onPressed: onPressed,
              style: style,
              icon: Icon(icon),
              label: child,
            );
    } else {
      button = icon == null
          ? OutlinedButton(onPressed: onPressed, style: style, child: child)
          : OutlinedButton.icon(
              onPressed: onPressed,
              style: style,
              icon: Icon(icon),
              label: child,
            );
    }
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.selected = false,
    this.size = 48,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      isSelected: selected,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        minimumSize: Size.square(size),
        iconSize: size / 2,
        padding: EdgeInsets.all(size / 4),
        shape: const CircleBorder(),
        backgroundColor: selected
            ? scheme.primaryContainer
            : isDark
            ? ReelvaDesign.playerGlassFill
            : ReelvaDesign.glassFill,
        foregroundColor: selected
            ? scheme.onPrimaryContainer
            : scheme.onSurface,
        disabledBackgroundColor: scheme.onSurface.withValues(alpha: 0.04),
        disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.38),
        side: isDark && !selected && onPressed != null
            ? const BorderSide(color: ReelvaDesign.playerGlassBorder)
            : null,
      ),
    );
  }
}

class GlassSearchField extends StatefulWidget {
  const GlassSearchField({
    super.key,
    this.controller,
    this.hintText = '搜索影视作品',
    this.onChanged,
    this.onClear,
  });

  final TextEditingController? controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;

  @override
  State<GlassSearchField> createState() => _GlassSearchFieldState();
}

class _GlassSearchFieldState extends State<GlassSearchField> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
  }

  @override
  void didUpdateWidget(covariant GlassSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      final previous = _controller;
      _controller =
          widget.controller ?? TextEditingController.fromValue(previous.value);
      if (oldWidget.controller == null) previous.dispose();
    }
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    widget.onChanged?.call('');
    widget.onClear?.call();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _controller,
      builder: (context, value, child) => GlassCard(
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(24),
        child: TextField(
          controller: _controller,
          onChanged: widget.onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.transparent,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            constraints: const BoxConstraints(minHeight: 48),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 1.5,
              ),
            ),
            hintText: widget.hintText,
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    onPressed: _clear,
                    tooltip: '清空搜索',
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
        ),
      ),
    );
  }
}

class GlassPageHeader extends StatelessWidget {
  const GlassPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.leading,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final heading = ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: ReelvaDesign.pageHeaderMinHeight,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 12)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          title,
                          style: theme.textTheme.headlineLarge?.copyWith(
                            fontSize: ReelvaDesign.pageHeaderTitleSize,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          subtitle!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
          if (actions.isEmpty) return heading;

          final stackActions =
              constraints.maxWidth < 600 ||
              MediaQuery.textScalerOf(context)
                      .scale(ReelvaDesign.pageHeaderTitleSize) >
                  ReelvaDesign.pageHeaderTitleSize * 1.4;
          final actionGroup = Wrap(
            spacing: 4,
            runSpacing: 4,
            alignment: stackActions ? WrapAlignment.start : WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: actions,
          );
          if (stackActions) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [heading, const SizedBox(height: 16), actionGroup],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: heading),
              const SizedBox(width: 16),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth * 0.45,
                ),
                child: actionGroup,
              ),
            ],
          );
        },
      ),
    );
  }
}

class GlassSectionTitle extends StatelessWidget {
  const GlassSectionTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        );
        if (trailing == null) return heading;
        if (constraints.maxWidth < 480 ||
            MediaQuery.textScalerOf(context).scale(19) > 28) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [heading, const SizedBox(height: 12), trailing!],
          );
        }
        return Row(
          children: [
            Expanded(child: heading),
            const SizedBox(width: 16),
            Flexible(child: trailing!),
          ],
        );
      },
    );
  }
}

class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: isDark
          ? const BoxDecoration(color: ReelvaDesign.playerBackground)
          : const BoxDecoration(
              color: ReelvaDesign.background,
              gradient: RadialGradient(
                center: Alignment.topRight,
                radius: 1.3,
                colors: [Color(0xFFEAF2FF), ReelvaDesign.background],
                stops: [0, 0.75],
              ),
            ),
      child: child,
    );
  }
}
