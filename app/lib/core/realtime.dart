import 'package:socket_io_client/socket_io_client.dart' as io;

import 'api.dart';

/// Conexión en tiempo real (Socket.IO) para chat, cambios de estado y notificaciones.
class Realtime {
  Realtime._();
  static final Realtime instance = Realtime._();

  io.Socket? _socket;
  void Function(dynamic)? onNotification;

  void connect(String token) {
    disconnect();
    _socket = io.io(
      apiBaseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .enableReconnection()
          .build(),
    );
    _socket!.on('notification', (data) => onNotification?.call(data));
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
  }

  /// Escucha los eventos de una solicitud (mensajes y cambios de estado).
  /// Devuelve una función para dejar de escuchar.
  void Function() watchRequest(
    String requestId, {
    void Function(Map<String, dynamic>)? onMessage,
    void Function()? onUpdated,
    void Function(double lat, double lng, DateTime at)? onLocation,
  }) {
    final s = _socket;
    if (s == null) return () {};
    void msgHandler(dynamic data) {
      if (data is Map && data['requestId'] == requestId) onMessage?.call(Map<String, dynamic>.from(data));
    }

    void updHandler(dynamic data) {
      if (data is Map && data['id'] == requestId) onUpdated?.call();
    }

    void locHandler(dynamic data) {
      if (data is Map && data['id'] == requestId && data['lat'] != null) {
        onLocation?.call(
          (data['lat'] as num).toDouble(),
          (data['lng'] as num).toDouble(),
          DateTime.tryParse('${data['at']}')?.toLocal() ?? DateTime.now(),
        );
      }
    }

    void join([_]) => s.emit('join', requestId);
    join();
    s.on('connect', join); // al reconectar, vuelve a la sala
    s.on('message:new', msgHandler);
    s.on('request:updated', updHandler);
    s.on('request:location', locHandler);
    return () {
      s.emit('leave', requestId);
      s.off('connect', join);
      s.off('message:new', msgHandler);
      s.off('request:updated', updHandler);
      s.off('request:location', locHandler);
    };
  }
}
