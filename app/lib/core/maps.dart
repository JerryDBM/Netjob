import 'package:flutter/foundation.dart';

import 'maps_loader_stub.dart' if (dart.library.js_interop) 'maps_loader_web.dart' as loader;

/// Llave de Google Maps. Se pasa al compilar:
///   flutter run -d chrome --dart-define=MAPS_API_KEY=AIza...
/// En Android además va en android/local.properties (MAPS_API_KEY=AIza...).
const mapsApiKey = String.fromEnvironment('MAPS_API_KEY');

/// Google Maps funciona en web, Android e iOS (no en Windows) y requiere la llave.
bool get mapsAvailable =>
    mapsApiKey.isNotEmpty &&
    (kIsWeb || defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

/// En web el script de Google Maps se carga una sola vez, bajo demanda.
Future<bool> ensureMapsLoaded() async {
  if (!mapsAvailable) return false;
  if (!kIsWeb) return true;
  return loader.loadMapsScript(mapsApiKey);
}

/// Estilo del mapa: claro, con un leve tinte lavanda para que combine con la app sin
/// perder legibilidad (el estilo oscuro anterior se confundía con la interfaz).
const netjobMapStyle = r'''[
  {"elementType":"geometry","stylers":[{"color":"#f4f1fa"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#4a3d63"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#ffffff"}]},
  {"featureType":"administrative","elementType":"geometry.stroke","stylers":[{"color":"#c9bde0"}]},
  {"featureType":"landscape.man_made","elementType":"geometry","stylers":[{"color":"#efeaf8"}]},
  {"featureType":"poi","elementType":"geometry","stylers":[{"color":"#e8e1f5"}]},
  {"featureType":"poi","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#d3efdd"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#ffffff"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#ddd3ee"}]},
  {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#ffffff"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#ead6ff"}]},
  {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#c9a6f2"}]},
  {"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#3b2560"}]},
  {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#e8e1f5"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#bcdcff"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#2c5f99"}]}
]''';
