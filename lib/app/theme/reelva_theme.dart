import 'package:flutter/material.dart';

abstract final class ReelvaDesign {
  static const background = Color(0xFFF8FAFD);
  static const ink = Color(0xFF161922);
  static const muted = Color(0xFF626C7A);
  static const accent = Color(0xFF3677E8);
  static const primary = Color(0xFF2464CD);
  static const accentForeground = Colors.white;
  static const glassFill = Color(0xF0FFFFFF);
  static const glassBorder = Color(0xF5FFFFFF);
  static const playerBackground = Color(0xFF0E141C);
  static const playerGlassFill = Color(0x38FFFFFF);
  static const playerGlassBorder = Color(0xB3FFFFFF);

  static const double space4 = 4;
  static const double space8 = 8;
  static const double space12 = 12;
  static const double space16 = 16;
  static const double space20 = 20;
  static const double space24 = 24;
  static const double space32 = 32;

  static const double radiusSmall = 12;
  static const double radius = 20;
  static const double radiusLarge = 28;
  static const double desktopBreakpoint = 900;
  static const double contentMaxWidth = 1280;
  static const double playerContentMaxWidth = 1136;
}

abstract final class ReelvaTheme {
  static final ThemeData _light = _create(Brightness.light);
  static final ThemeData _player = _create(Brightness.dark);

  static ThemeData get light => _light;
  static ThemeData get player => _player;

