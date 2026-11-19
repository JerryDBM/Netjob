import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/maps.dart';
import '../../core/theme.dart';
import '../../state/location_state.dart';
import '../../widgets/common.dart';
import '../../widgets/maps.dart';

/// Navegación del profesional hasta el domicilio del cliente, dentro de NetJob:
/// ruta por calles, indicaciones giro a giro, cámara que sigue al profesional,
/// recálculo si se sale de la ruta y aviso al llegar.
///
/// Al tocar "Voy en camino" se avisa al cliente y se comparte la ubicación con él
/// hasta llegar (o hasta terminar la navegación). Fuera de ese trayecto no se comparte nada.
class RouteScreen extends StatefulWidget {
  const RouteScreen({super.key, required this.requestId});
  final String requestId;
  @override
  State<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends State<RouteScreen> {
  Map? _r;
  Object? _error;
  GoogleMapController? _map;
  final Future<(bool, BitmapDescriptor?)> _mapReady = () async {
    final ok = await ensureMapsLoaded();
    return (ok, ok ? await myLocationIcon() : null);
  }();

  LatLng? _me; // posición actual del profesional
  double _heading = 0;
  bool _live = false; // ¿tenemos GPS real?
  StreamSubscription<Position>? _gps;

  // Ruta
  List<LatLng> _points = [];
  List<Map> _steps = [];
  double _routeMeters = 0;
  double _routeSeconds = 0;
  int _nearest = 0; // índice del punto de la ruta más cercano
  int _step = 0; // índice de la próxima maniobra
  bool _routing = false;
  DateTime _lastReroute = DateTime(2000);
  String? _routeError;

  bool _navigating = false;
  bool _autoMove = false; // la cámara la está moviendo la app (no el dedo)
  bool _follow = true;
  bool _arrived = false;

  // Trayecto compartido con el cliente
  bool _sharing = false;
  bool _tripBusy = false;
  DateTime _lastSent = DateTime(2000);

  LatLng? get _dest => _r?['lat'] == null ? null : LatLng((_r!['lat'] as num).toDouble(), (_r!['lng'] as num).toDouble());

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _gps?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Api.instance.get('/requests/${widget.requestId}') as Map;
      if (!mounted) return;
      setState(() => _r = r);
      await _locate();
      await _route();
      // Si ya iba en camino (por ejemplo, cerró y volvió a abrir la pantalla), se retoma
      if ((r['trip'] as Map?)?['enRoute'] == true && mounted) {
        setState(() {
          _sharing = true;
          _navigating = true;
        });
        if (!_live) _listenGps();
        _camera(animate: true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Ubicación inicial: GPS; si no hay, el centro de la zona del profesional.
  Future<void> _locate() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm != LocationPermission.denied && perm != LocationPermission.deniedForever) {
        final p = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 12)),
        );
        _me = LatLng(p.latitude, p.longitude);
        _live = true;
        _listenGps();
        return;
      }
    } catch (_) {}
    final me = await Api.instance.get('/professionals/me/profile') as Map;
    if (me['lat'] != null) _me = LatLng((me['lat'] as num).toDouble(), (me['lng'] as num).toDouble());
  }

  void _listenGps() {
    _gps?.cancel();
    _gps = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 3),
    ).listen(_onPosition, onError: (_) {});
  }

  void _onPosition(Position p) {
    final prev = _me;
    final now = LatLng(p.latitude, p.longitude);
    if (prev != null && _meters(prev, now) > 2) _heading = _bearing(prev, now);
    if (p.heading > 0 && p.speed > 1.5) _heading = p.heading;
    _me = now;
    _live = true;
    _progress();
    _share(now);
    if (mounted) setState(() {});
    if (_navigating && _follow) _camera(animate: true);
  }

  /// Pide la ruta por calles al backend (que usa OSRM).
  Future<void> _route() async {
    final a = _me;
    final b = _dest;
    if (a == null || b == null || _routing) return;
    _routing = true;
    _lastReroute = DateTime.now();
    try {
      final r = await Api.instance.get('/routes', {
        'fromLat': a.latitude, 'fromLng': a.longitude, 'toLat': b.latitude, 'toLng': b.longitude,
      }) as Map;
      _points = [for (final p in r['points']) LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble())];
      _steps = (r['steps'] as List).cast<Map>();
      _routeMeters = (r['distance'] as num).toDouble();
      _routeSeconds = (r['duration'] as num).toDouble();
      _nearest = 0;
      _step = _steps.length > 1 ? 1 : 0;
      _routeError = null;
      _progress();
    } catch (e) {
      // Sin ruta por calles: se muestra la línea recta para orientarse
      _points = [a, b];
      _steps = [];
      _routeMeters = _meters(a, b) * 1.35;
      _routeSeconds = _routeMeters / 1000 / 28 * 3600;
      _routeError = '$e';
    } finally {
      _routing = false;
    }
    if (!mounted) return;
    setState(() {});
    if (!_navigating) _overview();
  }

  /// Avanza en la ruta según la posición: punto más cercano, próxima maniobra,
  /// llegada y recálculo si el profesional se sale del camino.
  void _progress() {
    final me = _me;
    if (me == null || _points.length < 2) return;
    var best = _nearest;
    var bestD = double.infinity;
    final from = math.max(0, _nearest - 5);
    for (var i = from; i < _points.length; i++) {
      final d = _meters(me, _points[i]);
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    _nearest = best;
    // Siguiente maniobra: la primera cuyo punto aún no se ha pasado
    while (_step < _steps.length - 1 && _meters(me, _stepPoint(_step)) < 25) {
      _step++;
    }
    final dest = _dest;
    if (dest != null && _meters(me, dest) < 40 && _navigating && !_arrived) {
      _arrived = true;
      _follow = false;
      _trip('arrive');
    }
    final off = bestD > 55;
    if (off && _live && _navigating && DateTime.now().difference(_lastReroute).inSeconds > 12) {
      _route();
    }
  }

  LatLng _stepPoint(int i) => LatLng((_steps[i]['lat'] as num).toDouble(), (_steps[i]['lng'] as num).toDouble());

  double get _remainingMeters {
    final me = _me;
    if (me == null || _points.length < 2) return _routeMeters;
    var d = _meters(me, _points[math.min(_nearest, _points.length - 1)]);
    for (var i = _nearest; i < _points.length - 1; i++) {
      d += _meters(_points[i], _points[i + 1]);
    }
    return d;
  }

  int get _remainingMinutes {
    final speed = _routeSeconds > 0 ? _routeMeters / _routeSeconds : 7.8; // m/s
    return math.max(1, (_remainingMeters / speed / 60).round());
  }

  // ---------- Cámara ----------

  void _overview() {
    final a = _me;
    final b = _dest;
    if (_map == null || b == null) return;
    if (a == null) {
      _map!.animateCamera(CameraUpdate.newLatLngZoom(b, 15));
      return;
    }
    final pts = _points.isEmpty ? [a, b] : _points;
    var s = pts.first.latitude, n = s, w = pts.first.longitude, e = w;
    for (final p in pts) {
      s = math.min(s, p.latitude);
      n = math.max(n, p.latitude);
      w = math.min(w, p.longitude);
      e = math.max(e, p.longitude);
    }
    final size = MediaQuery.of(context).size;
    final freeH = math.max(120.0, size.height - 470);
    final freeW = math.max(120.0, size.width - 120);
    final midLat = (s + n) / 2;
    final mpp = math.max(math.max((n - s) * 110570 / freeH, (e - w) * 111320 * math.cos(midLat * math.pi / 180) / freeW) * 1.3, 0.5);
    final zoom = (math.log(156543.03 * math.cos(midLat * math.pi / 180) / mpp) / math.ln2).clamp(3.0, 18.0);
    _autoMove = true;
    _map!.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(target: LatLng(midLat, (w + e) / 2), zoom: zoom)));
  }

  void _camera({bool animate = false}) {
    final me = _me;
    if (_map == null || me == null) return;
    final pos = CameraPosition(target: me, zoom: 17.5, tilt: 50, bearing: _heading);
    _autoMove = true;
    animate ? _map!.animateCamera(CameraUpdate.newCameraPosition(pos)) : _map!.moveCamera(CameraUpdate.newCameraPosition(pos));
  }

  /// Envía la posición al cliente, como máximo cada 4 segundos.
  void _share(LatLng pos) {
    if (!_sharing || _arrived) return;
    final now = DateTime.now();
    if (now.difference(_lastSent).inSeconds < 4) return;
    _lastSent = now;
    Api.instance.post('/requests/${widget.requestId}/trip/location', {'lat': pos.latitude, 'lng': pos.longitude}).ignore();
  }

  /// Avisa al backend: voy en camino (start), llegué (arrive) o dejé de ir (stop).
  Future<bool> _trip(String action) async {
    if (_tripBusy) return false;
    _tripBusy = true;
    try {
      final me = _me;
      await Api.instance.post('/requests/${widget.requestId}/trip', {
        'action': action,
        if (action == 'start' && _live && me != null) 'lat': me.latitude,
        if (action == 'start' && _live && me != null) 'lng': me.longitude,
      });
      if (mounted) setState(() => _sharing = action == 'start');
      return true;
    } on ApiException catch (e) {
      // 409: todavía no se puede avisar (el cliente no ha pagado la visita) o ya se había marcado
      if (mounted && action == 'start') toast(context, e.message);
      if (mounted && action != 'start') setState(() => _sharing = false);
      return false;
    } catch (_) {
      return false;
    } finally {
      _tripBusy = false;
    }
  }

  /// "Voy en camino": avisa al cliente, empieza a compartir la ubicación y arranca la guía.
  Future<void> _start() async {
    setState(() {
      _navigating = true;
      _follow = true;
      _arrived = false;
    });
    if (!_live) _listenGps();
    _camera(animate: true);
    final ok = await _trip('start');
    if (ok && mounted) {
      toast(context, _live ? 'Avisamos al cliente que vas en camino. Verá tu ubicación hasta que llegues.' : 'Avisamos al cliente que vas en camino.', error: false);
    }
  }

  Future<void> _stop() async {
    setState(() {
      _navigating = false;
      _follow = true;
    });
    _overview();
    if (_sharing && !_arrived) await _trip('stop');
  }

  /// Llegada marcada a mano (por si el GPS no es preciso en la puerta del cliente).
  Future<void> _markArrived() async {
    setState(() {
      _arrived = true;
      _follow = false;
    });
    await _trip('arrive');
  }

  // ---------- Interfaz ----------

  @override
  Widget build(BuildContext context) {
    final r = _r;
    if (r == null) {
      return Scaffold(
        appBar: AppBar(),
        body: _error != null
            ? EmptyState(icon: Icons.error_outline, title: 'No se pudo cargar', message: '$_error')
            : const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(child: _mapView()),
        Positioned(top: 0, left: 0, right: 0, child: SafeArea(child: _topBanner(r))),
        Positioned(
          right: 14,
          top: MediaQuery.of(context).size.height * 0.4,
          child: Column(children: [
            if (_navigating && !_follow) ...[
              _roundButton(Icons.navigation_rounded, 'Seguir mi ubicación', () {
                setState(() => _follow = true);
                _camera(animate: true);
              }, highlight: true),
              const SizedBox(height: 12),
            ],
            _roundButton(Icons.chat_bubble_rounded, 'Chat con el cliente',
                () => context.push('/requests/${widget.requestId}/chat', extra: r['client']['name'])),
            const SizedBox(height: 12),
            _roundButton(Icons.alt_route_rounded, 'Ver toda la ruta', () {
              setState(() => _follow = false);
              _overview();
            }),
          ]),
        ),
        Positioned(left: 14, right: 14, bottom: 16, child: SafeArea(top: false, child: _bottom())),
      ]),
    );
  }

  Widget _topBanner(Map r) {
    final hasStep = _navigating && _steps.isNotEmpty && !_arrived;
    final step = hasStep ? _steps[_step] : null;
    final distToStep = (step != null && _me != null) ? _meters(_me!, _stepPoint(_step)) : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.fromLTRB(14, 12, 18, 18),
        decoration: BoxDecoration(
          gradient: hasStep ? NetJobColors.heroGradient : null,
          color: hasStep ? null : NetJobColors.slate.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: NetJobColors.border),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 20, offset: Offset(0, 8))],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            IconButton(
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            ),
            const Spacer(),
            if (_sharing && !_arrived)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: const Color(0x336DFFB4), borderRadius: BorderRadius.circular(20)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.sensors_rounded, size: 15, color: NetJobColors.mint),
                  SizedBox(width: 5),
                  Text('El cliente ve tu ubicación', style: TextStyle(color: NetJobColors.mint, fontSize: 12.5, fontWeight: FontWeight.w700)),
                ]),
              ),
            if (_routing) ...[
              const SizedBox(width: 10),
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            ],
          ]),
          if (_arrived) ...[
            Text('Llegaste', style: TextStyle(fontFamily: NetJobFonts.display, color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(r['address'], style: const TextStyle(color: NetJobColors.textSoft, fontSize: 18)),
          ] else if (step != null) ...[
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Icon(_maneuverIcon(step['type'], step['modifier']), color: Colors.white, size: 54),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_fmtDistance(distToStep ?? 0),
                      style: TextStyle(fontFamily: NetJobFonts.display, color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800)),
                  Text(step['text'], style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600, height: 1.2)),
                ]),
              ),
            ]),
            if (_step + 1 < _steps.length) ...[
              const SizedBox(height: 10),
              Text('Luego: ${_steps[_step + 1]['text']}', style: const TextStyle(color: NetJobColors.subtle, fontSize: 14)),
            ],
          ] else ...[
            Text(_fmtDistance(_remainingMeters),
                style: TextStyle(fontFamily: NetJobFonts.display, color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: NetJobColors.mint, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.home_rounded, color: NetJobColors.onPrimary, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(r['address'], style: const TextStyle(color: NetJobColors.textSoft, fontSize: 20, fontWeight: FontWeight.w600, height: 1.2))),
            ]),
            const SizedBox(height: 8),
            Text('${r['client']['name']} · ${fmtDateTime(r['scheduledAt'])}', style: const TextStyle(color: NetJobColors.subtle, fontSize: 14.5)),
            if (_routeError != null)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('No pudimos trazar la ruta por calles; se muestra la dirección en línea recta.',
                    style: TextStyle(color: NetJobColors.warning, fontSize: 12.5)),
              ),
          ],
        ]),
      ),
    );
  }

  Widget _bottom() {
    final arrival = DateTime.now().add(Duration(minutes: _remainingMinutes));
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: NetJobColors.card.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: NetJobColors.border),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 20, offset: Offset(0, 6))],
        ),
        child: Row(children: [
          _metric(DateFormat('h:mm', 'es').format(arrival), 'llegada', NetJobColors.subtle),
          _metric('$_remainingMinutes', 'min', NetJobColors.primary),
          _metric(_remainingMeters < 1000 ? '${_remainingMeters.round()}' : (_remainingMeters / 1000).toStringAsFixed(1),
              _remainingMeters < 1000 ? 'm' : 'km', NetJobColors.mint),
        ]),
      ),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        child: _arrived
            ? FilledButton.icon(
                onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Volver a la solicitud'),
              )
            : _navigating
                ? Row(children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(backgroundColor: NetJobColors.bgSoft, foregroundColor: NetJobColors.danger),
                      onPressed: _stop,
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('Terminar'),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _markArrived,
                        icon: const Icon(Icons.flag_rounded),
                        label: const Text('Ya llegué'),
                      ),
                    ),
                  ])
                : FilledButton.icon(
                    onPressed: _points.isEmpty ? null : _start,
                    icon: const Icon(Icons.navigation_rounded),
                    label: const Text('Voy en camino'),
                  ),
      ),
      if (!_navigating && !_arrived)
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('Al tocar "Voy en camino" avisamos al cliente y verá tu ubicación hasta que llegues.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: NetJobColors.ink, backgroundColor: Color(0xCC0D0716))),
        ),
      if (!_live)
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('Sin GPS: la ruta parte del centro de tu zona. Activa la ubicación para guiarte en tiempo real.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: NetJobColors.ink, backgroundColor: Color(0xCC0D0716))),
        ),
    ]);
  }

  Widget _metric(String value, String label, Color labelColor) => Expanded(
        child: Column(children: [
          Text(value, style: TextStyle(fontFamily: NetJobFonts.display, fontSize: 28, fontWeight: FontWeight.w800, color: NetJobColors.ink)),
          Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: labelColor)),
        ]),
      );

  Widget _roundButton(IconData icon, String tooltip, VoidCallback onTap, {bool highlight = false}) => Tooltip(
        message: tooltip,
        child: Material(
          color: highlight ? NetJobColors.primary : NetJobColors.card.withValues(alpha: 0.95),
          shape: const CircleBorder(side: BorderSide(color: NetJobColors.border)),
          elevation: 4,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 60, height: 60, child: Icon(icon, color: highlight ? NetJobColors.onPrimary : NetJobColors.ink, size: 26)),
          ),
        ),
      );

  Widget _mapView() {
    final dest = _dest;
    if (!mapsAvailable || dest == null) {
      return Container(
        color: NetJobColors.mapBg,
        alignment: Alignment.center,
        child: const Icon(Icons.map_outlined, size: 120, color: Color(0xFFC9BDE0)),
      );
    }
    return FutureBuilder<(bool, BitmapDescriptor?)>(
      future: _mapReady,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        if (snap.data!.$1 != true) return Container(color: NetJobColors.mapBg);
        final me = _me;
        final remaining = _points.length > 1 ? [?me, ..._points.sublist(math.min(_nearest + 1, _points.length - 1))] : _points;
        return GoogleMap(
          style: netjobMapStyle,
          initialCameraPosition: CameraPosition(target: me ?? dest, zoom: 14),
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          compassEnabled: false,
          webGestureHandling: WebGestureHandling.greedy,
          gestureRecognizers: {Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer())},
          onMapCreated: (c) {
            _map = c;
            Future.delayed(const Duration(milliseconds: 400), _overview);
          },
          // Si el profesional mueve el mapa con el dedo, se deja de seguir su ubicación
          onCameraMoveStarted: () {
            if (!_autoMove && _navigating && _follow) setState(() => _follow = false);
          },
          onCameraIdle: () => _autoMove = false,
          polylines: {
            if (_points.length > 1) ...[
              Polyline(polylineId: const PolylineId('borde'), points: remaining, width: 12, color: Colors.white, zIndex: 1),
              Polyline(
                polylineId: const PolylineId('ruta'),
                points: remaining,
                width: 8,
                color: NetJobColors.mapLine,
                zIndex: 2,
                startCap: Cap.roundCap,
                endCap: Cap.roundCap,
                jointType: JointType.round,
              ),
            ],
          },
          markers: {
            Marker(markerId: const MarkerId('destino'), position: dest, infoWindow: InfoWindow(title: _r!['client']['name'])),
            if (me != null)
              Marker(markerId: const MarkerId('yo'), position: me, icon: snap.data!.$2!, anchor: const Offset(0.5, 0.5), zIndexInt: 3),
          },
        );
      },
    );
  }
}

