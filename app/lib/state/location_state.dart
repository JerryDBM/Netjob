import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/colombia.dart';

/// Ciudades para elegir la ubicación a mano (cuando el GPS no está disponible)
/// y para nombrar la ubicación actual sin depender de servicios externos.
const colombianCities = <(String, double, double)>[
  ('Bogotá', 4.6533, -74.0836),
  ('Medellín', 6.2442, -75.5812),
  ('Cali', 3.4516, -76.5320),
  ('Barranquilla', 10.9685, -74.7813),
  ('Cartagena', 10.3910, -75.4794),
  ('Bucaramanga', 7.1193, -73.1227),
  ('Pereira', 4.8133, -75.6961),
  ('Santa Marta', 11.2408, -74.1990),
  ('Manizales', 5.0703, -75.5138),
  ('Cúcuta', 7.8939, -72.5078),
  ('Ibagué', 4.4389, -75.2322),
  ('Villavicencio', 4.1420, -73.6266),
  ('Pasto', 1.2136, -77.2811),
  ('Montería', 8.7479, -75.8814),
  ('Neiva', 2.9273, -75.2819),
  ('Armenia', 4.5339, -75.6811),
  ('Valledupar', 10.4631, -73.2532),
  ('Sincelejo', 9.3047, -75.3978),
  ('El Carmen de Bolívar', 9.7174, -75.1202),
  ('Magangué', 9.2415, -74.7546),
  ('Turbaco', 10.3313, -75.4128),
];

double distanceKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) + math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}

/// Municipio más cercano (cabecera a menos de 25 km), entre los 1.122 de Colombia.
String? nearestCity(double lat, double lng) {
  (String, double)? best;
  for (final dept in colombiaMunicipios.values) {
    for (final m in dept) {
      final d = distanceKm(lat, lng, m.$2, m.$3);
      if (best == null || d < best.$2) best = (m.$1, d);
    }
  }
  return best != null && best.$2 < 25 ? best.$1 : null;
}

enum LocationStatus { idle, loading, ok, denied, disabled, error }

/// Ubicación actual del cliente. Se toma del GPS/navegador y se sigue actualizando
/// mientras la app está abierta: si mañana estás en otra ciudad, la búsqueda cambia sola.
class LocationState extends ChangeNotifier {
  static const _prefsKey = 'netjob_manual_location';

  double? lat;
  double? lng;
  String label = '';
  bool manual = false;
  LocationStatus status = LocationStatus.idle;
  String? message;
  StreamSubscription<Position>? _sub;

  bool get hasLocation => lat != null && lng != null;

  /// Clave que cambia cuando la ubicación se mueve ~1 km: sirve para recargar búsquedas.
  String get key => hasLocation ? '${lat!.toStringAsFixed(2)},${lng!.toStringAsFixed(2)}' : 'none';

  Future<void> start() async {
    if (status == LocationStatus.loading) return;
    status = LocationStatus.loading;
    // La última ubicación elegida se muestra de inmediato mientras responde el GPS
    if (!hasLocation) await _loadManual();
    notifyListeners();
    final ok = await _startGps();
    if (!ok) await _loadManual();
    notifyListeners();
  }

  Future<bool> _startGps() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        status = LocationStatus.disabled;
        message = 'La ubicación del dispositivo está apagada.';
        return false;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        status = LocationStatus.denied;
        message = kIsWeb
            ? 'El navegador no permitió usar tu ubicación. Si entraste por http desde el celular, el navegador la bloquea: elige tu ciudad o usa una conexión https.'
            : 'No diste permiso para usar tu ubicación.';
        return false;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 20)),
      );
      _setGps(pos);
      await _sub?.cancel();
      _sub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, distanceFilter: 500),
      ).listen((p) {
        _setGps(p);
        notifyListeners();
      }, onError: (_) {});
      return true;
    } catch (e) {
      status = LocationStatus.error;
      message = kIsWeb
          ? 'No pudimos obtener tu ubicación. En el celular, el navegador solo la comparte por https: elige tu ciudad mientras tanto.'
          : 'No pudimos obtener tu ubicación.';
      return false;
    }
  }

  void _setGps(Position p) {
    lat = p.latitude;
    lng = p.longitude;
    manual = false;
    label = nearestCity(p.latitude, p.longitude) ?? 'Tu ubicación actual';
    status = LocationStatus.ok;
    message = null;
  }

  Future<void> _loadManual() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_prefsKey);
    if (saved != null && saved.length == 3) {
      lat = double.tryParse(saved[1]);
      lng = double.tryParse(saved[2]);
      label = saved[0];
      manual = true;
    }
  }

  /// Ubicación elegida a mano (ciudad o punto en el mapa). Deja de seguir el GPS.
  Future<void> setManual(double newLat, double newLng, String newLabel) async {
    await _sub?.cancel();
    _sub = null;
    lat = newLat;
    lng = newLng;
    label = newLabel;
    manual = true;
    status = LocationStatus.ok;
    message = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, [newLabel, '$newLat', '$newLng']);
    notifyListeners();
  }

  /// Vuelve a usar el GPS del dispositivo.
  Future<void> useDeviceLocation() async {
    status = LocationStatus.idle;
    await start();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
