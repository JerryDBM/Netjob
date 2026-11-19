import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import '../../core/api.dart';
import '../../core/maps.dart';
import '../../core/realtime.dart';
import '../../core/theme.dart';
import '../../state/location_state.dart';
import '../../widgets/common.dart';
import '../../widgets/maps.dart';

/// Seguimiento para el cliente: dónde va el profesional mientras se dirige a su casa.
/// Solo hay ubicación cuando el profesional indicó "Voy en camino" y hasta que llega.
class TrackScreen extends StatefulWidget {
  const TrackScreen({super.key, required this.requestId});
  final String requestId;
  @override
  State<TrackScreen> createState() => _TrackScreenState();
}

class _TrackScreenState extends State<TrackScreen> {
  Map? _r;
  Object? _error;
  GoogleMapController? _map;
  void Function()? _unwatch;
  Timer? _poll;
  Timer? _tick;

  LatLng? _pro; // última posición del profesional
  DateTime? _at; // cuándo se recibió
  bool _fitted = false;

  // Ruta por calles (para el tiempo estimado); si no hay, línea recta
  List<LatLng> _points = [];
  double? _routeMeters;
  double? _routeSeconds;
  DateTime _lastRoute = DateTime(2000);
  bool _routing = false;

  final Future<(bool, BitmapDescriptor?)> _mapReady = () async {
    final ok = await ensureMapsLoaded();
    return (ok, ok ? await myLocationIcon() : null);
  }();

  Map? get _trip => _r?['trip'] as Map?;
  bool get _enRoute => _trip?['enRoute'] == true;
  LatLng? get _home => _r?['lat'] == null ? null : LatLng((_r!['lat'] as num).toDouble(), (_r!['lng'] as num).toDouble());

