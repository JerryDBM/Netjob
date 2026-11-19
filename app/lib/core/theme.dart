import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Identidad visual (paleta tomada de drift.iscoutb.dev): fondo violeta casi negro,
/// paneles de vidrio translúcidos, lavanda como color principal, acentos menta, rosa y
/// celeste, y degradados profundos morado → azul → magenta.
class NetJobColors {
  // Fondos
  static const bg = Color(0xFF0D0716);
  static const bgSoft = Color(0xFF140A21); // barras y hojas inferiores
  static const card = Color(0xFF1B1029); // paneles
  static const cardHigh = Color(0xFF261A3A); // paneles elevados / campos
  static const border = Color(0x21FFFFFF); // borde de vidrio (13 %)

  // Texto
  static const ink = Color(0xFFF6F2FC); // principal
  static const textSoft = Color(0xFFDDD3EE);
  static const subtle = Color(0xFFB9AECD);
  static const muted = Color(0xFF8A7FA3);

  // Marca
  static const primary = Color(0xFFC98BFF); // lavanda
  static const primaryDeep = Color(0xFF8D6BFF);
  static const primaryLight = Color(0xFFE3C4FF);
  static const onPrimary = Color(0xFF1A0B2B); // texto sobre lavanda
  static const mint = Color(0xFF6DFFB4);
  static const pink = Color(0xFFFF8FD0);
  static const sky = Color(0xFF7CC7FF);

  // Estados
  static const accent = mint; // éxito / pagado
  static const warning = Color(0xFFFFB86B);
  static const danger = Color(0xFFFF7A9C);
  static const star = Color(0xFFFFC86B);

  // Compatibilidad con nombres anteriores
  static const surface = bg;
  static const surfaceDeep = bgSoft;
  static const highlight = primary;
  static const bubble = Color(0xFF3B2560);
  static const night = bg;
  static const nightCard = card;
  static const slate = Color(0xFF2A1846); // banner de navegación

  // Sobre el mapa (claro): trazos y texto con contraste suficiente
  static const mapBg = Color(0xFFF4F1FA);
  static const mapLine = Color(0xFF6B3FD4); // rutas, radio de búsqueda, "tú estás aquí"
  static const mapInk = Color(0xFF3B2560);

  /// Botones y selección: lila claro → lavanda → violeta.
  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryLight, primary, primaryDeep],
  );

  /// Fondos destacados: morado profundo → azul noche → magenta.
  static const heroGradient = LinearGradient(
    begin: Alignment(-1, -0.6),
    end: Alignment(1, 0.6),
    colors: [Color(0xFF45186A), Color(0xFF1D2A7C), Color(0xFF6A1D5C)],
  );

  /// Detalles: rosa → lavanda → celeste.
  static const rainbow = LinearGradient(colors: [pink, primary, sky]);
}

/// Tipografías: Exo 2 para títulos y DM Sans para textos.
class NetJobFonts {
  static String? get display => GoogleFonts.exo2().fontFamily;
  static String? get body => GoogleFonts.dmSans().fontFamily;
}

