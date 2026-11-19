import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../state/auth_state.dart';
import '../../widgets/common.dart';
import '../claims/claims_screens.dart';
import '../trust/trust_screens.dart';
import 'admin_tools.dart';

/// Panel administrativo: indicadores y las colas que el equipo de NetJob debe atender
/// (verificaciones, reclamaciones, cuentas en revisión, reseñas reportadas), pagos, categorías,
/// planes y promociones, y la configuración general.
class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});
  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  Map? _pending;

  Future<Map> _stats() async {
    final s = await Api.instance.get('/admin/stats') as Map;
    if (mounted) setState(() => _pending = s['pending'] as Map?);
    return s;
  }

  Widget _tab(String label, [int? count]) => Tab(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label),
          if ((count ?? 0) > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(color: NetJobColors.danger, borderRadius: BorderRadius.circular(10)),
              child: Text('$count', style: const TextStyle(color: NetJobColors.onPrimary, fontSize: 11.5, fontWeight: FontWeight.w800)),
            ),
          ],
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final p = _pending;
    return DefaultTabController(
      length: 9,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Panel administrativo'),
          actions: [IconButton(tooltip: 'Cerrar sesión', icon: const Icon(Icons.logout), onPressed: () => context.read<AuthState>().logout())],
          bottom: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
            _tab('Resumen'),
            _tab('Verificaciones', (p?['verifications'] as num?)?.toInt()),
            _tab('Reclamaciones', (p?['claims'] as num?)?.toInt()),
            _tab('Usuarios', (p?['underReview'] as num?)?.toInt()),
            _tab('Reseñas', (p?['reportedReviews'] as num?)?.toInt()),
            _tab('Pagos'),
            _tab('Categorías'),
            _tab('Planes y promociones'),
            _tab('Configuración'),
          ]),
        ),
        body: TabBarView(children: [
          _Summary(load: _stats),
          _Verifications(onChanged: _stats),
          _Claims(onChanged: _stats),
          _Users(onChanged: _stats),
          _Reviews(onChanged: _stats),
          const AdminPaymentsTab(),
          const AdminCategoriesTab(),
          const _PlansAndPromos(),
          const AdminSettingsTab(),
        ]),
      ),
    );
  }
}

// ---------------- Resumen ----------------

class _Summary extends StatelessWidget {
  const _Summary({required this.load});
  final Future<Map> Function() load;

  @override
  Widget build(BuildContext context) {
    return AsyncView<Map>(
      load: load,
      builder: (context, s, reload) {
        final rev = s['revenue'] as Map;
        final users = s['users'] as Map;
        final req = s['requests'] as Map;
        final pending = s['pending'] as Map;
        Widget kpi(String label, String value, {Color? color}) => Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(label, style: const TextStyle(color: NetJobColors.muted, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(value, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: color)),
                ]),
              ),
            );
        final cols = MediaQuery.of(context).size.width > 700 ? 4 : 2;
        Widget grid(List<Widget> children) => GridView.count(
              crossAxisCount: cols,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.9,
              children: children,
            );
        Color? alert(num? n) => (n ?? 0) > 0 ? NetJobColors.warning : null;
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            const SectionTitle('Por atender'),
            grid([
              kpi('Verificaciones pendientes', '${pending['verifications']}', color: alert(pending['verifications'])),
              kpi('Reclamaciones abiertas', '${pending['claims']}', color: alert(pending['claims'])),
              kpi('Cuentas en revisión', '${pending['underReview']}', color: alert(pending['underReview'])),
              kpi('Reseñas reportadas', '${pending['reportedReviews']}', color: alert(pending['reportedReviews'])),
            ]),
            const SectionTitle('Ingresos de NetJob'),
            grid([
              kpi('Comisiones por servicios', cop(rev['commissions'])),
              kpi('Suscripciones', cop(rev['subscriptions'])),
              kpi('Perfiles destacados', cop(rev['promotions'])),
              kpi('Volumen de servicios', cop(rev['servicesVolume'])),
            ]),
            const SectionTitle('Actividad'),
            grid([
              kpi('Clientes', '${users['CLIENT'] ?? 0}'),
              kpi('Profesionales', '${users['PROFESSIONAL'] ?? 0}'),
              kpi('Suscripciones activas', '${s['activeSubscriptions']}'),
              kpi('Cuentas suspendidas', '${pending['suspended']}'),
              kpi('Solicitudes pendientes', '${req['PENDING'] ?? 0}'),
              kpi('Servicios en proceso', '${(req['ACCEPTED'] ?? 0) + (req['IN_PROGRESS'] ?? 0)}'),
              kpi('Servicios finalizados', '${req['COMPLETED'] ?? 0}'),
              kpi('Cancelados o rechazados', '${(req['CANCELLED'] ?? 0) + (req['REJECTED'] ?? 0)}'),
            ]),
            const SizedBox(height: 24),
          ]),
        );
      },
    );
  }
}

