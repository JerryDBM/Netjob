import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import '../core/realtime.dart';
import '../core/tab_session.dart';

/// Sesión del usuario. El token se guarda localmente para no pedir login cada vez.
class AuthState extends ChangeNotifier {
  AuthState() {
    Api.instance.onUnauthorized = logout;
  }

  static const _tokenKey = 'netjob_token';

  Map<String, dynamic>? user;
  bool ready = false;
  int unreadNotifications = 0;

  /// Sube cada vez que cambia una solicitud o un pago: las pantallas que lo observan se recargan.
  int dataVersion = 0;
  void dataChanged() {
    dataVersion++;
    notifyListeners();
  }

  bool get loggedIn => user != null;
  String get role => user?['role'] ?? 'CLIENT';
  bool get isPro => role == 'PROFESSIONAL';
  bool get isAdmin => role == 'ADMIN';
  String? get userId => user?['id'];

  /// Lo que le falta al perfil profesional (foto, título, portafolio…). Vacío = completo.
  List<String> get proMissing => [for (final m in (user?['professional']?['missing'] as List? ?? const [])) m.toString()];
  bool get needsOnboarding => isPro && proMissing.isNotEmpty;

  /// Primero la sesión de esta pestaña (web); si no hay, la guardada en el dispositivo.
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final token = readTabToken() ?? prefs.getString(_tokenKey);
    if (token != null) {
      Api.instance.token = token;
      try {
        user = Map<String, dynamic>.from(await Api.instance.get('/me'));
        writeTabToken(token);
        _connect(token);
      } catch (_) {
        Api.instance.token = null;
        writeTabToken(null);
        if (prefs.getString(_tokenKey) == token) await prefs.remove(_tokenKey);
      }
    }
    ready = true;
    notifyListeners();
  }

  /// Con [remember] la sesión queda guardada en el dispositivo; sin él, dura hasta cerrar la app.
  Future<void> _setSession(Map res, {bool remember = true}) async {
    final token = res['token'] as String;
    Api.instance.token = token;
    user = Map<String, dynamic>.from(res['user']);
    final prefs = await SharedPreferences.getInstance();
    // La pestaña conserva su propia cuenta aunque en otra se inicie sesión con otra
    writeTabToken(token);
    if (remember) {
      await prefs.setString(_tokenKey, token);
    } else {
      await prefs.remove(_tokenKey);
    }
    _connect(token);
    notifyListeners();
  }

  void _connect(String token) {
    Realtime.instance.connect(token);
    Realtime.instance.onNotification = (_) {
      unreadNotifications++;
      notifyListeners();
    };
    refreshUnread();
  }

  Future<void> login(String email, String password, {bool remember = true}) async {
    await _setSession(await Api.instance.post('/auth/login', {'email': email, 'password': password}), remember: remember);
  }

  Future<void> register(Map<String, dynamic> data) async {
    await _setSession(await Api.instance.post('/auth/register', data));
  }

  Future<void> reloadUser() async {
    user = Map<String, dynamic>.from(await Api.instance.get('/me'));
    notifyListeners();
  }

  Future<void> refreshUnread() async {
    try {
      final r = await Api.instance.get('/notifications');
      unreadNotifications = r['unread'] ?? 0;
      notifyListeners();
    } catch (_) {}
  }

  void markNotificationsRead() {
    unreadNotifications = 0;
    notifyListeners();
  }

  Future<void> logout() async {
    Api.instance.token = null;
    Realtime.instance.disconnect();
    user = null;
    unreadNotifications = 0;
    writeTabToken(null);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    notifyListeners();
  }
}