  @override
  void initState() {
    super.initState();
    _load();
    _unwatch = Realtime.instance.watchRequest(widget.requestId, onUpdated: _load, onLocation: _onLocation);
    // Respaldo si el socket no está disponible, y refresco del "hace X s"
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _load());
    _tick = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _unwatch?.call();
    _poll?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Api.instance.get('/requests/${widget.requestId}') as Map;
      if (!mounted) return;
      final t = r['trip'] as Map?;
      setState(() {
        _r = r;
        _error = null;
        if (t?['enRoute'] == true && t?['lat'] != null) {
          final at = DateTime.tryParse('${t!['at']}')?.toLocal();
          // No se retrocede a una posición más vieja que la recibida por el socket
          if (_at == null || at == null || !at.isBefore(_at!)) {
            _pro = LatLng((t['lat'] as num).toDouble(), (t['lng'] as num).toDouble());
            _at = at ?? DateTime.now();
          }
        } else if (t?['enRoute'] != true) {
          _pro = null;
          _points = [];
        }
      });
      _afterPosition();
    } catch (e) {
      if (mounted && _r == null) setState(() => _error = e);
    }
  }

  void _onLocation(double lat, double lng, DateTime at) {
    if (!mounted) return;
    setState(() {
      _pro = LatLng(lat, lng);
      _at = at;
    });
    _afterPosition();
  }

  void _afterPosition() {
    if (_pro == null) return;
    if (!_fitted) _fit(animate: false);
    _route();
  }

  /// Ruta por calles desde el profesional hasta la casa (como mucho una vez por minuto).
  Future<void> _route() async {
    final a = _pro;
    final b = _home;
    if (a == null || b == null || _routing) return;
    if (DateTime.now().difference(_lastRoute).inSeconds < 60) return;
    _routing = true;
    _lastRoute = DateTime.now();
    try {
      final r = await Api.instance.get('/routes', {'fromLat': a.latitude, 'fromLng': a.longitude, 'toLat': b.latitude, 'toLng': b.longitude}) as Map;
      if (!mounted) return;
      setState(() {
        _points = [for (final p in r['points']) LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble())];
        _routeMeters = (r['distance'] as num).toDouble();
        _routeSeconds = (r['duration'] as num).toDouble();
      });
    } catch (_) {
      // Sin ruta por calles se estima en línea recta
    } finally {
      _routing = false;
    }
  }

  double? get _meters {
    final a = _pro;
    final b = _home;
    if (a == null || b == null) return null;
    final straight = distanceKm(a.latitude, a.longitude, b.latitude, b.longitude) * 1000;
    // La ruta se pide cada minuto: entre tanto se ajusta con la distancia en línea recta
    if (_routeMeters != null && _points.isNotEmpty) {
      final atRoute = distanceKm(_points.first.latitude, _points.first.longitude, b.latitude, b.longitude) * 1000;
      return atRoute <= 0 ? _routeMeters : math.max(0, _routeMeters! * (straight / atRoute));
    }
    return straight * 1.35;
  }

  int? get _minutes {
    final m = _meters;
    if (m == null) return null;
    final speed = (_routeSeconds != null && _routeMeters != null && _routeSeconds! > 0) ? _routeMeters! / _routeSeconds! : 7.0; // m/s
    return math.max(1, (m / speed / 60).round());
  }

  /// Encuadra al profesional y la casa. El primer encuadre va sin animación: en web, animar
  /// la cámara antes de que el mapa termine de cargar lo deja en blanco.
  void _fit({bool animate = true}) {
    final a = _pro;
    final b = _home;
    if (_map == null || a == null) return;
    _fitted = true;
    if (b == null) {
      final u = CameraUpdate.newLatLngZoom(a, 15);
      animate ? _map!.animateCamera(u) : _map!.moveCamera(u);
      return;
    }
    final south = math.min(a.latitude, b.latitude);
    final north = math.max(a.latitude, b.latitude);
    // La tarjeta inferior tapa casi la mitad del mapa: se amplía el encuadre hacia el sur
    // para que el profesional y la casa queden en la parte visible.
    final span = math.max(north - south, 0.004);
    final bounds = LatLngBounds(
      southwest: LatLng(south - span * 1.1, math.min(a.longitude, b.longitude)),
      northeast: LatLng(north + span * 0.15, math.max(a.longitude, b.longitude)),
    );
    final u = CameraUpdate.newLatLngBounds(bounds, 40);
    animate ? _map!.animateCamera(u) : _map!.moveCamera(u);
  }

  String _ago() {
    final at = _at;
    if (at == null) return '';
    final s = DateTime.now().difference(at).inSeconds;
    if (s < 15) return 'Actualizado ahora';
    if (s < 60) return 'Actualizado hace $s s';
    return 'Actualizado hace ${(s / 60).round()} min';
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    if (r == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Seguimiento')),
        body: _error != null
            ? EmptyState(icon: Icons.error_outline, title: 'No se pudo cargar', message: '$_error', action: FilledButton(onPressed: _load, child: const Text('Reintentar')))
            : const Center(child: CircularProgressIndicator()),
      );
    }
    final pro = r['professional']['user'] as Map;
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(child: _mapView(pro)),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(children: [
                _round(Icons.arrow_back_rounded, 'Volver', () => context.canPop() ? context.pop() : context.go('/requests/${widget.requestId}')),
                const Spacer(),
                if (_pro != null) _round(Icons.center_focus_strong_rounded, 'Ver todo el recorrido', _fit),
              ]),
            ),
          ),
        ),
        Positioned(left: 12, right: 12, bottom: 14, child: SafeArea(top: false, child: _panel(r, pro))),
      ]),
    );
  }

  Widget _round(IconData icon, String tooltip, VoidCallback onTap) => Tooltip(
        message: tooltip,
        child: Material(
          color: NetJobColors.card.withValues(alpha: 0.96),
          shape: const CircleBorder(side: BorderSide(color: NetJobColors.border)),
          elevation: 4,
          child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: SizedBox(width: 48, height: 48, child: Icon(icon, color: NetJobColors.ink))),
        ),
      );

  /// Tarjeta inferior: quién viene, a qué distancia y en cuánto llega.
  Widget _panel(Map r, Map pro) {
    final name = (pro['name'] as String).split(' ').first;
    final arrived = _trip?['arrivedAt'] != null;
    final m = _meters;
    final min = _minutes;
    final stale = _at != null && DateTime.now().difference(_at!).inMinutes >= 2;

    late final IconData icon;
    late final Color color;
    late final String title;
    late final String body;
    if (_enRoute && _pro != null) {
      icon = Icons.navigation_rounded;
      color = NetJobColors.mint;
      title = '$name va en camino';
      body = m == null
          ? 'Sigue su recorrido en el mapa.'
          : 'A ${m < 1000 ? '${(m / 10).round() * 10} m' : '${(m / 1000).toStringAsFixed(1)} km'} de tu dirección';
    } else if (_enRoute) {
      icon = Icons.navigation_rounded;
      color = NetJobColors.mint;
      title = '$name va en camino';
      body = 'Aún no recibimos su ubicación. Aparecerá aquí en cuanto su celular la comparta.';
    } else if (arrived) {
      icon = Icons.flag_rounded;
      color = NetJobColors.primary;
      title = '$name llegó';
      body = 'Tu profesional ya está en la dirección del servicio.';
    } else {
      icon = Icons.schedule_rounded;
      color = NetJobColors.warning;
      title = 'Aún no va en camino';
      body = 'Podrás ver su ubicación cuando $name indique que salió hacia tu dirección. Te avisaremos.';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: NetJobColors.card.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: NetJobColors.border),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 20, offset: Offset(0, 6))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          UserAvatar(url: pro['avatarUrl'], name: pro['name'], radius: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 6),
                Flexible(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
              ]),
              const SizedBox(height: 2),
              Text(body, style: const TextStyle(color: NetJobColors.subtle, fontSize: 13.5, height: 1.3)),
            ]),
          ),
        ]),
        if (_enRoute && _pro != null && min != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: NetJobColors.cardHigh, borderRadius: BorderRadius.circular(18)),
            child: Row(children: [
              _metric('$min', 'min aprox.'),
              _metric(DateFormat('h:mm a', 'es').format(DateTime.now().add(Duration(minutes: min))), 'llegada'),
            ]),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Icon(stale ? Icons.signal_wifi_statusbar_connected_no_internet_4_rounded : Icons.sensors_rounded,
                size: 14, color: stale ? NetJobColors.warning : NetJobColors.muted),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                stale ? '${_ago()} · puede que no tenga señal' : _ago(),
                style: TextStyle(fontSize: 12, color: stale ? NetJobColors.warning : NetJobColors.muted),
              ),
            ),
          ]),
        ],
        const SizedBox(height: 12),
        Row(children: [
          const Icon(Icons.home_rounded, size: 18, color: NetJobColors.muted),
          const SizedBox(width: 6),
          Expanded(child: Text(r['address'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: NetJobColors.textSoft))),
        ]),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => context.push('/requests/${widget.requestId}/chat', extra: pro['name']),
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            label: Text('Escribirle a $name'),
          ),
        ),
      ]),
    );
  }

  Widget _metric(String value, String label) => Expanded(
        child: Column(children: [
          Text(value, style: TextStyle(fontFamily: NetJobFonts.display, fontSize: 24, fontWeight: FontWeight.w800, color: NetJobColors.ink)),
          Text(label, style: const TextStyle(fontSize: 12.5, color: NetJobColors.subtle, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _mapView(Map pro) {
    final home = _home;
    final p = _pro;
    if (!mapsAvailable || (home == null && p == null)) return _fallback();
    return FutureBuilder<(bool, BitmapDescriptor?)>(
      future: _mapReady,
      builder: (context, snap) {
        if (!snap.hasData) return const ColoredBox(color: NetJobColors.mapBg, child: Center(child: CircularProgressIndicator()));
        if (snap.data!.$1 != true) return _fallback();
        final line = _points.length > 1 ? [?p, ..._points.skip(1)] : [?p, ?home];
        return GoogleMap(
          style: netjobMapStyle,
          initialCameraPosition: CameraPosition(target: p ?? home!, zoom: 14),
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          compassEnabled: false,
          webGestureHandling: WebGestureHandling.greedy,
          gestureRecognizers: {Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer())},
          padding: const EdgeInsets.only(bottom: 260, top: 70),
          onMapCreated: (c) {
            _map = c;
            // Al abrir la pantalla directamente, el mapa puede no tener tamaño todavía y el
            // primer encuadre no surte efecto: se repite hasta que termine de cargar.
            for (final ms in const [400, 1500, 3500]) {
              Future.delayed(Duration(milliseconds: ms), () {
                if (mounted && _pro != null) _fit(animate: false);
              });
            }
          },
          polylines: {
            if (p != null && line.length > 1) ...[
              Polyline(polylineId: const PolylineId('borde'), points: line, width: 10, color: Colors.white, zIndex: 1),
              Polyline(
                polylineId: const PolylineId('ruta'),
                points: line,
                width: 6,
                color: NetJobColors.mapLine,
                zIndex: 2,
                startCap: Cap.roundCap,
                endCap: Cap.roundCap,
                jointType: JointType.round,
              ),
            ],
          },
          markers: {
            if (home != null)
              Marker(
                markerId: const MarkerId('casa'),
                position: home,
                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
                infoWindow: const InfoWindow(title: 'Tu dirección'),
              ),
            if (p != null)
              Marker(
                markerId: const MarkerId('profesional'),
                position: p,
                icon: snap.data!.$2!,
                anchor: const Offset(0.5, 0.5),
                zIndexInt: 3,
                infoWindow: InfoWindow(title: pro['name']),
              ),
          },
        );
      },
    );
  }

  /// Sin Google Maps (por ejemplo en Windows): se informa la distancia sin mapa.
  Widget _fallback() => Container(
        color: NetJobColors.mapBg,
        alignment: const Alignment(0, -0.45),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(_enRoute ? Icons.directions_car_filled_rounded : Icons.map_outlined, size: 96, color: const Color(0xFFB9C9BD)),
          const SizedBox(height: 10),
          Text(
            mapsAvailable ? 'Esperando la ubicación…' : 'El mapa no está disponible en este dispositivo',
            style: const TextStyle(color: NetJobColors.mapInk, fontWeight: FontWeight.w700),
          ),
        ]),
      );
}