// ---------------- Verificación de identidad ----------------

class _Verifications extends StatefulWidget {
  const _Verifications({required this.onChanged});
  final Future<Map> Function() onChanged;
  @override
  State<_Verifications> createState() => _VerificationsState();
}

class _VerificationsState extends State<_Verifications> {
  String _status = 'PENDING';

  Future<void> _decide(Map v, bool approve, Future<void> Function() reload) async {
    String? note;
    if (!approve) {
      note = await promptText(context, 'Rechazar documentos', hint: 'Qué debe corregir (lo verá el profesional)', ok: 'Rechazar', minLength: 5);
      if (note == null) return;
    } else if (!await confirm(context, 'Aprobar verificación', '¿Confirmas que la cédula, la selfie y el certificado de antecedentes de ${v['user']['name']} son válidos y coinciden?', ok: 'Aprobar')) {
      return;
    }
    try {
      await Api.instance.patch('/admin/verifications/${v['id']}', {'approve': approve, 'note': ?note});
      if (mounted) toast(context, approve ? 'Profesional verificado' : 'Documentos rechazados', error: false);
      await reload();
      widget.onChanged();
    } catch (e) {
      if (mounted) toast(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    const docs = [('idFrontFile', 'Cédula · frente'), ('idBackFile', 'Cédula · reverso'), ('selfieFile', 'Selfie'), ('backgroundCheckFile', 'Antecedentes')];
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(children: [
          for (final s in const [('PENDING', 'Pendientes'), ('APPROVED', 'Aprobadas'), ('REJECTED', 'Rechazadas')])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(label: Text(s.$2), selected: _status == s.$1, onSelected: (_) => setState(() => _status = s.$1)),
            ),
        ]),
      ),
      Expanded(
        child: AsyncView<List>(
          key: ValueKey(_status),
          load: () async => await Api.instance.get('/admin/verifications', {'status': _status}) as List,
          builder: (context, items, reload) {
            if (items.isEmpty) return const EmptyState(icon: Icons.verified_user_outlined, title: 'No hay verificaciones aquí');
            return RefreshIndicator(
              onRefresh: reload,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final v = items[i] as Map;
                  final u = v['user'] as Map;
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          UserAvatar(url: u['avatarUrl'], name: u['name'], radius: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(u['name'], style: const TextStyle(fontWeight: FontWeight.w800)),
                              Text('${u['email']} · ${u['phone'] ?? 'sin celular'}', style: const TextStyle(color: NetJobColors.muted, fontSize: 12.5)),
                              Text('${v['headline'] ?? 'Sin título'} · ${v['city'] ?? ''}', style: const TextStyle(color: NetJobColors.subtle, fontSize: 12.5)),
                            ]),
                          ),
                          if (v['priority'] == true)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: NetJobColors.star.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(8)),
                              child: Text('Prioritaria · ${v['plan']}', style: const TextStyle(color: NetJobColors.star, fontSize: 11.5, fontWeight: FontWeight.w800)),
                            ),
                        ]),
                        const SizedBox(height: 4),
                        Text(
                          'Enviado el ${fmtDate(v['verificationSubmittedAt'])} · capacitación ${v['trainingPassedAt'] != null ? 'aprobada' : 'pendiente'}',
                          style: const TextStyle(color: NetJobColors.muted, fontSize: 12),
                        ),
                        const SizedBox(height: 10),
                        Row(children: [
                          for (final d in docs)
                            if (v[d.$1] != null)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: Column(children: [
                                    GestureDetector(
                                      onTap: () => showPrivateImage(context, v[d.$1], '${u['name']} · ${d.$2}'),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: AspectRatio(aspectRatio: 1.3, child: PrivateImage(v[d.$1])),
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(d.$2, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10.5, color: NetJobColors.subtle)),
                                  ]),
                                ),
                              ),
                        ]),
                        if (v['verificationNote'] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text('Motivo del rechazo: ${v['verificationNote']}', style: const TextStyle(color: NetJobColors.danger, fontSize: 13)),
                          ),
                        if (_status == 'PENDING') ...[
                          const SizedBox(height: 10),
                          Row(children: [
                            Expanded(child: OutlinedButton(onPressed: () => _decide(v, false, reload), child: const Text('Rechazar'))),
                            const SizedBox(width: 10),
                            Expanded(child: FilledButton(onPressed: () => _decide(v, true, reload), child: const Text('Aprobar'))),
                          ]),
                        ],
                      ]),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    ]);
  }
}

