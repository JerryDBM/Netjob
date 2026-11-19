import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../core/maps.dart';
import '../core/theme.dart';
import '../state/location_state.dart';
import '../core/colombia.dart';
import 'common.dart';
import 'place_picker.dart';

/// Zoom para que el círculo de [radiusKm] quepa completo en el lado más corto del mapa ([widthPx]).
double _zoomFor(double lat, double radiusKm, double widthPx) {
  final metersPerPx = radiusKm * 1000 * 1.15 / (widthPx / 2);
  return math.log(156543.03 * math.cos(lat * math.pi / 180) / metersPerPx) / math.ln2;
}

/// Icono "tú estás aquí": punto azul con borde blanco, de tamaño fijo en pantalla
/// (no crece al hacer zoom, a diferencia de un círculo en metros).
Future<BitmapDescriptor>? _meIcon;
Future<BitmapDescriptor> myLocationIcon() => _meIcon ??= () async {
      const size = 64.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      const c = Offset(size / 2, size / 2);
      canvas.drawCircle(c, size / 2, Paint()..color = NetJobColors.mapLine.withValues(alpha: 0.22));
      canvas.drawCircle(c, size * 0.28, Paint()..color = Colors.white);
      canvas.drawCircle(c, size * 0.2, Paint()..color = NetJobColors.mapLine);
      final img = await recorder.endRecording().toImage(size.toInt(), size.toInt());
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      return BitmapDescriptor.bytes(bytes!.buffer.asUint8List(), width: 22, height: 22);
    }();

/// Script de Maps + icono, una sola vez (evita parpadeos al reconstruir la pantalla).
Future<(bool, BitmapDescriptor?)>? _ready;
Future<(bool, BitmapDescriptor?)> _mapReady() => _ready ??= () async {
      final ok = await ensureMapsLoaded();
      return (ok, ok ? await myLocationIcon() : null);
    }();

/// Mapa con la ubicación del cliente, el radio de búsqueda y los profesionales cercanos.
/// Si Google Maps no está configurado, muestra una vista aproximada tipo radar.
class NearbyMap extends StatelessWidget {
  const NearbyMap({
    super.key,
    required this.lat,
    required this.lng,
    required this.radiusKm,
    required this.pros,
    this.height = 300,
    this.onProTap,
  });

  final double lat;
  final double lng;
  final double radiusKm;
  final List pros;
  final double height;
  final void Function(Map pro)? onProTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: height,
        child: FutureBuilder<(bool, BitmapDescriptor?)>(
          future: _mapReady(),
          builder: (context, snap) {
            if (mapsAvailable && !snap.hasData) return const Center(child: CircularProgressIndicator());
            if (snap.data?.$1 == true) return _google(snap.data!.$2!);
            return _RadarView(lat: lat, lng: lng, radiusKm: radiusKm, pros: pros, onProTap: onProTap);
          },
        ),
      ),
    );
  }

  Widget _google(BitmapDescriptor meIcon) {
    return LayoutBuilder(builder: (context, c) {
      final me = LatLng(lat, lng);
      return GoogleMap(
        style: netjobMapStyle,
        key: ValueKey('$lat,$lng,${pros.length}'),
        initialCameraPosition: CameraPosition(target: me, zoom: _zoomFor(lat, radiusKm, math.min(c.maxWidth, c.maxHeight))),
        myLocationButtonEnabled: false,
        zoomControlsEnabled: true,
        mapToolbarEnabled: false,
        // El mapa responde directo al dedo: arrastrar para moverse y pellizcar para zoom,
        // aunque esté dentro de una pantalla que se desplaza.
        webGestureHandling: WebGestureHandling.greedy,
        gestureRecognizers: _mapGestures,
        scrollGesturesEnabled: true,
        zoomGesturesEnabled: true,
        rotateGesturesEnabled: true,
        circles: {
          Circle(
            circleId: const CircleId('radio'),
            center: me,
            radius: radiusKm * 1000,
            strokeWidth: 2,
            strokeColor: NetJobColors.mapLine,
            fillColor: NetJobColors.mapLine.withValues(alpha: 0.08),
          ),
        },
        markers: {
          Marker(
            markerId: const MarkerId('yo'),
            position: me,
            icon: meIcon,
            anchor: const Offset(0.5, 0.5),
            infoWindow: const InfoWindow(title: 'Tú estás aquí'),
          ),
          for (final p in pros)
            if (p['lat'] != null && p['lng'] != null)
              Marker(
                markerId: MarkerId(p['id']),
                position: LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()),
                infoWindow: InfoWindow(
                  title: p['name'],
                  snippet: '${p['distanceKm']} km · toca para ver el perfil',
                  onTap: onProTap == null ? null : () => onProTap!(p),
                ),
              ),
        },
      );
    });
  }
}

