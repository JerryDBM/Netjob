import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Fondo de las pantallas de acceso: violeta casi negro con resplandores morado,
/// azul y magenta que se mueven lentamente.
class AuthBackground extends StatefulWidget {
  const AuthBackground({super.key, required this.child});
  final Widget child;
  @override
  State<AuthBackground> createState() => _AuthBackgroundState();
}

class _AuthBackgroundState extends State<AuthBackground> with SingleTickerProviderStateMixin {
  late final _float = AnimationController(vsync: this, duration: const Duration(seconds: 9))..repeat(reverse: true);

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: NetJobColors.bg,
      child: AnimatedBuilder(
        animation: _float,
        builder: (context, child) {
          final t = Curves.easeInOut.transform(_float.value);
          return LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth;
            final h = c.maxHeight;
            return Stack(children: [
              _glow(left: -w * 0.35 + t * 20, top: -h * 0.12, size: w * 0.95, color: const Color(0xFFCFE6D8)),
              _glow(left: w * 0.45 - t * 24, top: h * 0.18 + t * 16, size: w * 0.75, color: const Color(0xFFE9F0B8)),
              _glow(left: -w * 0.2 + t * 18, top: h * 0.62, size: w * 0.8, color: const Color(0xFFF6D9C6)),
              _ring(left: w * 0.68, top: h * 0.06 + t * 10, size: w * 0.42),
              _ring(left: -w * 0.16, top: h * 0.8 - t * 8, size: w * 0.36),
              child!,
            ]);
          });
        },
        child: widget.child,
      ),
    );
  }

  /// Mancha de luz difusa.
  Widget _glow({required double left, required double top, required double size, required Color color}) {
    final s = math.min(size, 620.0);
    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: Container(
          width: s,
          height: s,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [color.withValues(alpha: 0.75), color.withValues(alpha: 0.0)]),
          ),
        ),
      ),
    );
  }

  /// Aro de vidrio decorativo.
  Widget _ring({required double left, required double top, required double size}) {
    final s = math.min(size, 300.0);
    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: Container(
          width: s,
          height: s,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0x2E1B4332), width: 1.5),
            gradient: const RadialGradient(colors: [Color(0x00000000), Color(0x0F1B4332)]),
          ),
        ),
      ),
    );
  }
}

/// Logo de NetJob: un maletín con degradado lavanda dentro de una baldosa de vidrio oscuro.
class NetJobLogo extends StatefulWidget {
  const NetJobLogo({super.key, this.size = 150});
  final double size;
  @override
  State<NetJobLogo> createState() => _NetJobLogoState();
}

class _NetJobLogoState extends State<NetJobLogo> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => Transform.translate(offset: Offset(0, -4 * Curves.easeInOut.transform(_c.value)), child: child),
      child: Container(
        width: s,
        height: s,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(s * 0.3),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF24563F), Color(0xFF12301F)],
          ),
          border: Border.all(color: const Color(0x33D3E27F), width: 1.5),
          boxShadow: const [
            BoxShadow(color: Color(0x591B4332), blurRadius: 40, offset: Offset(0, 14)),
          ],
        ),
        child: CustomPaint(painter: BriefcasePainter()),
      ),
    );
  }
}

