import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/theme.dart';

/// Abre las fotos en pantalla completa: deslizar a los lados para pasar de una a otra,
/// pellizcar o tocar dos veces para ampliar y deslizar hacia abajo para cerrar.
Future<void> openPhotoViewer(
  BuildContext context,
  List<String> urls, {
  int initial = 0,
  List<String?>? captions,
  String heroPrefix = 'foto',
}) {
  return Navigator.of(context, rootNavigator: true).push(PageRouteBuilder(
    opaque: false,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, _, _) => _PhotoViewer(urls: urls, initial: initial, captions: captions, heroPrefix: heroPrefix),
    transitionsBuilder: (_, anim, _, child) => FadeTransition(opacity: anim, child: child),
  ));
}

/// Etiqueta Hero común para la miniatura y la foto ampliada.
String photoHeroTag(String prefix, int index, String url) => '$prefix-$index-$url';

class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({required this.urls, required this.initial, required this.heroPrefix, this.captions});
  final List<String> urls;
  final int initial;
  final List<String?>? captions;
  final String heroPrefix;
  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final _page = PageController(initialPage: widget.initial);
  late int _index = widget.initial;
  final Map<int, TransformationController> _zoom = {};
  double _drag = 0; // desplazamiento vertical para cerrar
  bool _zoomed = false;

  TransformationController _ctrl(int i) => _zoom.putIfAbsent(i, () {
        final c = TransformationController();
        c.addListener(() {
          final z = c.value.getMaxScaleOnAxis() > 1.01;
          if (z != _zoomed && i == _index) setState(() => _zoomed = z);
        });
        return c;
      });

  @override
  void dispose() {
    _page.dispose();
    for (final c in _zoom.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _toggleZoom(int i, TapDownDetails? d) {
    final c = _ctrl(i);
    if (c.value.getMaxScaleOnAxis() > 1.01) {
      c.value = Matrix4.identity();
    } else {
      final p = d?.localPosition ?? Offset.zero;
      c.value = Matrix4.identity()
        ..translateByDouble(-p.dx * 1.5, -p.dy * 1.5, 0, 1)
        ..scaleByDouble(2.5, 2.5, 1, 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final caption = widget.captions != null && _index < widget.captions!.length ? widget.captions![_index] : null;
    final fade = (1 - (_drag.abs() / 400)).clamp(0.0, 1.0);
    TapDownDetails? lastTap;
    // En computador: Esc cierra y las flechas pasan de foto
    return Focus(
      autofocus: true,
      onKeyEvent: (_, e) {
        if (e is! KeyDownEvent) return KeyEventResult.ignored;
        if (e.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(context).pop();
          return KeyEventResult.handled;
        }
        if (e.logicalKey == LogicalKeyboardKey.arrowRight || e.logicalKey == LogicalKeyboardKey.arrowLeft) {
          final next = _index + (e.logicalKey == LogicalKeyboardKey.arrowRight ? 1 : -1);
          if (next >= 0 && next < widget.urls.length) {
            _page.animateToPage(next, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.94 * fade),
      body: Stack(children: [
        GestureDetector(
          // Deslizar hacia abajo (sin zoom) cierra el visor
          onVerticalDragUpdate: _zoomed ? null : (d) => setState(() => _drag += d.delta.dy),
          onVerticalDragEnd: _zoomed
              ? null
              : (d) {
                  if (_drag.abs() > 120 || d.velocity.pixelsPerSecond.dy.abs() > 900) {
                    Navigator.of(context).pop();
                  } else {
                    setState(() => _drag = 0);
                  }
                },
          child: Transform.translate(
            offset: Offset(0, _drag),
            child: PageView.builder(
              controller: _page,
              physics: _zoomed ? const NeverScrollableScrollPhysics() : const BouncingScrollPhysics(),
              itemCount: widget.urls.length,
              onPageChanged: (i) => setState(() {
                _index = i;
                _zoomed = false;
                _zoom[i]?.value = Matrix4.identity();
              }),
              itemBuilder: (_, i) => GestureDetector(
                onDoubleTapDown: (d) => lastTap = d,
                onDoubleTap: () => _toggleZoom(i, lastTap),
                child: InteractiveViewer(
                  transformationController: _ctrl(i),
                  minScale: 1,
                  maxScale: 5,
                  child: SizedBox.expand(
                    child: Hero(
                      tag: photoHeroTag(widget.heroPrefix, i, widget.urls[i]),
                      child: Image.network(
                        resolveUrl(widget.urls[i]),
                        fit: BoxFit.contain,
                        loadingBuilder: (_, child, p) => p == null ? child : const Center(child: CircularProgressIndicator()),
                        errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined, color: NetJobColors.muted, size: 64),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // Barra superior: cerrar y contador
        SafeArea(
          child: Opacity(
            opacity: fade,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(children: [
                IconButton.filled(
                  style: IconButton.styleFrom(backgroundColor: const Color(0x66000000), foregroundColor: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
                const Spacer(),
                if (widget.urls.length > 1)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(color: const Color(0x66000000), borderRadius: BorderRadius.circular(20)),
                    child: Text('${_index + 1} / ${widget.urls.length}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
              ]),
            ),
          ),
        ),
        // Pie: título de la foto y puntos de posición
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: Opacity(
              opacity: fade,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (caption != null && caption.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(caption,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontFamily: NetJobFonts.display, color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                    ),
                  if (widget.urls.length > 1)
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      for (var i = 0; i < widget.urls.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: i == _index ? 22 : 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: i == _index ? NetJobColors.primary : Colors.white38,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                    ]),
                ]),
              ),
            ),
          ),
        ),
      ]),
    ),
    );
  }
}

/// Miniatura que abre el visor al tocarla (con animación Hero hacia la foto grande).
class PhotoThumb extends StatelessWidget {
  const PhotoThumb({
    super.key,
    required this.urls,
    required this.index,
    this.captions,
    this.heroPrefix = 'foto',
    this.width,
    this.height,
    this.radius = 12,
  });
  final List<String> urls;
  final int index;
  final List<String?>? captions;
  final String heroPrefix;
  final double? width;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final url = urls[index];
    return GestureDetector(
      onTap: () => openPhotoViewer(context, urls, initial: index, captions: captions, heroPrefix: heroPrefix),
      child: Hero(
        tag: photoHeroTag(heroPrefix, index, url),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Image.network(
            resolveUrl(url),
            width: width,
            height: height,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              width: width,
              height: height,
              color: NetJobColors.cardHigh,
              child: const Icon(Icons.broken_image_outlined, color: NetJobColors.muted),
            ),
          ),
        ),
      ),
    );
  }
}
