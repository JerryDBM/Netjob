import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

Future<bool>? _loading;

/// Inyecta el script de Google Maps JavaScript API con la llave de compilación.
Future<bool> loadMapsScript(String key) => _loading ??= _load(key);

Future<bool> _load(String key) {
  final done = Completer<bool>();
  globalContext.setProperty(
    '__netjobMapsReady'.toJS,
    (() {
      if (!done.isCompleted) done.complete(true);
    }).toJS,
  );
  final script = web.HTMLScriptElement()
    ..src = 'https://maps.googleapis.com/maps/api/js?key=${Uri.encodeComponent(key)}&loading=async&callback=__netjobMapsReady'
    ..async = true;
  script.onerror = ((web.Event _) {
    if (!done.isCompleted) done.complete(false);
  }).toJS;
  web.document.head!.append(script);
  return done.future.timeout(const Duration(seconds: 15), onTimeout: () => false);
}
