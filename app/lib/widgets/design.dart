import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'common.dart';

/// Encabezado grande de pantalla: avatar, título en negrita, subtítulo y acciones.
/// (Estilo bandeja de entrada: "Mail · 20 unread".)
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({super.key, required this.title, this.subtitle, this.avatarUrl, this.avatarName, this.actions = const []});
  final String title;
  final String? subtitle;
  final String? avatarUrl;
  final String? avatarName;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
      child: Row(children: [
        if (avatarName != null) ...[
          UserAvatar(url: avatarUrl, name: avatarName!, radius: 22),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontFamily: NetJobFonts.display, fontSize: 25, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: NetJobColors.ink)),
            if (subtitle != null) Text(subtitle!, style: const TextStyle(fontSize: 14, color: NetJobColors.muted)),
          ]),
        ),
        ...actions,
      ]),
    );
  }
}

/// Filtros tipo píldora; la seleccionada va en amarillo.
class PillTabs extends StatelessWidget {
  const PillTabs({super.key, required this.items, required this.selected, required this.onSelected, this.padding});
  final List<(String value, String label, IconData icon)> items;
  final String selected;
  final ValueChanged<String> onSelected;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(children: [
        for (final it in items)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              decoration: ShapeDecoration(
                shape: const StadiumBorder(),
                gradient: it.$1 == selected ? NetJobColors.gradient : null,
                color: it.$1 == selected ? null : const Color(0xFF241834),
                shadows: it.$1 == selected
                    ? const [BoxShadow(color: Color(0x40C98BFF), blurRadius: 14, offset: Offset(0, 6))]
                    : const [],
              ),
              child: Material(
              color: Colors.transparent,
              shape: const StadiumBorder(),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () => onSelected(it.$1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(it.$3, size: 18, color: it.$1 == selected ? NetJobColors.onPrimary : NetJobColors.ink),
                    const SizedBox(width: 6),
                    Text(it.$2,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: it.$1 == selected ? NetJobColors.onPrimary : NetJobColors.ink,
                        )),
                  ]),
                ),
              ),
            ),
            ),
          ),
      ]),
    );
  }
}

/// Tarjeta destacada con borde azul grueso: el aviso más importante del momento.
class HighlightCard extends StatelessWidget {
  const HighlightCard({super.key, required this.title, this.subtitle, required this.icon, this.color = NetJobColors.primary, this.onTap});
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: NetJobColors.card,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: NetJobColors.primary, width: 3.5),
        boxShadow: const [BoxShadow(color: Color(0x26C98BFF), blurRadius: 24, offset: Offset(0, 10))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 14, 18),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                      style: TextStyle(fontFamily: NetJobFonts.display, fontSize: 21, fontWeight: FontWeight.w800, height: 1.15, letterSpacing: -0.2, color: NetJobColors.ink)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 8),
                    Text(subtitle!, style: const TextStyle(fontSize: 15, color: NetJobColors.muted, fontWeight: FontWeight.w500)),
                  ],
                ]),
              ),
              const SizedBox(width: 12),
              IllustrationBadge(icon: icon, color: color),
            ]),
          ),
        ),
      ),
    );
  }
}

/// "Ilustración" sencilla: ícono grande sobre una mancha de color con destellos.
class IllustrationBadge extends StatelessWidget {
  const IllustrationBadge({super.key, required this.icon, required this.color, this.size = 92});
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        Container(
          width: size * 0.86,
          height: size * 0.86,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(size * 0.32),
          ),
        ),
        Icon(icon, size: size * 0.5, color: color),
        Positioned(left: 0, top: size * 0.3, child: Icon(Icons.auto_awesome, size: size * 0.2, color: NetJobColors.primaryLight)),
        Positioned(right: 2, top: 4, child: Icon(Icons.auto_awesome, size: size * 0.15, color: NetJobColors.bubble)),
      ]),
    );
  }
}

/// Círculo de color con ícono, para filas de listas (avisos, pagos).
class IconBubble extends StatelessWidget {
  const IconBubble({super.key, required this.icon, required this.color, this.size = 50});
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(icon, color: Colors.white, size: size * 0.48),
    );
  }
}

/// Separador de sección en mayúsculas ("HOY", "AYER").
class GroupLabel extends StatelessWidget {
  const GroupLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 20, 8),
        child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: NetJobColors.muted)),
      );
}

/// Anillo de progreso de 0 a [max] (por defecto 5): calificación promedio.
class RatingRing extends StatelessWidget {
  const RatingRing({
    super.key,
    required this.value,
    this.max = 5,
    this.size = 150,
    this.stroke = 12,
    this.color = NetJobColors.mint,
    this.track = const Color(0xFF33244D),
    this.center,
  });
  final double value;
  final double max;
  final double size;
  final double stroke;
  final Color color;
  final Color track;
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: (value / max).clamp(0, 1)),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _RingPainter(t, stroke, color, track), child: Center(child: child)),
      ),
      child: center,
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.t, this.stroke, this.color, this.track);
  final double t;
  final double stroke;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset(stroke / 2, stroke / 2) & Size(size.width - stroke, size.height - stroke);
    // Arco abierto abajo, como un medidor (de 135° a 405°)
    const start = math.pi * 0.75;
    const sweep = math.pi * 1.5;
    final base = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, start, sweep, false, base);
    if (t > 0) canvas.drawArc(rect, start, sweep * t, false, base..color = color);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.t != t || old.color != color;
}

/// Barra fina de progreso con etiqueta y conteo (como "Carbs 97 / 207 g").
class LabeledBar extends StatelessWidget {
  const LabeledBar({super.key, required this.label, required this.value, required this.total, this.dark = true, this.star = false});
  final String label;
  final int value;
  final int total;
  final bool dark;
  final bool star; // agrega un ícono de estrella junto a la etiqueta

  @override
  Widget build(BuildContext context) {
    final fg = dark ? Colors.white : NetJobColors.ink;
    return Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: TextStyle(color: fg.withValues(alpha: 0.85), fontSize: 13)),
        if (star) const Icon(Icons.star_rounded, size: 14, color: NetJobColors.star),
      ]),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: total == 0 ? 0 : value / total,
          minHeight: 6,
          color: NetJobColors.mint,
          backgroundColor: dark ? const Color(0xFF33244D) : const Color(0xFF241834),
        ),
      ),
      const SizedBox(height: 6),
      Text('$value', style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 13)),
    ]);
  }
}