// ---------------- Reclamaciones ----------------

class _Claims extends StatefulWidget {
  const _Claims({required this.onChanged});
  final Future<Map> Function() onChanged;
  @override
  State<_Claims> createState() => _ClaimsState();
}

class _ClaimsState extends State<_Claims> {
  bool _open = true;

  Future<void> _resolve(Map c, Future<void> Function() reload) async {
    final r = await showDialog<Map>(context: context, builder: (_) => _ResolveDialog(claim: c));
    if (r == null) return;
    try {
      await Api.instance.patch('/admin/claims/${c['id']}', r);
      if (mounted) toast(context, 'Reclamación actualizada', error: false);
      await reload();
      widget.onChanged();
    } catch (e) {
      if (mounted) toast(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(children: [
          ChoiceChip(label: const Text('Abiertas'), selected: _open, onSelected: (_) => setState(() => _open = true)),
          const SizedBox(width: 8),
          ChoiceChip(label: const Text('Cerradas'), selected: !_open, onSelected: (_) => setState(() => _open = false)),
        ]),
      ),
      Expanded(
        child: AsyncView<List>(
          key: ValueKey(_open),
          load: () async => await Api.instance.get('/admin/claims', {'status': _open ? 'open' : 'closed'}) as List,
          builder: (context, items, reload) {
            if (items.isEmpty) return const EmptyState(icon: Icons.fact_check_outlined, title: 'No hay reclamaciones aquí');
            return RefreshIndicator(
              onRefresh: reload,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final c = items[i] as Map;
                  final req = c['request'] as Map;
                  final held = (req['payments'] as List).cast<Map>().where((p) => p['kind'] == 'SERVICE' && p['payoutStatus'] == 'HELD').firstOrNull;
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        ClaimBody(claim: c, showParties: true),
                        const SizedBox(height: 8),
                        Text(
                          'Solicitud ${statusLabel[req['status']] ?? req['status']}${held != null ? ' · ${cop(held['serviceAmount'])} retenidos' : ' · sin dinero retenido'}',
                          style: TextStyle(color: held != null ? NetJobColors.warning : NetJobColors.muted, fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                        if (_open) ...[
                          const SizedBox(height: 10),
                          Row(children: [
                            if (c['status'] == 'OPEN')
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () async {
                                    try {
                                      await Api.instance.patch('/admin/claims/${c['id']}', {'status': 'IN_REVIEW'});
                                      await reload();
                                    } catch (e) {
                                      if (context.mounted) toast(context, e);
                                    }
                                  },
                                  child: const Text('Tomar en revisión'),
                                ),
                              ),
                            if (c['status'] == 'OPEN') const SizedBox(width: 10),
                            Expanded(child: FilledButton(onPressed: () => _resolve(c, reload), child: const Text('Resolver'))),
                          ]),
                        ],
                      ]),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    ]);
  }
}

class _ResolveDialog extends StatefulWidget {
  const _ResolveDialog({required this.claim});
  final Map claim;
  @override
  State<_ResolveDialog> createState() => _ResolveDialogState();
}

class _ResolveDialogState extends State<_ResolveDialog> {
  String _action = 'NONE';
  bool _reject = false;
  final _text = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final req = widget.claim['request'] as Map;
    final held = (req['payments'] as List).any((p) => p['kind'] == 'SERVICE' && p['payoutStatus'] == 'HELD');
    final actions = [
      'NONE',
      if (held) 'REFUND_CLIENT',
      if (held && req['status'] == 'IN_PROGRESS') 'RELEASE_PRO',
      'WARRANTY_VISIT',
      'INSURANCE',
    ];
    return AlertDialog(
      title: const Text('Resolver reclamación'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Cerrar sin darle la razón'),
            subtitle: const Text('La reclamación no procede; no cambia nada en la solicitud'),
            value: _reject,
            onChanged: (v) => setState(() => _reject = v),
          ),
          if (!_reject) ...[
            const SizedBox(height: 6),
            const Text('Acción', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final a in actions) ChoiceChip(label: Text(claimActionLabel[a]!), selected: _action == a, onSelected: (_) => setState(() => _action = a)),
            ]),
            if (!held)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('No hay dinero retenido: no se puede devolver ni liberar desde aquí.', style: TextStyle(color: NetJobColors.muted, fontSize: 12.5)),
              ),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: _text,
            maxLines: 4,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Explicación para ambas partes', hintText: 'Qué se revisó y por qué se decide así', alignLabelWithHint: true),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Volver')),
        FilledButton(
          onPressed: _text.text.trim().length < 10
              ? null
              : () => Navigator.pop(context, {'status': _reject ? 'REJECTED' : 'RESOLVED', 'action': _reject ? 'NONE' : _action, 'resolution': _text.text.trim()}),
          child: const Text('Guardar decisión'),
        ),
      ],
    );
  }
}