/// Maletín: cuerpo redondeado con degradado, asa, franja de cierre y broche menta.
class BriefcasePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Asa
    final handle = RRect.fromRectAndRadius(Rect.fromLTRB(w * 0.37, h * 0.24, w * 0.63, h * 0.42), Radius.circular(w * 0.06));
    canvas.drawRRect(
      handle,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.055
        ..shader = const LinearGradient(colors: [Color(0xFFE6EFA6), NetJobColors.lime]).createShader(handle.outerRect),
    );

    // Cuerpo
    final bodyRect = Rect.fromLTRB(w * 0.18, h * 0.36, w * 0.82, h * 0.78);
    final body = RRect.fromRectAndRadius(bodyRect, Radius.circular(w * 0.09));
    canvas.drawShadow(Path()..addRRect(body), const Color(0x66000000), 10, false);
    canvas.drawRRect(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE6EFA6), NetJobColors.lime, Color(0xFFB2C75A)],
        ).createShader(bodyRect),
    );

    // Brillo de vidrio en la parte superior
    final shine = RRect.fromRectAndCorners(
      Rect.fromLTRB(bodyRect.left, bodyRect.top, bodyRect.right, bodyRect.top + bodyRect.height * 0.42),
      topLeft: Radius.circular(w * 0.09),
      topRight: Radius.circular(w * 0.09),
    );
    canvas.drawRRect(shine, Paint()..color = Colors.white.withValues(alpha: 0.16));

    // Franja de cierre
    final y = bodyRect.top + bodyRect.height * 0.42;
    canvas.drawLine(
      Offset(bodyRect.left, y),
      Offset(bodyRect.right, y),
      Paint()
        ..color = NetJobColors.onPrimary.withValues(alpha: 0.35)
        ..strokeWidth = w * 0.022,
    );

    // Broche
    final clasp = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(w * 0.5, y), width: w * 0.15, height: h * 0.1), Radius.circular(w * 0.03));
    canvas.drawRRect(clasp, Paint()..color = NetJobColors.primary);
    canvas.drawRRect(clasp.deflate(w * 0.018), Paint()..color = NetJobColors.orange);

    // Destellos
    _sparkle(canvas, Offset(w * 0.82, h * 0.22), w * 0.06, NetJobColors.orange);
    _sparkle(canvas, Offset(w * 0.2, h * 0.26), w * 0.035, NetJobColors.lime);
  }

  void _sparkle(Canvas canvas, Offset c, double r, Color color) {
    final p = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Campo "de vidrio" oscuro: fondo translúcido, borde sutil y brillo lavanda al enfocar.
class GlassField extends StatelessWidget {
  const GlassField({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xD9FCFBF6), // rgba(24,14,38,.58)
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: NetJobColors.border, width: 1.2),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 18, offset: Offset(0, 8))],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme: const InputDecorationTheme(
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 20),
            hintStyle: TextStyle(color: NetJobColors.muted, fontSize: 16),
            labelStyle: TextStyle(color: NetJobColors.muted, fontSize: 16),
            prefixIconColor: NetJobColors.subtle,
            suffixIconColor: NetJobColors.subtle,
          ),
        ),
        child: child,
      ),
    );
  }
}

/// Botón principal en píldora con degradado lavanda, resplandor y círculo con flecha.
class GradientButton extends StatefulWidget {
  const GradientButton({super.key, required this.label, required this.onPressed, this.loading = false, this.icon = Icons.arrow_forward_rounded});
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData icon;
  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.loading;
    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapCancel: () => setState(() => _down = false),
      onTapUp: enabled
          ? (_) {
              setState(() => _down = false);
              widget.onPressed!();
            }
          : null,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        child: AnimatedOpacity(
          opacity: enabled ? 1 : 0.7,
          duration: const Duration(milliseconds: 200),
          child: Container(
            height: 62,
            decoration: BoxDecoration(
              gradient: NetJobColors.gradient,
              borderRadius: BorderRadius.circular(40),
              boxShadow: const [BoxShadow(color: Color(0x331B4332), blurRadius: 28, offset: Offset(0, 12))],
            ),
            child: Stack(alignment: Alignment.center, children: [
              widget.loading
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.4, color: NetJobColors.onPrimary))
                  : Text(widget.label,
                      style: TextStyle(fontFamily: NetJobFonts.display, color: NetJobColors.onPrimary, fontSize: 19, fontWeight: FontWeight.w800)),
              Positioned(
                right: 9,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x26F8F6EE)),
                  child: Icon(widget.icon, color: NetJobColors.onPrimary),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Hace aparecer los hijos uno tras otro (desvanecido + subida) al abrir la pantalla.
class StaggeredColumn extends StatefulWidget {
  const StaggeredColumn({super.key, required this.children, this.crossAxisAlignment = CrossAxisAlignment.stretch});
  final List<Widget> children;
  final CrossAxisAlignment crossAxisAlignment;
  @override
  State<StaggeredColumn> createState() => _StaggeredColumnState();
}

class _StaggeredColumnState extends State<StaggeredColumn> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: Duration(milliseconds: 500 + widget.children.length * 70))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.children.length;
    return Column(crossAxisAlignment: widget.crossAxisAlignment, mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < n; i++)
        () {
          final start = (i / (n + 4)).clamp(0.0, 0.8);
          final anim = CurvedAnimation(parent: _c, curve: Interval(start, (start + 0.45).clamp(0.0, 1.0), curve: Curves.easeOutCubic));
          return FadeTransition(
            opacity: anim,
            child: SlideTransition(position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(anim), child: widget.children[i]),
          );
        }(),
    ]);
  }
}

/// Lema con letras espaciadas, como "INICIA SESIÓN PARA CONTINUAR".
class SpacedText extends StatelessWidget {
  const SpacedText(this.text, {super.key, this.size = 15, this.color = NetJobColors.subtle, this.spacing = 3.2});
  final String text;
  final double size;
  final Color color;
  final double spacing;
  @override
  Widget build(BuildContext context) => Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: size, letterSpacing: spacing, color: color, fontWeight: FontWeight.w500),
      );
}
