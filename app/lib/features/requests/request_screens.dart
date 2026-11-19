import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../calendar/calendar_screens.dart';
import '../../core/format.dart';
import '../../core/realtime.dart';
import '../../core/theme.dart';
import '../../state/auth_state.dart';
import '../../widgets/photo_viewer.dart';
import '../../widgets/common.dart';
import '../claims/claims_screens.dart';

// ============================ Listado / historial ============================

class RequestsScreen extends StatelessWidget {
  const RequestsScreen({super.key});

  static const _tabs = [
    ['En curso', 'PENDING,ACCEPTED,IN_PROGRESS'],
    ['Finalizadas', 'COMPLETED'],
    ['Canceladas', 'REJECTED,CANCELLED'],
  ];

  @override
  Widget build(BuildContext context) {
    final isPro = context.watch<AuthState>().isPro;
    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(isPro ? 'Solicitudes recibidas' : 'Mis servicios'),
          bottom: TabBar(tabs: [for (final t in _tabs) Tab(text: t[0])]),
        ),
        body: TabBarView(children: [for (final t in _tabs) _RequestList(status: t[1], isPro: isPro)]),
      ),
    );
  }
}

class _RequestList extends StatelessWidget {
  const _RequestList({required this.status, required this.isPro});
  final String status;
  final bool isPro;

  @override
  Widget build(BuildContext context) {
    return AsyncView<List>(
      load: () async => await Api.instance.get('/requests', {'status': status}) as List,
      builder: (context, items, reload) {
        if (items.isEmpty) {
          return EmptyState(
            icon: Icons.assignment_outlined,
            title: 'No hay solicitudes aquí',
            message: isPro ? 'Cuando un cliente te contrate, verás la solicitud aquí.' : 'Busca un profesional y envía tu primera solicitud.',
            action: isPro ? null : FilledButton(onPressed: () => context.go('/home'), child: const Text('Buscar servicios')),
          );
        }
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final r = items[i];
              final other = isPro ? r['client'] : r['professional']['user'];
              final stage = requestStage(r);
              final needsMe = isPro
                  ? ['PENDING', 'DIAGNOSIS', 'READY_TO_START'].contains(stage)
                  : ['PAY_DIAGNOSTIC', 'PAY_SERVICE'].contains(stage);
              return Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () async {
                    await context.push('/requests/${r['id']}');
                    reload();
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      UserAvatar(url: other['avatarUrl'], name: other['name']),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(r['service']['title'], style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text(other['name'], style: TextStyle(color: NetJobColors.subtle)),
                          const SizedBox(height: 4),
                          Text(fmtDateTime(r['scheduledAt']), style: TextStyle(fontSize: 12, color: NetJobColors.muted)),
                          const SizedBox(height: 2),
                          Text(stageLabel(stage, isPro: isPro),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: needsMe ? FontWeight.w700 : FontWeight.w500,
                                color: needsMe ? const Color(0xFFC77A12) : NetJobColors.subtle,
                              )),
                        ]),
                      ),
                      StatusChip(r['status']),
                    ]),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// ============================ Detalle de solicitud ============================

/// Pasos del flujo, en orden, para la barra de progreso del detalle.
const _flowSteps = [
  ('PENDING', 'Solicitud'),
  ('PAY_DIAGNOSTIC', 'Visita'),
  ('DIAGNOSIS', 'Diagnóstico'),
  ('PAY_SERVICE', 'Pago'),
  ('IN_PROGRESS', 'Trabajo'),
  ('COMPLETED', 'Listo'),
];

class RequestDetailScreen extends StatefulWidget {
  const RequestDetailScreen({super.key, required this.id});
  final String id;
  @override
  State<RequestDetailScreen> createState() => _RequestDetailScreenState();
}

