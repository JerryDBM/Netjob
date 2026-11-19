import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Identidad visual: fondo crema cálido, verde bosque como color principal, acento
/// naranja para las llamadas a la acción y lima suave para destacar sobre el verde.
class NetJobColors {
  // Fondos
  static const bg = Color(0xFFF4F1E6); // crema
  static const bgSoft = Color(0xFFF8F6EE); // barras y hojas inferiores
  static const card = Color(0xFFFCFBF6); // paneles
  static const cardHigh = Color(0xFFE8ECE1); // paneles elevados / campos (verde salvia muy claro)
  static const border = Color(0x241B4332); // borde fino verdoso

  // Texto
  static const ink = Color(0xFF1A2E24); // principal (casi negro verdoso)
  static const textSoft = Color(0xFF3C4A42);
  static const subtle = Color(0xFF5E6A63);
  static const muted = Color(0xFF878E87);

  // Marca
  static const primary = Color(0xFF1B4332); // verde bosque
  static const primaryDeep = Color(0xFF12301F);
  static const primaryLight = Color(0xFF3D7A5C);
  static const onPrimary = Color(0xFFF8F6EE); // texto sobre verde
  static const mint = Color(0xFF2E8B57); // verde éxito
  static const pink = Color(0xFFE4602B); // naranja de acción
  static const orange = pink;
  static const lime = Color(0xFFD3E27F); // lima suave (sobre verde oscuro)
  static const sky = Color(0xFF3F7CAC);
  static const onDarkSoft = Color(0xFFC9DCCF); // texto secundario sobre verde oscuro

  // Estados
  static const accent = mint; // éxito / pagado
  static const warning = Color(0xFFC77A12);
  static const danger = Color(0xFFC8452F);
  static const star = Color(0xFFE0A21B);

  // Compatibilidad con nombres anteriores
  static const surface = bg;
  static const surfaceDeep = bgSoft;
  static const highlight = primary;
  static const bubble = Color(0xFFCFE6D8); // menta pálida
  static const night = Color(0xFF1B4332); // superficies oscuras (verde bosque)
  static const nightCard = Color(0xFF225240);
  static const slate = Color(0xFF1B4332); // banner de navegación

  // Sobre el mapa (claro): trazos y texto con contraste suficiente
  static const mapBg = Color(0xFFF4F1E6);
  static const mapLine = Color(0xFFE4602B); // rutas, radio de búsqueda, "tú estás aquí"
  static const mapInk = Color(0xFF1B4332);

  /// Botones y selección: verde bosque.
  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF24563F), primary, primaryDeep],
  );

  /// Fondos destacados: verde bosque profundo.
  static const heroGradient = LinearGradient(
    begin: Alignment(-1, -0.6),
    end: Alignment(1, 0.6),
    colors: [Color(0xFF225240), Color(0xFF1B4332), Color(0xFF143425)],
  );

  /// Detalles: naranja → lima → verde.
  static const rainbow = LinearGradient(colors: [pink, lime, mint]);
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
    brightness: Brightness.light,
    primary: NetJobColors.primary,
    onPrimary: NetJobColors.onPrimary,
    secondary: NetJobColors.orange,
    onSecondary: Colors.white,
    surface: NetJobColors.card,
    onSurface: NetJobColors.ink,
    error: NetJobColors.danger,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: Brightness.light);
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
        side: const BorderSide(color: Color(0x591B4332)),
        foregroundColor: NetJobColors.primary,
        textStyle: GoogleFonts.dmSans(fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: NetJobColors.primary)),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: NetJobColors.bgSoft,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 70,
      indicatorColor: NetJobColors.primary,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? NetJobColors.onPrimary : NetJobColors.muted),
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
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28), side: const BorderSide(color: NetJobColors.border)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: NetJobColors.bgSoft,
      dragHandleColor: NetJobColors.muted,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    snackBarTheme: const SnackBarThemeData(backgroundColor: NetJobColors.primary, contentTextStyle: TextStyle(color: NetJobColors.onPrimary, fontWeight: FontWeight.w600)),
    datePickerTheme: const DatePickerThemeData(backgroundColor: NetJobColors.card),
    timePickerTheme: const TimePickerThemeData(backgroundColor: NetJobColors.card),
    popupMenuTheme: const PopupMenuThemeData(color: NetJobColors.cardHigh),
  );
}