// ---------------- Usuarios: revisión y suspensión ----------------

class _Users extends StatefulWidget {
  const _Users({required this.onChanged});
  final Future<Map> Function() onChanged;
  @override
  State<_Users> createState() => _UsersState();
}

class _UsersState extends State<_Users> {
  String _filter = 'review';
  final _q = TextEditingController();
  int _version = 0;

  Future<void> _patch(Map u, Map body, Future<void> Function() reload, String ok) async {
    try {
      await Api.instance.patch('/admin/users/${u['id']}', body);
      if (mounted) toast(context, ok, error: false);
      await reload();
      widget.onChanged();
    } catch (e) {
      if (mounted) toast(context, e);
    }
  }

  Future<void> _suspend(Map u, Future<void> Function() reload) async {
    int? days = 7;
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text('Suspender a ${u['name']}'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Duración'),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final d in const [(7, '7 días'), (15, '15 días'), (30, '30 días'), (null, 'Indefinida')])
                ChoiceChip(label: Text(d.$2), selected: days == d.$1, onSelected: (_) => set(() => days = d.$1)),
            ]),
            const SizedBox(height: 12),
            TextField(controller: reason, maxLines: 3, onChanged: (_) => set(() {}), decoration: const InputDecoration(labelText: 'Motivo (lo verá el usuario)')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Volver')),
            FilledButton(onPressed: reason.text.trim().length < 5 ? null : () => Navigator.pop(c, true), child: const Text('Suspender')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _patch(u, {'status': 'SUSPENDED', 'days': days, 'reason': reason.text.trim()}, reload, 'Cuenta suspendida');
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(children: [
          TextField(
            controller: _q,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(hintText: 'Buscar por nombre o correo', prefixIcon: Icon(Icons.search), isDense: true),
            onSubmitted: (_) => setState(() => _version++),
          ),
          const SizedBox(height: 8),
          Row(children: [
            for (final f in const [('review', 'En revisión'), ('suspended', 'Suspendidas'), ('all', 'Todas')])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(label: Text(f.$2), selected: _filter == f.$1, onSelected: (_) => setState(() => _filter = f.$1)),
              ),
          ]),
        ]),
      ),
      Expanded(
        child: AsyncView<List>(
          key: ValueKey('$_filter-$_version'),
          load: () async => await Api.instance.get('/admin/users', {'filter': _filter == 'all' ? null : _filter, 'q': _q.text.trim()}) as List,
          builder: (context, items, reload) {
            if (items.isEmpty) {
              return EmptyState(
                icon: Icons.groups_outlined,
                title: _filter == 'review' ? 'No hay cuentas en revisión' : 'No hay cuentas aquí',
                message: _filter == 'review' ? 'Una cuenta entra en revisión cuando su calificación promedio baja de 3,5 con al menos tres reseñas.' : null,
              );
            }
            return RefreshIndicator(
              onRefresh: reload,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final u = items[i] as Map;
                  final pro = u['professional'] as Map?;
                  final suspended = u['status'] == 'SUSPENDED';
                  final rating = pro != null
                      ? ((pro['ratingCount'] as num) == 0 ? 'sin reseñas' : '${pro['ratingAvg']} (${pro['ratingCount']})')
                      : ((u['clientRatingCount'] as num) == 0 ? 'sin reseñas' : '${u['clientRatingAvg']} (${u['clientRatingCount']})');
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          UserAvatar(url: u['avatarUrl'], name: u['name'], radius: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(u['name'], style: const TextStyle(fontWeight: FontWeight.w800)),
                              Text('${{'CLIENT': 'Cliente', 'PROFESSIONAL': 'Profesional', 'ADMIN': 'Administrador'}[u['role']]} · ${u['email']}',
                                  style: const TextStyle(color: NetJobColors.muted, fontSize: 12.5)),
                              Text('Calificación: $rating${pro?['verified'] == true ? ' · verificado' : ''}', style: const TextStyle(color: NetJobColors.subtle, fontSize: 12.5)),
                            ]),
                          ),
                        ]),
                        if (u['underReview'] == true)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text('En revisión: ${u['reviewNote'] ?? 'calificaciones bajas'}', style: const TextStyle(color: NetJobColors.warning, fontSize: 13)),
                          ),
                        if (suspended)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Suspendida ${u['suspendedUntil'] != null ? 'hasta el ${fmtDate(u['suspendedUntil'])}' : 'indefinidamente'}${u['suspensionReason'] != null ? ' · ${u['suspensionReason']}' : ''}',
                              style: const TextStyle(color: NetJobColors.danger, fontSize: 13),
                            ),
                          ),
                        if (u['role'] != 'ADMIN') ...[
                          const SizedBox(height: 8),
                          Wrap(spacing: 8, runSpacing: 4, children: [
                            if (u['underReview'] == true)
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                                onPressed: () => _patch(u, {'underReview': false}, reload, 'Cuenta fuera de revisión'),
                                child: const Text('Sacar de revisión'),
                              )
                            else
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                                onPressed: () async {
                                  final reason = await promptText(context, 'Poner en revisión', hint: 'Motivo interno', ok: 'Guardar', minLength: 5);
                                  if (reason != null) await _patch(u, {'underReview': true, 'reason': reason}, reload, 'Cuenta en revisión');
                                },
                                child: const Text('Poner en revisión'),
                              ),
                            suspended
                                ? FilledButton(
                                    style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                                    onPressed: () => _patch(u, {'status': 'ACTIVE'}, reload, 'Cuenta reactivada'),
                                    child: const Text('Reactivar'),
                                  )
                                : OutlinedButton(
                                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), foregroundColor: NetJobColors.danger),
                                    onPressed: () => _suspend(u, reload),
                                    child: const Text('Suspender'),
                                  ),
                          ]),
                        ],
                      ]),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    ]);
  }
}