/// Vista aproximada sin Google Maps: anillos de 4, 8 y 12 km con los profesionales.
class _RadarView extends StatelessWidget {
  const _RadarView({required this.lat, required this.lng, required this.radiusKm, required this.pros, this.onProTap});
  final double lat;
  final double lng;
  final double radiusKm;
  final List pros;
  final void Function(Map pro)? onProTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: NetJobColors.mapBg,
      child: LayoutBuilder(builder: (context, c) {
        final center = Offset(c.maxWidth / 2, c.maxHeight / 2);
        final r = math.min(c.maxWidth, c.maxHeight) / 2 - 18;
        final scale = r / radiusKm;
        return Stack(children: [
          Positioned.fill(child: CustomPaint(painter: _RingsPainter(center, r, radiusKm))),
          for (final p in pros)
            if (p['lat'] != null)
              () {
                final dx = ((p['lng'] as num) - lng) * math.cos(lat * math.pi / 180) * 111.32 * scale;
                final dy = ((p['lat'] as num) - lat) * 110.57 * scale;
                return Positioned(
                  left: center.dx + dx - 16,
                  top: center.dy - dy - 16,
                  child: Tooltip(
                    message: '${p['name']} · ${p['distanceKm']} km',
                    child: GestureDetector(
                      onTap: onProTap == null ? null : () => onProTap!(p),
                      child: Container(
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white, boxShadow: [BoxShadow(blurRadius: 4, color: Colors.black26)]),
                        padding: const EdgeInsets.all(2),
                        child: UserAvatar(url: p['avatarUrl'], name: p['name'], radius: 14),
                      ),
                    ),
                  ),
                );
              }(),
          Positioned(
            left: center.dx - 9,
            top: center.dy - 9,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: NetJobColors.mapLine,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black26)],
              ),
            ),
          ),
          Positioned(
            left: 10,
            bottom: 8,
            child: Text('Vista aproximada · radio de ${radiusKm.round()} km',
                style: const TextStyle(fontSize: 11, color: NetJobColors.mapInk, fontWeight: FontWeight.w600)),
          ),
        ]);
      }),
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter(this.center, this.r, this.radiusKm);
  final Offset center;
  final double r;
  final double radiusKm;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = NetJobColors.mapLine.withValues(alpha: 0.07);
    final line = Paint()
      ..color = NetJobColors.mapLine.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, r, fill);
    for (final km in [radiusKm / 3, radiusKm * 2 / 3, radiusKm]) {
      canvas.drawCircle(center, r * km / radiusKm, line..strokeWidth = km == radiusKm ? 2 : 1);
      final tp = TextPainter(
        text: TextSpan(text: '${km.round()} km', style: const TextStyle(fontSize: 10, color: NetJobColors.mapInk, fontWeight: FontWeight.w600)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, center + Offset(4, -r * km / radiusKm - 2));
    }
  }

  @override
  bool shouldRepaint(covariant _RingsPainter old) => old.center != center || old.r != r;
}

/// Mapa para que el profesional marque el punto central de su zona de trabajo.
class LocationPickerMap extends StatelessWidget {
  const LocationPickerMap({super.key, required this.lat, required this.lng, required this.onChanged, this.height = 220});
  final double? lat;
  final double? lng;
  final void Function(double lat, double lng) onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (!mapsAvailable) return const SizedBox.shrink();
    final target = LatLng(lat ?? 4.6533, lng ?? -74.0836);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: height,
        child: FutureBuilder<bool>(
          future: ensureMapsLoaded(),
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            if (snap.data != true) return const SizedBox.shrink();
            return GoogleMap(
              style: netjobMapStyle,
              key: ValueKey('$lat,$lng'),
              initialCameraPosition: CameraPosition(target: target, zoom: lat == null ? 5.5 : 13),
              myLocationButtonEnabled: false,
              mapToolbarEnabled: false,
              webGestureHandling: WebGestureHandling.greedy,
              gestureRecognizers: _mapGestures,
              onTap: (p) => onChanged(p.latitude, p.longitude),
              markers: {
                if (lat != null && lng != null)
                  Marker(
                    markerId: const MarkerId('zona'),
                    position: target,
                    draggable: true,
                    onDragEnd: (p) => onChanged(p.latitude, p.longitude),
                  ),
              },
            );
          },
        ),
      ),
    );
  }
}

