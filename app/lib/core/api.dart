import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';

/// URL del backend. Se puede cambiar al compilar:
///   flutter run --dart-define=API_URL=https://api.netjob.co
/// En el emulador de Android, localhost del PC es 10.0.2.2.
String get apiBaseUrl {
  const fromEnv = String.fromEnvironment('API_URL');
  if (fromEnv.isNotEmpty) return fromEnv;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:4000';
  }
  return 'http://localhost:4000';
}

/// Las imágenes se guardan con ruta relativa (/uploads/...): se completan con la URL
/// de la API para que funcionen desde el PC, el celular o un túnel. Las URLs antiguas
/// con localhost también se corrigen.
String resolveUrl(String url) {
  if (url.startsWith('/')) return '$apiBaseUrl$url';
  return url.replaceFirst(RegExp(r'^https?://localhost:4000'), apiBaseUrl);
}

Map<String, dynamic>? _config;

/// Parámetros públicos del backend (póliza de diagnóstico, radio de búsqueda, etc.).
Future<Map<String, dynamic>> appConfig() async =>
    _config ??= Map<String, dynamic>.from(await Api.instance.get('/config'));

class ApiException implements Exception {
  ApiException(this.status, this.message, {this.code});
  final int status;
  final String message;

  /// Código del backend para casos que la app trata distinto (PLAN_LIMIT, PLAN_REQUIRED).
  final String? code;

  /// El límite o la función depende del plan: se ofrece mejorar la suscripción.
  bool get isPlanLimit => code == 'PLAN_LIMIT' || code == 'PLAN_REQUIRED';
  @override
  String toString() => message;
}

/// Cliente HTTP mínimo para la API REST de NetJob.
class Api {
  Api._();
  static final Api instance = Api._();

  String? token;

  /// Se invoca cuando el backend responde 401 (sesión vencida).
  VoidCallback? onUnauthorized;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  /// Encabezados para descargar imágenes protegidas (documentos de verificación).
  Map<String, String> get authHeaders => {if (token != null) 'Authorization': 'Bearer $token'};

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final q = <String, String>{};
    query?.forEach((k, v) {
      if (v != null && v.toString().isNotEmpty) q[k] = v.toString();
    });
    return Uri.parse('$apiBaseUrl$path').replace(queryParameters: q.isEmpty ? null : q);
  }

  Future<dynamic> get(String path, [Map<String, dynamic>? query]) =>
      _send(() => http.get(_uri(path, query), headers: _headers));

  Future<dynamic> post(String path, [Object? body]) =>
      _send(() => http.post(_uri(path), headers: _headers, body: jsonEncode(body ?? {})));

  Future<dynamic> patch(String path, [Object? body]) =>
      _send(() => http.patch(_uri(path), headers: _headers, body: jsonEncode(body ?? {})));

  Future<dynamic> put(String path, [Object? body]) =>
      _send(() => http.put(_uri(path), headers: _headers, body: jsonEncode(body ?? {})));

  Future<dynamic> delete(String path) => _send(() => http.delete(_uri(path), headers: _headers));

  /// Sube imágenes (multipart). `field` es "file" para una o "files" para varias.
  Future<dynamic> upload(String path, List<XFile> files,
      {String field = 'file', Map<String, String> fields = const {}}) async {
    final req = http.MultipartRequest('POST', _uri(path));
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    req.fields.addAll(fields);
    for (final f in files) {
      final bytes = await f.readAsBytes();
      final name = f.name.isNotEmpty ? f.name : 'foto.jpg';
      final ext = name.split('.').last.toLowerCase();
      final mime = {'png': 'png', 'webp': 'webp', 'gif': 'gif'}[ext] ?? 'jpeg';
      req.files.add(http.MultipartFile.fromBytes(field, bytes,
          filename: name, contentType: MediaType('image', mime)));
    }
    return _send(() async => http.Response.fromStream(await req.send()));
  }

  Future<dynamic> _send(Future<http.Response> Function() call) async {
    http.Response res;
    try {
      // El servidor gratuito se duerme sin uso: la primera petición puede tardar ~50 s en despertarlo
      res = await call().timeout(const Duration(seconds: 70));
    } catch (e) {
      throw ApiException(0, 'No pudimos conectar con NetJob. Revisa tu conexión.');
    }
    final text = utf8.decode(res.bodyBytes, allowMalformed: true);
    final body = text.isEmpty ? null : _tryDecode(text);
    if (res.statusCode >= 200 && res.statusCode < 300) return body;
    if (res.statusCode == 401 && token != null) onUnauthorized?.call();
    final msg = body is Map && body['error'] != null ? body['error'].toString() : 'Error ${res.statusCode}';
    throw ApiException(res.statusCode, msg, code: body is Map ? body['code']?.toString() : null);
  }

  dynamic _tryDecode(String s) {
    try {
      return jsonDecode(s);
    } catch (_) {
      return s;
    }
  }
}