// ---------------- Reseñas reportadas ----------------

class _Reviews extends StatelessWidget {
  const _Reviews({required this.onChanged});
  final Future<Map> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    return AsyncView<List>(
      load: () async => await Api.instance.get('/admin/reviews/reported') as List,
      builder: (context, items, reload) {
        if (items.isEmpty) return const EmptyState(icon: Icons.reviews_outlined, title: 'No hay reseñas reportadas');
        Future<void> act(Map r, bool hide) async {
          try {
            await Api.instance.patch('/admin/reviews/${r['id']}', {'hidden': hide, 'reported': false});
            if (context.mounted) toast(context, hide ? 'Reseña ocultada' : 'Reseña conservada', error: false);
            await reload();
            onChanged();
          } catch (e) {
            if (context.mounted) toast(context, e);
          }
        }

        return RefreshIndicator(
          onRefresh: reload,
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final r = items[i] as Map;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      for (var k = 0; k < 5; k++) Icon(k < (r['rating'] as num) ? Icons.star_rounded : Icons.star_outline_rounded, color: NetJobColors.star, size: 20),
                      const Spacer(),
                      if (r['hidden'] == true) const Text('Oculta', style: TextStyle(color: NetJobColors.muted)),
                    ]),
                    const SizedBox(height: 4),
                    Text('${r['author']['name']} sobre ${r['professional']['user']['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (r['comment'] != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(r['comment'])),
                    const SizedBox(height: 6),
                    Text('Motivo del reporte: ${r['reportReason'] ?? '—'}', style: const TextStyle(color: NetJobColors.warning, fontSize: 13)),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: OutlinedButton(onPressed: () => act(r, false), child: const Text('Conservar'))),
                      const SizedBox(width: 10),
                      Expanded(child: FilledButton(onPressed: () => act(r, true), child: const Text('Ocultar reseña'))),
                    ]),
                  ]),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// ---------------- Planes y promociones ----------------

class _PlansAndPromos extends StatelessWidget {
  const _PlansAndPromos();