  static ThemeData _create(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: ReelvaDesign.accent,
          brightness: brightness,
        ).copyWith(
          primary: isDark ? const Color(0xFFA5C7FF) : ReelvaDesign.primary,
          onPrimary: isDark
              ? const Color(0xFF102443)
              : ReelvaDesign.accentForeground,
          primaryContainer: isDark
              ? const Color(0xFF203A60)
              : const Color(0xFFE8F0FF),
          onPrimaryContainer: isDark
              ? const Color(0xFFDCE9FF)
              : ReelvaDesign.primary,
          secondary: isDark ? const Color(0xFFB8C9E3) : ReelvaDesign.muted,
          surface: isDark ? ReelvaDesign.playerBackground : Colors.white,
          onSurface: isDark ? const Color(0xFFF2F5FC) : ReelvaDesign.ink,
          onSurfaceVariant: isDark
              ? const Color(0xFFB2BDCD)
              : ReelvaDesign.muted,
          surfaceContainerLowest: isDark
              ? ReelvaDesign.playerBackground
              : Colors.white,
          surfaceContainerLow: isDark
              ? const Color(0xFF171D28)
              : const Color(0xFFF5F7FC),
          surfaceContainer: isDark
              ? const Color(0xFF1C2330)
              : const Color(0xFFEEF2F9),
          surfaceContainerHigh: isDark
              ? const Color(0xFF252E3D)
              : const Color(0xFFE8EEF7),
          surfaceContainerHighest: isDark
              ? const Color(0xFF313D50)
              : const Color(0xFFDEE6F2),
          outline: isDark ? const Color(0xFF8E9CAF) : const Color(0xFF8994A5),
          outlineVariant: isDark
              ? const Color(0xFF354154)
              : const Color(0xFFDCE3ED),
        );
    final surface = isDark
        ? scheme.surfaceContainerLow
        : ReelvaDesign.glassFill;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(ReelvaDesign.radius),
    );
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(ReelvaDesign.radius),
      borderSide: BorderSide(color: scheme.outlineVariant),
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark
          ? ReelvaDesign.playerBackground
          : ReelvaDesign.background,
      canvasColor: scheme.surface,
      fontFamilyFallback: const [
        'PingFang SC',
        'Microsoft YaHei',
        'Noto Sans CJK SC',
        'Noto Sans SC',
      ],
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
    );
    final text = base.textTheme.copyWith(
      headlineLarge: base.textTheme.headlineLarge?.copyWith(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        height: 1.25,
        letterSpacing: 0,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        height: 1.3,
        letterSpacing: 0,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        height: 1.35,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontSize: 19,
        fontWeight: FontWeight.w700,
        height: 1.35,
        letterSpacing: 0,
      ),
      titleSmall: base.textTheme.titleSmall?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.4,
        letterSpacing: 0,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(
        fontSize: 16,
        height: 1.5,
        letterSpacing: 0,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        fontSize: 14,
        height: 1.5,
        letterSpacing: 0,
      ),
      bodySmall: base.textTheme.bodySmall?.copyWith(
        fontSize: 13,
        height: 1.45,
        letterSpacing: 0,
      ),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
    );
    final menuStyle = MenuStyle(
      backgroundColor: WidgetStatePropertyAll(surface),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      shadowColor: WidgetStatePropertyAll(
        Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
      ),
      elevation: const WidgetStatePropertyAll(8),
      padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
      shape: WidgetStatePropertyAll(shape),
      side: WidgetStatePropertyAll(
        BorderSide(
          color: isDark ? scheme.outlineVariant : ReelvaDesign.glassBorder,
        ),
      ),
    );

    return base.copyWith(
      textTheme: text,
      iconTheme: IconThemeData(color: scheme.onSurface, size: 24),
      dividerColor: scheme.outlineVariant,
      focusColor: scheme.primary.withValues(alpha: 0.16),
      hoverColor: scheme.primary.withValues(alpha: 0.06),
      appBarTheme: AppBarThemeData(
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: isDark ? scheme.surfaceContainer : const Color(0xFFF1F4FA),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
        hintStyle: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        labelStyle: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        helperStyle: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        errorMaxLines: 3,
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
        border: inputBorder,
        enabledBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: Colors.transparent),
        ),
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        disabledBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
      ),
      cardTheme: CardThemeData(
        color: isDark ? ReelvaDesign.playerGlassFill : surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: shape.copyWith(
          side: BorderSide(
            color: isDark
                ? ReelvaDesign.playerGlassBorder
                : ReelvaDesign.glassBorder,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: scheme.onSurface.withValues(alpha: 0.08),
          disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.38),
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: shape,
          textStyle: text.labelLarge,
          alignment: Alignment.center,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: isDark ? ReelvaDesign.playerGlassFill : surface,
          foregroundColor: isDark ? scheme.onSurface : scheme.primary,
          disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.38),
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          side: BorderSide(
            color: isDark
                ? ReelvaDesign.playerGlassBorder
                : scheme.outlineVariant,
          ),
          shape: shape,
          textStyle: text.labelLarge,
          alignment: Alignment.center,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: surface,
          foregroundColor: scheme.primary,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          elevation: 1,
          shadowColor: Colors.black.withValues(alpha: 0.08),
          shape: shape,
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: shape,
          textStyle: text.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: scheme.onSurface,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.all(12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ReelvaDesign.radiusSmall),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: shape,
        insetPadding: const EdgeInsets.all(24),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyLarge,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(ReelvaDesign.radiusLarge),
          ),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: scheme.primaryContainer,
        secondarySelectedColor: scheme.primaryContainer,
        disabledColor: scheme.onSurface.withValues(alpha: 0.06),
        labelStyle: text.labelLarge?.copyWith(color: scheme.onSurface),
        secondaryLabelStyle: text.labelLarge?.copyWith(
          color: scheme.onPrimaryContainer,
        ),
        side: BorderSide(color: scheme.outlineVariant),
        shape: shape,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        showCheckmark: true,
        checkmarkColor: scheme.onPrimaryContainer,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.onSurface,
          borderRadius: BorderRadius.circular(ReelvaDesign.radiusSmall),
        ),
        textStyle: text.bodySmall?.copyWith(color: scheme.surface),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        margin: const EdgeInsets.all(12),
        waitDuration: const Duration(milliseconds: 450),
      ),
      menuTheme: MenuThemeData(style: menuStyle),
      menuButtonTheme: MenuButtonThemeData(
        style: MenuItemButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: text.bodyMedium,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ReelvaDesign.radiusSmall),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: shape,
        textStyle: text.bodyMedium,
      ),
    );
  }
}
