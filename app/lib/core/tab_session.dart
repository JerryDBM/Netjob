import 'tab_session_stub.dart' if (dart.library.js_interop) 'tab_session_web.dart' as impl;

/// Sesión de la pestaña actual (solo en web). Permite tener, en el mismo navegador,
/// una pestaña como cliente y otra como profesional sin que una pise a la otra.
/// En celular o escritorio no hace nada.
String? readTabToken() => impl.readTabToken();
void writeTabToken(String? token) => impl.writeTabToken(token);