  Future<int?> _askPrice(BuildContext context, String title, num current) async {
    final v = await promptText(context, title, hint: 'Valor en pesos', ok: 'Guardar', initial: '$current', keyboard: TextInputType.number, minLength: 4);
    final n = int.tryParse((v ?? '').replaceAll(RegExp(r'\D'), ''));
    return n != null && n >= 1000 ? n : null;
  }

  @override
  Widget build(BuildContext context) {
    return AsyncView<List>(
      load: () => Future.wait([Api.instance.get('/admin/plans'), Api.instance.get('/admin/promotions')]),
      builder: (context, data, reload) {
        final plans = (data[0] as List).cast<Map>();
        final promos = data[1] as Map;
        final options = (promos['options'] as List).cast<Map>();
        final featured = (promos['featured'] as List).cast<Map>();

        Future<void> patchPlan(Map p, Map body) async {
          try {
            await Api.instance.patch('/admin/plans/${p['id']}', body);
            await reload();
          } catch (e) {
            if (context.mounted) toast(context, e);
          }
        }

        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            const SectionTitle('Planes de suscripción'),
            for (final p in plans)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(p['name'], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                      Text(cop(p['priceMonthly']), style: const TextStyle(fontWeight: FontWeight.w800, color: NetJobColors.primary)),
                      IconButton(
                        tooltip: 'Cambiar precio',
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        onPressed: () async {
                          final n = await _askPrice(context, 'Precio del plan ${p['name']}', p['priceMonthly']);
                          if (n != null) await patchPlan(p, {'priceMonthly': n});
                        },
                      ),
                    ]),
                    Text(
                      'Servicios: ${p['maxServices'] ?? 'sin límite'} · Fotos: ${p['maxPortfolio'] ?? 'sin límite'} · Prioridad: ${p['searchBoost']} · Destacado incluido: ${p['featuredDays']} días',
                      style: const TextStyle(color: NetJobColors.subtle, fontSize: 12.5),
                    ),
                    const SizedBox(height: 4),
                    Wrap(spacing: 6, runSpacing: 0, children: [
                      for (final f in const [
                        ('popular', 'Más popular'),
                        ('hasStats', 'Estadísticas'),
                        ('prioritySupport', 'Soporte prioritario'),
                        ('recommendationPriority', 'Primero en recomendados'),
                        ('verificationPriority', 'Verificación prioritaria'),
                        ('active', 'Disponible'),
                      ])
                        FilterChip(
                          label: Text(f.$2, style: const TextStyle(fontSize: 12)),
                          visualDensity: VisualDensity.compact,
                          selected: p[f.$1] == true,
                          onSelected: (v) => patchPlan(p, {f.$1: v}),
                        ),
                    ]),
                  ]),
                ),
              ),
            const SectionTitle('Precios de perfil destacado'),
            for (final o in options)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: const Icon(Icons.campaign_rounded, color: NetJobColors.star),
                  title: Text('${o['label']} · ${o['days']} días'),
                  subtitle: Text(cop(o['price'])),
                  trailing: IconButton(
                    tooltip: 'Cambiar precio',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () async {
                      final n = await _askPrice(context, 'Precio de ${o['label']}', o['price']);
                      if (n == null) return;
                      try {
                        await Api.instance.put('/admin/promotions', {
                          'options': [for (final x in options) x['id'] == o['id'] ? {...x, 'price': n} : x],
                        });
                        await reload();
                      } catch (e) {
                        if (context.mounted) toast(context, e);
                      }
                    },
                  ),
                ),
              ),
            SectionTitle('Perfiles destacados ahora (${featured.length})'),
            if (featured.isEmpty) const Text('Ningún profesional está destacado en este momento.', style: TextStyle(color: NetJobColors.muted)),
            for (final f in featured)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: UserAvatar(url: f['user']['avatarUrl'], name: f['user']['name'], radius: 20),
                title: Text(f['user']['name']),
                subtitle: Text('${f['city'] ?? ''} · hasta el ${fmtDate(f['featuredUntil'])}'),
                trailing: TextButton(
                  onPressed: () async {
                    try {
                      await Api.instance.patch('/admin/professionals/${f['id']}', {'featuredUntil': null});
                      await reload();
                    } catch (e) {
                      if (context.mounted) toast(context, e);
                    }
                  },
                  child: const Text('Quitar'),
                ),
              ),
            const SizedBox(height: 24),
          ]),
        );
      },
    );
  }
}