// ---------- Utilidades geográficas ----------

double _meters(LatLng a, LatLng b) => distanceKm(a.latitude, a.longitude, b.latitude, b.longitude) * 1000;

double _bearing(LatLng a, LatLng b) {
  final la1 = a.latitude * math.pi / 180, la2 = b.latitude * math.pi / 180;
  final dl = (b.longitude - a.longitude) * math.pi / 180;
  final y = math.sin(dl) * math.cos(la2);
  final x = math.cos(la1) * math.sin(la2) - math.sin(la1) * math.cos(la2) * math.cos(dl);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

String _fmtDistance(double m) {
  if (m < 1000) return '${(m / 10).round() * 10} m';
  return '${(m / 1000).toStringAsFixed(1)} km';
}

IconData _maneuverIcon(String? type, String? modifier) {
  if (type == 'arrive') return Icons.flag_rounded;
  if (type == 'roundabout' || type == 'rotary' || type == 'roundabout turn') return Icons.roundabout_right_rounded;
  if (type == 'merge') return Icons.merge_rounded;
  if (type == 'fork') return modifier?.contains('left') == true ? Icons.fork_left_rounded : Icons.fork_right_rounded;
  return switch (modifier) {
    'left' => Icons.turn_left_rounded,
    'right' => Icons.turn_right_rounded,
    'slight left' => Icons.turn_slight_left_rounded,
    'slight right' => Icons.turn_slight_right_rounded,
    'sharp left' => Icons.turn_sharp_left_rounded,
    'sharp right' => Icons.turn_sharp_right_rounded,
    'uturn' => Icons.u_turn_left_rounded,
    _ => Icons.straight_rounded,
  };
}