class _RequestDetailScreenState extends State<RequestDetailScreen> with WidgetsBindingObserver {
  Map? _r;
  Object? _error;
  bool _busy = false;
  void Function()? _unwatch;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _unwatch = Realtime.instance.watchRequest(widget.id, onUpdated: _load);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _unwatch?.call();
    super.dispose();
  }

  /// Al volver del checkout de Wompi, sincroniza el pago pendiente.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _syncPendingPayment();
  }

  Future<void> _load() async {
    try {
      final r = await Api.instance.get('/requests/${widget.id}');
      if (mounted) {
        setState(() {
          _r = r;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _syncPendingPayment() async {
    final pending = (_r?['payments'] as List?)?.where((p) => p['status'] == 'PENDING' && p['kind'] != 'SUBSCRIPTION');
    if (pending == null || pending.isEmpty) return;
    try {
      await Api.instance.post('/payments/${pending.first['id']}/sync');
    } catch (_) {}
    await _load();
  }

  Future<void> _act(Future<dynamic> Function() fn, {String? ok}) async {
    setState(() => _busy = true);
    try {
      final r = await fn();
      if (r is Map && r['status'] != null && r['service'] != null) setState(() => _r = r);
      if (ok != null && mounted) toast(context, ok, error: false);
      if (mounted) context.read<AuthState>().dataChanged();
      await _load();
    } catch (e) {
      if (mounted) toast(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---- Acciones ----

  Future<void> _accept() async {
    final free = (_r!['diagnosticFee'] ?? 0) == 0;
    final fee = cop(_r!['diagnosticFee']);
    if (!await confirm(context, 'Aceptar solicitud',
        free
            ? 'Tu visita de diagnóstico es gratis: ve en la fecha acordada, revisa y envía la cotización final desde aquí.'
            : 'El cliente pagará $fee por tu visita de diagnóstico. Después de revisar, le envías la cotización final desde aquí.',
        ok: 'Aceptar')) {
      return;
    }
    await _act(() => Api.instance.post('/requests/${widget.id}/accept'), ok: 'Solicitud aceptada');
  }

  Future<void> _reject() async {
    final note = await promptText(context, 'Rechazar solicitud', hint: 'Motivo (opcional)', ok: 'Rechazar');
    if (note == null) return;
    await _act(() => Api.instance.post('/requests/${widget.id}/reject', {if (note.isNotEmpty) 'note': note}));
  }

  Future<void> _quote() async {
    final r = await showDialog<Map>(context: context, builder: (_) => _QuoteDialog(price: _r!['agreedPrice'], note: _r!['quoteNote']));
    if (r == null) return;
    await _act(() => Api.instance.post('/requests/${widget.id}/quote', r), ok: 'Cotización enviada al cliente');
  }

  Future<void> _cancel({String title = 'Cancelar solicitud', String? warning}) async {
    if (warning != null && !await confirm(context, title, warning, ok: 'Continuar')) return;
    if (!mounted) return;
    final reason = await promptText(context, title, hint: 'Cuéntanos el motivo', ok: 'Confirmar', minLength: 3);
    if (reason == null) return;
    await _act(() => Api.instance.post('/requests/${widget.id}/cancel', {'reason': reason}), ok: 'Solicitud cancelada');
  }

  Future<void> _pay() async {
    setState(() => _busy = true);
    try {
      final co = await Api.instance.post('/payments/service/${widget.id}/checkout');
      if (!mounted) return;
      final what = co['payment']['kind'] == 'DIAGNOSTIC' ? 'la visita de diagnóstico' : 'el servicio';
      if (co['mode'] == 'wompi') {
        await launchUrl(Uri.parse(co['checkoutUrl']), mode: LaunchMode.externalApplication);
        if (mounted) toast(context, 'Completa el pago de $what en Wompi y vuelve a la app.', error: false);
      } else {
        // Modo pruebas: el backend no tiene llaves de Wompi; se simula la respuesta de la pasarela
        final approve = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Pago en modo pruebas'),
            content: Text('Pago de $what: ${cop(co['payment']['totalAmount'])}\n\nLa pasarela Wompi no está configurada en el servidor. Simula el resultado del pago:'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Simular rechazo')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Simular aprobado')),
            ],
          ),
        );
        if (approve == null) return;
        final p = await Api.instance.post('/payments/${co['payment']['id']}/simulate', {'status': approve ? 'APPROVED' : 'DECLINED'});
        if (mounted) toast(context, p['status'] == 'APPROVED' ? 'Pago aprobado' : 'Pago rechazado', error: p['status'] != 'APPROVED');
      }
      if (mounted) context.read<AuthState>().dataChanged();
      await _load();
    } catch (e) {
      if (mounted) toast(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reviewClient() async {
    final r = await showModalBottomSheet<Map>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ReviewSheet(
        title: '¿Cómo fue el cliente?',
        hint: 'Puntualidad, trato, claridad y pago (opcional). La verán otros profesionales.',
      ),
    );
    if (r == null) return;
    await _act(() => Api.instance.post('/requests/${widget.id}/client-review', r), ok: 'Gracias por calificar al cliente');
  }

  Future<void> _review() async {
    final r = await showModalBottomSheet<Map>(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => const _ReviewSheet());
    if (r == null) return;
    await _act(() => Api.instance.post('/requests/${widget.id}/review', r), ok: '¡Gracias por tu calificación!');
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final r = _r;
    final canPop = context.canPop();
    return Scaffold(
      appBar: AppBar(
        // Siempre hay salida: atrás si hay historial, si no, al inicio
        leading: canPop
            ? const BackButton()
            : IconButton(tooltip: 'Inicio', icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/home')),
        title: const Text('Detalle de la solicitud'),
        actions: [
          IconButton(tooltip: 'Ir al inicio', icon: const Icon(Icons.home_outlined), onPressed: () => context.go('/home')),
        ],
      ),
      body: r == null
          ? (_error != null
              ? EmptyState(icon: Icons.error_outline, title: 'No se pudo cargar', message: '$_error',
                  action: FilledButton(onPressed: _load, child: const Text('Reintentar')))
              : const Center(child: CircularProgressIndicator()))
          : RefreshIndicator(onRefresh: _load, child: _body(context, r, auth)),
      bottomNavigationBar: r == null ? null : _actions(r, auth),
    );
  }

  Widget _progress(String stage, String status) {
    if (status == 'REJECTED' || status == 'CANCELLED') return const SizedBox.shrink();
    final order = _flowSteps.map((s) => s.$1).toList();
    final current = switch (stage) {
      'READY_TO_START' => order.indexOf('IN_PROGRESS'),
      _ => order.indexOf(stage),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        for (var i = 0; i < _flowSteps.length; i++)
          Expanded(
            child: Column(children: [
              Container(
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: i < current || stage == 'COMPLETED'
                      ? NetJobColors.accent
                      : i == current
                          ? NetJobColors.primary
                          : const Color(0xFFDDE1D5),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 4),
              Text(_flowSteps[i].$2,
                  style: TextStyle(fontSize: 10, color: i == current ? NetJobColors.primary : NetJobColors.muted, fontWeight: i == current ? FontWeight.w700 : null)),
            ]),
          ),
      ]),
    );
  }

  /// Mensaje principal: qué está pasando y qué sigue, según el rol.
  Widget _nextStep(String stage, bool isPro, Map r) {
    final fee = cop(r['diagnosticFee']);
    final free = (r['diagnosticFee'] ?? 0) == 0;
    final (IconData icon, String title, String body) = switch (stage) {
      'PENDING' => isPro
          ? (Icons.inbox, 'Nueva solicitud', free ? 'Tu visita de diagnóstico es gratis: si aceptas, ve a revisar y envía la cotización.' : 'Si aceptas, el cliente pagará $fee por tu visita de diagnóstico.')
          : (Icons.hourglass_top, 'Esperando al profesional',
              free ? 'Te avisaremos cuando acepte. La visita de diagnóstico es gratis.' : 'Te avisaremos cuando acepte. Luego pagarás $fee por la visita de diagnóstico.'),
      'PAY_DIAGNOSTIC' => isPro
          ? (Icons.hourglass_top, 'Esperando el pago de la visita', 'Cuando el cliente pague $fee, ve a revisar y envíale la cotización.')
          : (Icons.home_repair_service, 'Paga la visita de diagnóstico', 'Pagas $fee para que el profesional vaya a revisar. Después te envía el precio final según materiales y complejidad.'),
      'DIAGNOSIS' => isPro
          ? (Icons.search, 'Haz el diagnóstico', 'Visita al cliente, revisa el problema y envíale la cotización con el valor final.')
          : (Icons.event_available, 'Visita confirmada', 'El profesional irá en la fecha acordada, revisará y te enviará la cotización aquí.'),
      'PAY_SERVICE' => isPro
          ? (Icons.hourglass_top, 'Cotización enviada', 'Cuando el cliente pague, podrás iniciar el trabajo. Puedes corregir el valor mientras no haya pagado.')
          : (Icons.request_quote, 'Revisa la cotización', 'Si estás de acuerdo, paga para que empiece el trabajo. Si no, puedes rechazarla (la visita no se reembolsa).'),
      'READY_TO_START' => isPro
          ? (Icons.play_circle_outline, 'Pago recibido', 'Ya puedes iniciar el trabajo.')
          : (Icons.verified, 'Pago confirmado', 'El profesional iniciará el trabajo.'),
      'IN_PROGRESS' => (
          Icons.construction,
          'Trabajo en proceso',
          _confirmText(r, isPro),
        ),
      'COMPLETED' => (Icons.task_alt, 'Servicio finalizado', isPro ? 'Gracias por tu trabajo.' : 'Cuéntales a otros cómo te fue con tu calificación.'),
      'REJECTED' => (Icons.block, 'Solicitud rechazada', 'Busca otro profesional cerca de ti.'),
      _ => (Icons.cancel_outlined, 'Solicitud cancelada', r['cancelReason'] ?? ''),
    };
    final highlight = (!isPro && (stage == 'PAY_DIAGNOSTIC' || stage == 'PAY_SERVICE')) ||
        (isPro && (stage == 'PENDING' || stage == 'DIAGNOSIS' || stage == 'READY_TO_START'));
    return Card(
      color: highlight ? const Color(0xFFFBEBDA) : NetJobColors.primary.withValues(alpha: 0.05),
      child: ListTile(
        leading: Icon(icon, color: highlight ? const Color(0xFFC77A12) : NetJobColors.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(body),
      ),
    );
  }

  Widget _body(BuildContext context, Map r, AuthState auth) {
    final isPro = r['professional']['userId'] == auth.userId;
    final other = isPro ? r['client'] : r['professional']['user'];
    final status = r['status'] as String;
    final stage = requestStage(r);
    final charge = r['charge'] as Map?;
    final history = r['history'] as List;
    final photos = r['photos'] as List;
    final review = r['review'] as Map?;
    final chatOpen = ['PENDING', 'ACCEPTED', 'IN_PROGRESS'].contains(status);
    final diagnosticPaid = r['diagnosticPaid'] == true;
    final paid = r['paid'] == true;
    final trip = (r['trip'] as Map?) ?? const {};
    final enRoute = trip['enRoute'] == true;
    final commission = (r['commission'] as Map?) ?? const {};
    final claims = (r['claims'] as List? ?? const []).cast<Map>();
    final myOpenClaim = claims.any((c) => c['openedById'] == auth.userId && (c['status'] == 'OPEN' || c['status'] == 'IN_REVIEW'));
    final receipts = (r['payments'] as List).cast<Map>().where((p) => p['status'] == 'APPROVED').toList();

    return ListView(padding: const EdgeInsets.all(16), children: [
      _progress(stage, status),
      _nextStep(stage, isPro, r),
      // El cliente sigue al profesional en el mapa solo mientras va en camino
      if (!isPro && enRoute) ...[
        const SizedBox(height: 8),
        Material(
          color: const Color(0xFF1B4332),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: const BorderSide(color: Color(0x66D3E27F))),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () => context.push('/requests/${r['id']}/track'),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(color: NetJobColors.mint, shape: BoxShape.circle),
                  child: const Icon(Icons.navigation_rounded, color: NetJobColors.onPrimary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${(other['name'] as String).split(' ').first} va en camino', style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                    const Text('Toca para ver por dónde va en el mapa', style: TextStyle(color: Color(0xFFCFE6D8))),
                  ]),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.white),
              ]),
            ),
          ),
        ),
      ] else if (!isPro && trip['arrivedAt'] != null && ['DIAGNOSIS', 'PAY_SERVICE', 'READY_TO_START', 'IN_PROGRESS'].contains(stage)) ...[
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.flag_rounded, color: NetJobColors.primary),
            title: const Text('El profesional llegó a tu dirección'),
            subtitle: Text(fmtDateTime(trip['arrivedAt'])),
          ),
        ),
      ],
      // El profesional abre la ruta al domicilio cuando va a la visita o al trabajo
      if (isPro && ['PAY_DIAGNOSTIC', 'DIAGNOSIS', 'PAY_SERVICE', 'READY_TO_START', 'IN_PROGRESS'].contains(stage)) ...[
        const SizedBox(height: 8),
        Material(
          color: NetJobColors.slate,
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () => context.push('/requests/${r['id']}/route'),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(color: NetJobColors.orange, shape: BoxShape.circle),
                  child: const Icon(Icons.navigation_rounded, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(enRoute ? 'Vas en camino' : 'Cómo llegar', style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                    Text(enRoute ? 'El cliente está viendo tu ubicación' : 'Ruta y aviso de "Voy en camino" · ${r['address']}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: enRoute ? NetJobColors.lime : NetJobColors.onDarkSoft)),
                  ]),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.white),
              ]),
            ),
          ),
        ),
      ],
      const SizedBox(height: 8),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(r['service']['title'], style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
              StatusChip(status),
            ]),
            Text(r['service']['category']['name'], style: TextStyle(color: NetJobColors.muted, fontSize: 12)),
            const Divider(height: 24),
            Row(children: [
              UserAvatar(url: other['avatarUrl'], name: other['name'], radius: 20),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(isPro ? 'Cliente' : 'Profesional', style: TextStyle(fontSize: 12, color: NetJobColors.muted)),
                Text(other['name'], style: const TextStyle(fontWeight: FontWeight.w600)),
                if (isPro)
                  InkWell(
                    onTap: () => context.push('/clients/${other['id']}/reviews'),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        RatingStars(rating: other['clientRatingAvg'] ?? 0, count: other['clientRatingCount'] ?? 0, size: 14),
                        const SizedBox(width: 6),
                        const Text('Ver reseñas', style: TextStyle(fontSize: 12, color: NetJobColors.primary, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ),
              ])),
              if (!isPro)
                TextButton(onPressed: () => context.push('/pro/${r['professional']['id']}'), child: const Text('Ver perfil')),
            ]),
            const SizedBox(height: 12),
            _row(Icons.event, fmtDateTime(r['scheduledAt'])),
            _row(Icons.place_outlined, r['address']),
            const SizedBox(height: 8),
            Text(r['description']),
            if (r['additionalInfo'] != null) ...[
              const SizedBox(height: 6),
              Text('Info adicional: ${r['additionalInfo']}', style: TextStyle(color: NetJobColors.subtle)),
            ],
            if (photos.isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 80,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (var k = 0; k < photos.length; k++)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: PhotoThumb(urls: [for (final x in photos) x as String], index: k, heroPrefix: 'solicitud', width: 80, height: 80),
                    ),
                ]),
              ),
            ],
            if (r['cancelReason'] != null) ...[
              const SizedBox(height: 8),
              Text('Motivo de cancelación: ${r['cancelReason']}', style: const TextStyle(color: Color(0xFFC8452F))),
            ],
          ]),
        ),
      ),
      // Agenda: proponer otra hora, responder propuestas y nota privada
      if (['PENDING', 'ACCEPTED', 'IN_PROGRESS', 'COMPLETED'].contains(status)) ...[
        const SizedBox(height: 8),
        AppointmentTools(
          requestId: r['id'],
          status: status,
          scheduledAt: r['scheduledAt'],
          reschedule: r['reschedule'] as Map?,
          myNote: r['myNote'],
          counterpartName: other['name'],
          onChanged: (_) => _load(),
        ),
      ],
      const SizedBox(height: 12),
      Card(
        child: ListTile(
          leading: const Icon(Icons.chat_bubble_outline, color: NetJobColors.primary),
          title: const Text('Chat con la otra parte'),
          subtitle: Text(chatOpen ? 'Coordina fechas, detalles y condiciones' : 'El chat está cerrado (solo lectura)'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/requests/${r['id']}/chat', extra: other['name']),
        ),
      ),
      const SectionTitle('Pagos'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Precio de referencia: desde ${cop(r['service']['price'])} ${priceUnitLabel[r['service']['priceUnit']]}',
                style: TextStyle(fontSize: 12, color: NetJobColors.muted)),
            const SizedBox(height: 8),
            _payLine('1. Visita de diagnóstico', (r['diagnosticFee'] ?? 0) == 0 ? 'Gratis' : cop(r['diagnosticFee']), diagnosticPaid,
                hint: (r['diagnosticFee'] ?? 0) == 0 ? 'Este profesional no cobra la visita' : isPro ? 'Lo recibes por tu visita' : 'No incluye tarifa NetJob'),
            const Divider(height: 20),
            const Text('2. Valor final cotizado', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            if (charge == null)
              Text(diagnosticPaid ? 'Pendiente: el profesional lo envía después de la visita.' : 'Se define después de la visita de diagnóstico.',
                  style: TextStyle(color: NetJobColors.subtle))
            else ...[
              if (r['quoteNote'] != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFFE6E9DE), borderRadius: BorderRadius.circular(10)),
                  child: Text('“${r['quoteNote']}”', style: const TextStyle(fontStyle: FontStyle.italic)),
                ),
              AmountRow('Valor del servicio', cop(charge['serviceAmount'])),
              if (!isPro) ...[
                AmountRow(
                  'Tarifa NetJob (${pct(commission['rate'])})',
                  cop(charge['commissionAmount']),
                  hint: commission['reduced'] == true
                      ? 'Tarifa reducida por tu beneficio (la normal es ${pct(commission['standardRate'])})'
                      : 'Asumida por el cliente',
                ),
                const Divider(),
                AmountRow('Total a pagar', cop(charge['totalAmount']), bold: true),
              ] else
                Text('Tú recibes el valor del servicio. La tarifa NetJob la paga el cliente.',
                    style: TextStyle(fontSize: 12, color: NetJobColors.muted)),
              const SizedBox(height: 6),
              Row(children: [
                Icon(paid ? Icons.check_circle : Icons.pending_outlined, size: 18, color: paid ? const Color(0xFF2E8B57) : NetJobColors.muted),
                const SizedBox(width: 6),
                Flexible(child: Text(_payoutText(r, paid, isPro))),
                const Spacer(),
                if (isPro && stage == 'PAY_SERVICE')
                  TextButton(onPressed: _busy ? null : _quote, child: const Text('Corregir cotización')),
              ]),
            ],
          ]),
        ),
      ),
      if (receipts.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(spacing: 8, runSpacing: 0, children: [
            for (final p in receipts)
              TextButton.icon(
                onPressed: () => context.push('/payments/${p['id']}/receipt'),
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                label: Text('Comprobante · ${p['kind'] == 'DIAGNOSTIC' ? 'visita' : 'servicio'}'),
              ),
          ]),
        ),
      if (status == 'COMPLETED' && r['warrantyUntil'] != null) ...[
        const SizedBox(height: 6),
        Card(
          child: ListTile(
            leading: const Icon(Icons.verified_user_outlined, color: NetJobColors.mint),
            title: const Text('Garantía de la mano de obra'),
            subtitle: Text(DateTime.tryParse('${r['warrantyUntil']}')?.isAfter(DateTime.now()) == true
                ? 'Vigente hasta el ${fmtDate(r['warrantyUntil'])}. ${isPro ? 'Si el arreglo falla, debes volver a revisarlo.' : 'Si el arreglo falla, abre una reclamación de garantía.'}'
                : 'Terminó el ${fmtDate(r['warrantyUntil'])}.'),
          ),
        ),
      ],
      if (claims.isNotEmpty || r['canClaim'] == true) ...[
        SectionTitle(claims.isEmpty ? '¿Algo salió mal?' : 'Reclamaciones'),
        for (final c in claims)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: ClaimBody(claim: {...c, 'request': {'service': r['service']}}),
              ),
            ),
          ),
        if (r['canClaim'] == true && !myOpenClaim)
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () async {
                    if (await openClaimSheet(context, r, isPro: isPro)) await _load();
                  },
            icon: const Icon(Icons.report_problem_outlined),
            label: Text(status == 'COMPLETED' && !isPro ? 'Reclamar o usar la garantía' : 'Tengo un problema con este servicio'),
          ),
      ],
      if (review != null) ...[
        const SectionTitle('Calificación del servicio'),
        _ratingCard(review, isPro ? 'El cliente te calificó' : 'Tu calificación'),
      ],
      if (r['clientReview'] != null) ...[
        const SectionTitle('Calificación del cliente'),
        _ratingCard(r['clientReview'], isPro ? 'Tu calificación al cliente' : 'El profesional te calificó'),
      ],
      const SectionTitle('Historial'),
      for (final h in history)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.circle, size: 12, color: statusColor[h['toStatus']]),
          // Mismo estado antes y después = actualización dentro de la etapa (ej. cotización)
          title: Text(h['fromStatus'] != h['toStatus']
              ? statusLabel[h['toStatus']] ?? h['toStatus']
              : switch ((h['note'] ?? '').toString()) {
                  final n when n.startsWith('Cotización') => 'Cotización',
                  final n when n.startsWith('Reclamación') => 'Reclamación',
                  final n when n.startsWith('El profesional va') || n.startsWith('El profesional llegó') || n.startsWith('El profesional pausó') => 'Trayecto',
                  _ => 'Confirmación',
                }),
          subtitle: Text([fmtDateTime(h['createdAt']), h['changedBy']?['name'], h['note']].whereType<String>().join(' · ')),
        ),
      const SizedBox(height: 24),
    ]);
  }

  /// Estado de la doble confirmación y del dinero retenido.
  String _confirmText(Map r, bool isPro) {
    final client = r['clientConfirmedAt'] != null;
    final pro = r['proConfirmedAt'] != null;
    if (r['openClaim'] == true) {
      return 'Hay una reclamación abierta. El pago sigue retenido por NetJob hasta que el equipo la resuelva.';
    }
    if (!client && !pro) {
      return isPro
          ? 'Tu pago está retenido por NetJob. Cuando termines, confirma aquí; el cliente también debe confirmarlo para liberarlo.'
          : 'Tu pago está retenido por NetJob. Cuando el trabajo esté listo, confirma aquí; el profesional recibe el dinero cuando ambos confirmen.';
    }
    if (isPro) {
      return pro ? 'Confirmaste que terminaste. Falta que el cliente lo confirme para liberar tu dinero.' : 'El cliente ya confirmó que el trabajo terminó. Confírmalo tú para recibir tu dinero.';
    }
    return client ? 'Confirmaste que el trabajo terminó. Falta que el profesional lo confirme.' : 'El profesional marcó el trabajo como terminado. Si todo quedó bien, confírmalo.';
  }

  Widget _ratingCard(Map review, String label) => Card(
        child: ListTile(
          title: Text(label, style: const TextStyle(fontSize: 13, color: NetJobColors.muted, fontWeight: FontWeight.w600)),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              for (var i = 0; i < 5; i++)
                Icon(i < review['rating'] ? Icons.star_rounded : Icons.star_outline_rounded, color: NetJobColors.star),
            ]),
            if (review['comment'] != null)
              Text(review['comment'], style: const TextStyle(color: NetJobColors.ink, fontSize: 14.5)),
          ]),
        ),
      );

  String _payoutText(Map r, bool paid, bool isPro) {
    if (!paid) return 'Pago pendiente';
    final service = (r['payments'] as List).cast<Map>().where((p) => p['kind'] == 'SERVICE' && p['status'] == 'APPROVED').firstOrNull;
    final released = service?['payoutStatus'] == 'RELEASED';
    if (service?['payoutStatus'] == 'REFUNDED') return isPro ? 'Devuelto al cliente por una reclamación' : 'Devuelto a tu favor por la reclamación';
    if (isPro) return released ? 'Pagado · liberado a tu favor' : 'Pagado · retenido hasta que ambos confirmen';
    return released ? 'Pagado · liberado al profesional' : 'Pagado · NetJob lo retiene hasta que ambos confirmen';
  }

  Widget _payLine(String label, String amount, bool paid, {String? hint}) => Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (hint != null) Text(hint, style: TextStyle(fontSize: 11, color: NetJobColors.muted)),
          ]),
        ),
        Text(amount, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        Icon(paid ? Icons.check_circle : Icons.pending_outlined, size: 18, color: paid ? const Color(0xFF2E8B57) : NetJobColors.muted),
      ]);

  Widget _row(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: NetJobColors.muted),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ]),
      );

  /// Botones según rol y etapa: aquí vive el flujo de la contratación.
  Widget? _actions(Map r, AuthState auth) {
    final isPro = r['professional']['userId'] == auth.userId;
    final isClient = r['client']['id'] == auth.userId;
    final stage = requestStage(r);
    final buttons = <Widget>[];
    Widget gap() => const SizedBox(width: 12);
    const noRefund = 'La visita de diagnóstico ya pagada no se reembolsa porque cubre el desplazamiento y la revisión del profesional.';

    if (isPro) {
      switch (stage) {
        case 'PENDING':
          buttons.addAll([
            Expanded(child: OutlinedButton(onPressed: _busy ? null : _reject, child: const Text('Rechazar'))),
            gap(),
            Expanded(child: FilledButton(onPressed: _busy ? null : _accept, child: const Text('Aceptar'))),
          ]);
        case 'PAY_DIAGNOSTIC':
          buttons.addAll([
            OutlinedButton(onPressed: _busy ? null : () => _cancel(), child: const Text('Cancelar')),
            gap(),
            const Expanded(child: FilledButton(onPressed: null, child: Text('Esperando pago de la visita'))),
          ]);
        case 'DIAGNOSIS':
          buttons.addAll([
            OutlinedButton(onPressed: _busy ? null : () => _cancel(), child: const Text('Cancelar')),
            gap(),
            Expanded(
              child: FilledButton.icon(onPressed: _busy ? null : _quote, icon: const Icon(Icons.request_quote), label: const Text('Enviar cotización')),
            ),
          ]);
        case 'PAY_SERVICE':
          buttons.add(const Expanded(child: FilledButton(onPressed: null, child: Text('Esperando pago del cliente'))));
        case 'READY_TO_START':
          buttons.add(Expanded(
            child: FilledButton.icon(
              icon: const Icon(Icons.play_arrow),
              onPressed: _busy ? null : () => _act(() => Api.instance.post('/requests/${widget.id}/start'), ok: 'Servicio en proceso'),
              label: const Text('Iniciar servicio'),
            ),
          ));
      }
      if (stage == 'COMPLETED' && r['clientReview'] == null) {
        buttons.add(Expanded(
          child: FilledButton.icon(
            icon: const Icon(Icons.star_outline),
            onPressed: _busy ? null : _reviewClient,
            label: const Text('Calificar al cliente'),
          ),
        ));
      }
    } else if (isClient) {
      switch (stage) {
        case 'PENDING':
          buttons.add(Expanded(child: OutlinedButton(onPressed: _busy ? null : () => _cancel(), child: const Text('Cancelar solicitud'))));
        case 'PAY_DIAGNOSTIC':
          buttons.addAll([
            OutlinedButton(onPressed: _busy ? null : () => _cancel(), child: const Text('Cancelar')),
            gap(),
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.lock_outline),
                onPressed: _busy ? null : _pay,
                label: Text('Pagar visita ${cop(r['diagnosticFee'])}'),
              ),
            ),
          ]);
        case 'DIAGNOSIS':
          buttons.add(Expanded(
            child: OutlinedButton(
              onPressed: _busy ? null : () => _cancel(warning: noRefund),
              child: const Text('Cancelar solicitud'),
            ),
          ));
        case 'PAY_SERVICE':
          buttons.addAll([
            OutlinedButton(
              onPressed: _busy ? null : () => _cancel(title: 'Rechazar cotización', warning: 'Se cancelará la solicitud. $noRefund'),
              child: const Text('Rechazar'),
            ),
            gap(),
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.lock_outline),
                onPressed: _busy ? null : _pay,
                label: Text('Pagar ${cop((r['charge'] as Map?)?['totalAmount'])}'),
              ),
            ),
          ]);
        case 'COMPLETED' when r['review'] == null:
          buttons.add(Expanded(
            child: FilledButton.icon(icon: const Icon(Icons.star_outline), onPressed: _busy ? null : _review, label: const Text('Calificar servicio')),
          ));
      }
    }
    if (stage == 'IN_PROGRESS' && (isPro || isClient)) {
      // Doble confirmación: cada parte confirma por su lado
      final mine = isPro ? r['proConfirmedAt'] : r['clientConfirmedAt'];
      buttons.add(Expanded(
        child: mine != null
            ? FilledButton.icon(
                onPressed: null,
                icon: const Icon(Icons.hourglass_top_rounded),
                label: Text(isPro ? 'Esperando que el cliente confirme' : 'Esperando que el profesional confirme'),
              )
            : FilledButton.icon(
                icon: const Icon(Icons.task_alt),
                onPressed: _busy
                    ? null
                    : () async {
                        final msg = isPro
                            ? '¿El trabajo quedó terminado? El cliente también debe confirmarlo; cuando ambos lo hagan, recibes tu dinero.'
                            : '¿El trabajo quedó terminado y a tu gusto? Al confirmar (y cuando el profesional también lo haga), NetJob le libera el pago.';
                        if (await confirm(context, 'Confirmar fin del servicio', msg, ok: 'Sí, terminó')) {
                          await _act(() => Api.instance.post('/requests/${widget.id}/complete'), ok: 'Confirmación registrada');
                        }
                      },
                label: const Text('Confirmar que terminó'),
              ),
      ));
    }
    if (buttons.isEmpty) return null;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: const BoxDecoration(color: NetJobColors.bgSoft, border: Border(top: BorderSide(color: NetJobColors.border))),
        child: Row(children: buttons),
      ),
    );
  }
}

