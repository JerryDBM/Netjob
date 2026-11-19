import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

final _thousands = NumberFormat('#,##0', 'es_CO');

/// Formato colombiano: $100.000 (símbolo antes, punto de miles, sin decimales).
String cop(num? v) => v == null ? '—' : '\$${_thousands.format(v)}';

String fmtDate(String? iso) {
  if (iso == null) return '—';
  final d = DateTime.tryParse(iso)?.toLocal();
  return d == null ? '—' : DateFormat("d MMM y", 'es').format(d);
}

String fmtDateTime(String? iso) {
  if (iso == null) return '—';
  final d = DateTime.tryParse(iso)?.toLocal();
  return d == null ? '—' : DateFormat("EEE d MMM y · h:mm a", 'es').format(d);
}

String fmtTime(String? iso) {
  final d = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
  return d == null ? '' : DateFormat('h:mm a', 'es').format(d);
}

const priceUnitLabel = {'FIXED': '', 'HOUR': '/ hora', 'VISIT': '/ visita'};

const statusLabel = {
  'PENDING': 'Pendiente',
  'ACCEPTED': 'Aceptada',
  'REJECTED': 'Rechazada',
  'IN_PROGRESS': 'En proceso',
  'COMPLETED': 'Finalizada',
  'CANCELLED': 'Cancelada',
};

const statusColor = {
  'PENDING': Color(0xFFC77A12),
  'ACCEPTED': Color(0xFF3F7CAC),
  'REJECTED': Color(0xFFC8452F),
  'IN_PROGRESS': Color(0xFFE4602B),
  'COMPLETED': Color(0xFF2E8B57),
  'CANCELLED': Color(0xFF878E87),
};

/// Etapa del flujo de contratación (la calcula el backend en el detalle).
String requestStage(Map r) {
  if (r['stage'] != null) return r['stage'];
  final status = r['status'] as String;
  if (status != 'ACCEPTED') return status;
  final payments = (r['payments'] as List? ?? const []);
  bool paid(String kind) => payments.any((p) => p['kind'] == kind && p['status'] == 'APPROVED');
  if ((r['diagnosticFee'] ?? 1) != 0 && !paid('DIAGNOSTIC')) return 'PAY_DIAGNOSTIC';
  if (r['agreedPrice'] == null) return 'DIAGNOSIS';
  if (!paid('SERVICE')) return 'PAY_SERVICE';
  return 'READY_TO_START';
}

/// Texto corto de la etapa, según quién la mira.
String stageLabel(String stage, {required bool isPro}) => switch (stage) {
      'PENDING' => isPro ? 'Nueva solicitud: acepta o rechaza' : 'Esperando respuesta del profesional',
      'PAY_DIAGNOSTIC' => isPro ? 'Esperando pago de la visita' : 'Paga la visita de diagnóstico',
      'DIAGNOSIS' => isPro ? 'Visita y envía la cotización' : 'Visita de diagnóstico confirmada',
      'PAY_SERVICE' => isPro ? 'Cotización enviada, esperando pago' : 'Revisa y paga la cotización',
      'READY_TO_START' => isPro ? 'Pagado: inicia el servicio' : 'Pagado: el profesional iniciará',
      'IN_PROGRESS' => 'Trabajo en proceso',
      'COMPLETED' => 'Finalizado',
      'REJECTED' => 'Rechazada',
      'CANCELLED' => 'Cancelada',
      _ => stage,
    };

const paymentKindLabel = {
  'DIAGNOSTIC': 'Visita de diagnóstico',
  'SERVICE': 'Servicio',
  'SUBSCRIPTION': 'Suscripción',
  'PROMOTION': 'Perfil destacado',
};

/// "3 %" o "1 %" a partir de la tarifa (0.03, 0.01).
String pct(num? rate) {
  final v = ((rate ?? 0.03) * 1000).round() / 10;
  return '${v == v.roundToDouble() ? v.round() : v.toString().replaceAll('.', ',')} %';
}

const claimTypeLabel = {
  'QUALITY': 'Trabajo mal hecho o incompleto',
  'NO_SHOW': 'No llegó o incumplió la cita',
  'EXTRA_CHARGE': 'Cobros no pactados',
  'BEHAVIOR': 'Conducta inapropiada',
  'DAMAGE': 'Daños en el domicilio',
  'WARRANTY': 'Garantía: el arreglo falló',
  'PAYMENT': 'Problema con un pago o cancelación',
  'OTHER': 'Otro motivo',
};

const claimStatusLabel = {'OPEN': 'Abierta', 'IN_REVIEW': 'En revisión', 'RESOLVED': 'Resuelta', 'REJECTED': 'Cerrada'};

const claimStatusColor = {
  'OPEN': Color(0xFFC77A12),
  'IN_REVIEW': Color(0xFF3F7CAC),
  'RESOLVED': Color(0xFF2E8B57),
  'REJECTED': Color(0xFF878E87),
};

const claimActionLabel = {
  'NONE': 'Sin acción sobre el pago',
  'REFUND_CLIENT': 'Devolución al cliente',
  'RELEASE_PRO': 'Pago liberado al profesional',
  'WARRANTY_VISIT': 'Visita de garantía sin costo',
  'INSURANCE': 'Remitido a la aseguradora',
};

const paymentStatusLabel = {
  'PENDING': 'Pendiente',
  'APPROVED': 'Aprobado',
  'DECLINED': 'Rechazado',
  'VOIDED': 'Anulado',
  'ERROR': 'Error',
};

const weekdays = ['Domingo', 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado'];

/// Íconos Material por nombre (los define el admin en cada categoría).
const categoryIcons = <String, IconData>{
  'plumbing': Icons.plumbing,
  'electrical_services': Icons.electrical_services,
  'carpenter': Icons.carpenter,
  'build': Icons.build,
  'handyman': Icons.handyman,
  'devices': Icons.devices,
  'format_paint': Icons.format_paint,
  'key': Icons.key,
  'more_horiz': Icons.more_horiz,
};

IconData categoryIcon(String? name) => categoryIcons[name] ?? Icons.home_repair_service;

/// Tiempo relativo corto, como en una bandeja de entrada: "Ahora", "5 min", "2 h", "3 d".
String timeAgo(String? iso) {
  final d = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
  if (d == null) return '';
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'Ahora';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min';
  if (diff.inHours < 24) return '${diff.inHours} h';
  if (diff.inDays < 7) return '${diff.inDays} d';
  return DateFormat('d MMM', 'es').format(d);
}

/// Agrupa por día para separadores tipo "HOY", "AYER", "ANTERIORES".
String dayGroup(String? iso) {
  final d = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
  if (d == null) return 'ANTERIORES';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final days = today.difference(day).inDays;
  if (days == 0) return 'HOY';
  if (days == 1) return 'AYER';
  if (days < 7) return 'ESTA SEMANA';
  return 'ANTERIORES';
}

/// Estado automático según el horario: "Disponible hasta las 17:00",
/// "Fuera de horario · vuelve mañana a las 08:00" o "Pausado".
(bool, String) availabilityText(Map? a, {bool enabled = true, bool own = false}) {
  if (!enabled) return (false, own ? 'Pausaste tu disponibilidad' : 'No está recibiendo solicitudes');
  if (a == null) return (false, 'Sin horario configurado');
  if (a['availableNow'] == true) return (true, 'Disponible ahora · hasta las ${a['until']}');
  final next = a['next'] as Map?;
  if (next == null) return (false, 'Sin horario configurado');
  return (false, 'Fuera de horario · ${own ? 'vuelves' : 'vuelve'} ${next['day']} a las ${next['time']}');
}