/// Transición entre pantallas: aparece desde abajo con desvanecido y un leve zoom.
class NetJobPageTransitions extends PageTransitionsBuilder {
  const NetJobPageTransitions();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 420);

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    final inCurve = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    final outCurve = CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: Tween(begin: 1.0, end: 0.6).animate(outCurve),
      child: ScaleTransition(
        scale: Tween(begin: 1.0, end: 0.96).animate(outCurve),
        child: FadeTransition(
          opacity: inCurve,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(inCurve),
            child: ScaleTransition(scale: Tween(begin: 0.985, end: 1.0).animate(inCurve), child: child),
          ),
        ),
      ),
    );
  }
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: NetJobColors.primary,
    brightness: Brightness.dark,
    primary: NetJobColors.primary,
    onPrimary: NetJobColors.onPrimary,
    secondary: NetJobColors.mint,
    onSecondary: NetJobColors.onPrimary,
    surface: NetJobColors.card,
    onSurface: NetJobColors.ink,
    error: NetJobColors.danger,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: Brightness.dark);
  final body = GoogleFonts.dmSansTextTheme(base.textTheme).apply(bodyColor: NetJobColors.ink, displayColor: NetJobColors.ink);
  TextStyle? display(TextStyle? s, FontWeight w, double ls) => GoogleFonts.exo2(textStyle: s, fontWeight: w, letterSpacing: ls);
  final radius = BorderRadius.circular(16);
  return base.copyWith(
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: NetJobPageTransitions(),
      TargetPlatform.iOS: NetJobPageTransitions(),
      TargetPlatform.windows: NetJobPageTransitions(),
      TargetPlatform.macOS: NetJobPageTransitions(),
      TargetPlatform.linux: NetJobPageTransitions(),
      TargetPlatform.fuchsia: NetJobPageTransitions(),
    }),
    scaffoldBackgroundColor: NetJobColors.bg,
    canvasColor: NetJobColors.bg,
    dividerColor: NetJobColors.border,
    textTheme: body.copyWith(
      headlineLarge: display(body.headlineLarge, FontWeight.w800, -0.6),
      headlineMedium: display(body.headlineMedium, FontWeight.w800, -0.6),
      headlineSmall: display(body.headlineSmall, FontWeight.w800, -0.4),
      titleLarge: display(body.titleLarge, FontWeight.w700, -0.2),
      titleMedium: body.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: NetJobColors.bg,
      foregroundColor: NetJobColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.exo2(fontSize: 22, fontWeight: FontWeight.w800, color: NetJobColors.ink),
    ),
    cardTheme: CardThemeData(
      color: NetJobColors.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: NetJobColors.border),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: NetJobColors.subtle,
      titleTextStyle: GoogleFonts.dmSans(fontSize: 16, fontWeight: FontWeight.w700, color: NetJobColors.ink),
      subtitleTextStyle: GoogleFonts.dmSans(fontSize: 13.5, color: NetJobColors.subtle, height: 1.35),
    ),
    iconTheme: const IconThemeData(color: NetJobColors.subtle),
    chipTheme: base.chipTheme.copyWith(
      shape: const StadiumBorder(),
      side: const BorderSide(color: NetJobColors.border),
      backgroundColor: NetJobColors.cardHigh,
      selectedColor: NetJobColors.primary,
      labelStyle: const TextStyle(fontWeight: FontWeight.w700, color: NetJobColors.ink),
      secondaryLabelStyle: const TextStyle(fontWeight: FontWeight.w700, color: NetJobColors.onPrimary),
      showCheckmark: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: NetJobColors.cardHigh,
      hintStyle: const TextStyle(color: NetJobColors.muted),
      labelStyle: const TextStyle(color: NetJobColors.subtle),
      prefixIconColor: NetJobColors.subtle,
      suffixIconColor: NetJobColors.subtle,
      border: OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: NetJobColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: NetJobColors.border)),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: NetJobColors.primary, width: 1.6)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        shape: const StadiumBorder(),
        backgroundColor: NetJobColors.primary,
        foregroundColor: NetJobColors.onPrimary,
        disabledBackgroundColor: NetJobColors.cardHigh,
        disabledForegroundColor: NetJobColors.muted,
        textStyle: GoogleFonts.dmSans(fontWeight: FontWeight.w800, fontSize: 15.5),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 52),
        shape: const StadiumBorder(),
        side: const BorderSide(color: Color(0x40C98BFF)),
        foregroundColor: NetJobColors.primary,
        textStyle: GoogleFonts.dmSans(fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: NetJobColors.primary)),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: NetJobColors.bgSoft,
      elevation: 0,
      height: 70,
      indicatorColor: const Color(0x33C98BFF),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? NetJobColors.primary : NetJobColors.muted),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => GoogleFonts.dmSans(
          fontSize: 12,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
          color: s.contains(WidgetState.selected) ? NetJobColors.primary : NetJobColors.muted,
        ),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelStyle: GoogleFonts.dmSans(fontWeight: FontWeight.w800),
      labelColor: NetJobColors.primary,
      unselectedLabelColor: NetJobColors.muted,
      indicatorColor: NetJobColors.primary,
      dividerColor: Colors.transparent,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? NetJobColors.onPrimary : NetJobColors.muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? NetJobColors.primary : NetJobColors.cardHigh),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: NetJobColors.primary, linearTrackColor: NetJobColors.cardHigh),
    dialogTheme: DialogThemeData(
      backgroundColor: NetJobColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28), side: const BorderSide(color: NetJobColors.border)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: NetJobColors.bgSoft,
      dragHandleColor: NetJobColors.muted,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    snackBarTheme: const SnackBarThemeData(contentTextStyle: TextStyle(color: NetJobColors.onPrimary, fontWeight: FontWeight.w600)),
    datePickerTheme: const DatePickerThemeData(backgroundColor: NetJobColors.card),
    timePickerTheme: const TimePickerThemeData(backgroundColor: NetJobColors.card),
    popupMenuTheme: const PopupMenuThemeData(color: NetJobColors.cardHigh),
  );
}