/// Cotización después del diagnóstico: valor final y qué incluye.
class _QuoteDialog extends StatefulWidget {
  const _QuoteDialog({this.price, this.note});
  final int? price;
  final String? note;
  @override
  State<_QuoteDialog> createState() => _QuoteDialogState();
}

class _QuoteDialogState extends State<_QuoteDialog> {
  final _form = GlobalKey<FormState>();
  late final _price = TextEditingController(text: widget.price?.toString());
  late final _note = TextEditingController(text: widget.note);

  @override
  Widget build(BuildContext context) {
    final value = int.tryParse(_price.text.replaceAll(RegExp(r'\D'), ''));
    return AlertDialog(
      title: const Text('Cotización del servicio'),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Según lo que encontraste en el diagnóstico, ¿cuánto cuesta el trabajo?', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextFormField(
              controller: _price,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Valor final (COP)', prefixText: r'$ '),
              validator: (v) => (int.tryParse((v ?? '').replaceAll(RegExp(r'\D'), '')) ?? 0) >= 1000 ? null : 'Mínimo \$1.000',
            ),
            if (value != null && value >= 1000)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('El cliente pagará ${cop(value + (value * 0.03).round())} con la tarifa NetJob del 3 % (menos si tiene un beneficio). Tú recibes ${cop(value)} completos.',
                    style: TextStyle(fontSize: 12, color: NetJobColors.subtle)),
              ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _note,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Qué incluye',
                hintText: 'Hallazgos, materiales, mano de obra, garantía…',
                alignLabelWithHint: true,
              ),
              validator: (v) => (v ?? '').trim().length >= 10 ? null : 'Explica qué incluye (mín. 10 caracteres)',
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.pop(context, {
              'agreedPrice': int.parse(_price.text.replaceAll(RegExp(r'\D'), '')),
              'quoteNote': _note.text.trim(),
            });
          },
          child: const Text('Enviar'),
        ),
      ],
    );
  }
}

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({
    this.title = '¿Cómo fue el servicio?',
    this.hint = 'Cuéntales a otros clientes tu experiencia (opcional)',
  });
  final String title;
  final String hint;
  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  int _rating = 0;
  final _comment = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(widget.title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 1; i <= 5; i++)
            IconButton(
              iconSize: 40,
              onPressed: () => setState(() => _rating = i),
              icon: Icon(i <= _rating ? Icons.star_rounded : Icons.star_outline_rounded, color: NetJobColors.star),
            ),
        ]),
        const SizedBox(height: 8),
        TextField(controller: _comment, maxLines: 3, decoration: InputDecoration(hintText: widget.hint)),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _rating == 0
              ? null
              : () => Navigator.pop(context, {'rating': _rating, if (_comment.text.trim().isNotEmpty) 'comment': _comment.text.trim()}),
          child: const Text('Publicar calificación'),
        ),
      ]),
    );
  }
}