/// Barra "Buscando cerca de: Cartagena · Cambiar".
class LocationBar extends StatelessWidget {
  const LocationBar({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocationState>();
    final text = switch (loc.status) {
      LocationStatus.loading when !loc.hasLocation => 'Obteniendo tu ubicación…',
      _ when loc.hasLocation => '${loc.label}${loc.manual ? ' (elegida)' : ''}',
      _ => 'Elige tu ubicación',
    };
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => showLocationSheet(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Icon(loc.manual ? Icons.location_city : Icons.my_location, size: 18, color: NetJobColors.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(text, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          const Icon(Icons.expand_more, size: 20),
        ]),
      ),
    );
  }
}

/// Hoja para cambiar la ubicación: GPS del dispositivo o una ciudad.
Future<void> showLocationSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) {
      final loc = sheet.watch<LocationState>();
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(sheet).size.height * 0.75),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
            Text('¿Dónde necesitas el servicio?', style: Theme.of(sheet).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Te mostramos profesionales a máximo 12 km.', style: TextStyle(color: NetJobColors.subtle)),
            if (loc.message != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFFBEBDA), borderRadius: BorderRadius.circular(10)),
                child: Text(loc.message!, style: const TextStyle(fontSize: 13)),
              ),
            ],
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.my_location, color: NetJobColors.primary),
              title: const Text('Usar mi ubicación actual'),
              subtitle: const Text('Se actualiza sola si te mueves'),
              trailing: loc.status == LocationStatus.loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : null,
              onTap: () async {
                await loc.useDeviceLocation();
                if (sheet.mounted && loc.status == LocationStatus.ok) Navigator.pop(sheet);
              },
            ),
            const Divider(),
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 6, 4, 10),
              child: Text('O elige el municipio', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            ),
            _MunicipioChooser(onChosen: (dept, city) {
              final c = municipioCoords(dept, city);
              if (c == null) return;
              loc.setManual(c.$1, c.$2, city);
              Navigator.pop(sheet);
            }),
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 16, 4, 8),
              child: Text('Ciudades principales', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            ),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in colombianCities.take(10))
                ChoiceChip(
                  label: Text(c.$1),
                  selected: loc.manual && loc.label == c.$1,
                  onSelected: (_) {
                    loc.setManual(c.$2, c.$3, c.$1);
                    Navigator.pop(sheet);
                  },
                ),
            ]),
          ]),
        ),
      );
    },
  );
}

/// Departamento → Municipio dentro de la hoja de ubicación.
class _MunicipioChooser extends StatefulWidget {
  const _MunicipioChooser({required this.onChosen});
  final void Function(String department, String city) onChosen;
  @override
  State<_MunicipioChooser> createState() => _MunicipioChooserState();
}

class _MunicipioChooserState extends State<_MunicipioChooser> {
  String? _dept;
  String? _city;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DepartmentCityPicker(
        department: _dept,
        city: _city,
        decorate: (w) => Container(
          decoration: BoxDecoration(color: const Color(0xFFE6E9DE), borderRadius: BorderRadius.circular(18)),
          child: w,
        ),
        onChanged: (d, c) {
          setState(() {
            _dept = d;
            _city = c;
          });
          if (d != null && c != null) widget.onChosen(d, c);
        },
      ),
    ]);
  }
}

/// El mapa se queda con los gestos (arrastrar, pellizcar, rotar) en lugar de la lista
/// que lo contiene; así se puede mover con los dedos.
final Set<Factory<OneSequenceGestureRecognizer>> _mapGestures = {
  Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
};