// ============================ Chat ============================

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.requestId, this.title});
  final String requestId;
  final String? title;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  bool _open = true;
  bool _loading = true;
  bool _sending = false;
  void Function()? _unwatch;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _unwatch = Realtime.instance.watchRequest(widget.requestId, onMessage: _add, onUpdated: _load);
    // Respaldo por si el socket no está disponible (redes que bloquean websockets)
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _load());
  }

  @override
  void dispose() {
    _unwatch?.call();
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Api.instance.get('/requests/${widget.requestId}/messages');
      if (!mounted) return;
      setState(() {
        _open = r['open'] == true;
        _messages
          ..clear()
          ..addAll((r['messages'] as List).map((m) => Map<String, dynamic>.from(m)));
        _loading = false;
      });
      _toBottom();
      Api.instance.post('/requests/${widget.requestId}/messages/read').ignore();
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _add(Map<String, dynamic> m) {
    if (_messages.any((x) => x['id'] == m['id'])) return; // llega por sala y por usuario
    setState(() => _messages.add(m));
    _toBottom();
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      });

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      final m = await Api.instance.post('/requests/${widget.requestId}/messages', {'content': text});
      _ctrl.clear();
      _add(Map<String, dynamic>.from(m));
    } catch (e) {
      if (mounted) toast(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AuthState>().userId;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? 'Chat')),
      body: Column(children: [
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _messages.isEmpty
                  ? const EmptyState(icon: Icons.forum_outlined, title: 'Aún no hay mensajes', message: 'Escribe para coordinar los detalles del servicio.')
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(12),
                      itemCount: _messages.length,
                      itemBuilder: (_, i) {
                        final m = _messages[i];
                        final mine = m['senderId'] == me;
                        return Align(
                          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                            margin: const EdgeInsets.symmetric(vertical: 3),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: mine ? NetJobColors.primary : NetJobColors.cardHigh,
                              borderRadius: BorderRadius.circular(14),
                              border: mine ? null : Border.all(color: const Color(0xFFDDE1D5)),
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text(m['content'], style: TextStyle(color: mine ? NetJobColors.onPrimary : NetJobColors.ink)),
                              const SizedBox(height: 2),
                              Text(fmtTime(m['createdAt']), style: TextStyle(fontSize: 10, color: mine ? const Color(0x99F8F6EE) : NetJobColors.muted)),
                            ]),
                          ),
                        );
                      },
                    ),
        ),
        SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            color: NetJobColors.bgSoft,
            child: _open
                ? Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: const InputDecoration(hintText: 'Escribe un mensaje…', isDense: true),
                      ),
                    ),
                    IconButton.filled(onPressed: _sending ? null : _send, icon: const Icon(Icons.send)),
                  ])
                : const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('El chat se cerró porque la solicitud terminó.', textAlign: TextAlign.center),
                  ),
          ),
        ),
      ]),
    );
  }
}
