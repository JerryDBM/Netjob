import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/maps.dart';
import '../../core/theme.dart';
import '../../state/auth_state.dart';
import '../../state/location_state.dart';
import '../../widgets/photo_viewer.dart';
import '../../widgets/common.dart';
import '../../widgets/maps.dart';
import 'plan_screens.dart';

// ============================ Panel del profesional ============================

class ProDashboardScreen extends StatelessWidget {
  const ProDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final name = (context.watch<AuthState>().user?['name'] ?? '').toString().split(' ').first;
    return Scaffold(
      body: SafeArea(
        child: AsyncView<List>(
          load: () => Future.wait([
            Api.instance.get('/professionals/me/profile'),
            Api.instance.get('/professionals/me/stats'),
            Api.instance.get('/requests', {'status': 'PENDING,ACCEPTED,IN_PROGRESS'}),
            Api.instance.get('/subscriptions/me'),
          ]),
          builder: (context, data, reload) {
            final profile = data[0] as Map;
            final stats = data[1] as Map;
            final active = data[2] as List;
            final plan = data[3] as Map;
            final sub = profile['subscription'] as Map?;
            final usage = plan['usage'] as Map;
            final value = plan['value'] as Map?;
            final soon = plan['expiringSoon'] == true;
            final days = (plan['daysLeft'] as num?)?.toInt() ?? 0;
            final discount = ((plan['performance'] as Map)['discountPct'] as num).toInt();
            final verification = profile['verificationStatus'] as String? ?? 'NONE';
            final verificationRequired = profile['verificationRequired'] == true;
            final underReview = context.read<AuthState>().user?['underReview'] == true;
            final nearLimit = (usage['services'] as Map)['near'] == true || (usage['portfolio'] as Map)['near'] == true;
            Future<void> open(String route) async {
              await context.push(route);
              reload();
            }

            final req = stats['requests'] as Map;
            final missing = <String>[
              if (verificationRequired && verification != 'APPROVED' && verification != 'PENDING') 'Verifica tu identidad',
              if (sub == null) 'Activa un plan de suscripción',
              if ((profile['services'] as List).isEmpty) 'Publica tu primer servicio',
            ];
            return RefreshIndicator(
              onRefresh: reload,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Text('Hola, $name', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                if (underReview)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Card(
                      color: const Color(0xFFFBE3D6),
                      child: ListTile(
                        leading: const Icon(Icons.rate_review_outlined, color: NetJobColors.warning),
                        title: const Text('Tu cuenta está en revisión'),
                        subtitle: const Text('Tus calificaciones recientes son bajas. Repasa los instructivos y cuida tus próximos servicios para salir de la revisión.'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => open('/pro/guides'),
                      ),
                    ),
                  ),
                Card(
                  color: sub == null || soon ? const Color(0xFFFBEBDA) : null,
                  shape: soon
                      ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: NetJobColors.warning))
                      : null,
                  child: ListTile(
                    leading: Icon(Icons.workspace_premium, color: sub == null || soon ? const Color(0xFFC77A12) : NetJobColors.accent),
                    title: Row(children: [
                      Flexible(child: Text(sub == null ? 'Sin suscripción activa' : 'Plan ${sub['plan']['name']}')),
                      if (sub != null) ...[const SizedBox(width: 8), PlanBadge(sub['plan']['badge'], compact: true)],
                    ]),
                    subtitle: Text(sub == null
                        ? 'No apareces en las búsquedas ni puedes aceptar solicitudes.'
                        : soon
                            ? (days <= 1 ? 'Vence mañana: renueva para no desaparecer de las búsquedas' : 'Vence en $days días: renueva para no desaparecer de las búsquedas')
                            : 'Vence el ${fmtDate(sub['endsAt'])} · quedan $days días'),
                    trailing: TextButton(
                      onPressed: () => open('/pro/subscription'),
                      child: Text(sub == null ? 'Activar' : soon ? 'Renovar' : 'Gestionar'),
                    ),
                  ),
                ),
                // Lo que el plan le ha traído: hace visible el valor de la suscripción
                if (value != null) ...[
                  const SizedBox(height: 10),
                  Material(
                    color: NetJobColors.card,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: NetJobColors.border)),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => open('/pro/subscription'),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            const Icon(Icons.auto_graph_rounded, color: NetJobColors.mint, size: 20),
                            const SizedBox(width: 8),
                            const Expanded(child: Text('Lo que tu plan te ha traído', style: TextStyle(fontWeight: FontWeight.w800))),
                            if (discount > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(color: NetJobColors.mint.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(8)),
                                child: Text('−$discount % en tu renovación', style: const TextStyle(color: NetJobColors.mint, fontSize: 11.5, fontWeight: FontWeight.w800)),
                              ),
                          ]),
                          const SizedBox(height: 6),
                          Text(
                            '${value['requests']} ${value['requests'] == 1 ? 'solicitud' : 'solicitudes'} · ${value['views']} visitas a tu perfil · ${cop(value['income'])} en servicios',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                          Text('Desde el ${fmtDate(value['since'])}', style: const TextStyle(color: NetJobColors.muted, fontSize: 12.5)),
                        ]),
                      ),
                    ),
                  ),
                ],
                if (sub != null && nearLimit) ...[
                  const SizedBox(height: 10),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(children: [
                        UsageMeter(label: 'Servicios publicados', usage: usage['services'], onUpgrade: () => open('/pro/subscription')),
                        const SizedBox(height: 12),
                        UsageMeter(label: 'Fotos de portafolio', usage: usage['portfolio'], onUpgrade: () => open('/pro/subscription')),
                      ]),
                    ),
                  ),
                ],
                if (verification != 'APPROVED') ...[
                  const SizedBox(height: 10),
                  Card(
                    color: verificationRequired ? const Color(0xFFFBEBDA) : null,
                    shape: verificationRequired
                        ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: NetJobColors.warning))
                        : null,
                    child: ListTile(
                      leading: Icon(
                        verification == 'PENDING' ? Icons.hourglass_top_rounded : Icons.verified_user_outlined,
                        color: verification == 'REJECTED' ? NetJobColors.danger : NetJobColors.sky,
                      ),
                      title: Text(switch (verification) {
                        'PENDING' => 'Documentos en revisión',
                        'REJECTED' => 'Corrige tus documentos',
                        _ => 'Verifica tu identidad',
                      }),
                      subtitle: Text(switch (verification) {
                        'PENDING' => verificationRequired
                            ? 'Aún no apareces en las búsquedas. Te avisaremos cuando el equipo de NetJob responda.'
                            : 'Te avisaremos cuando el equipo de NetJob responda',
                        'REJECTED' => '${profile['verificationNote'] ?? 'Sube de nuevo tus documentos'}${verificationRequired ? '. Hasta entonces no apareces en las búsquedas.' : ''}',
                        _ => verificationRequired
                            ? 'Es obligatorio: no apareces en las búsquedas ni recibes solicitudes hasta que validemos tus documentos'
                            : 'Los clientes confían más en perfiles con la insignia de verificado',
                      }),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => open('/pro/verification'),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(children: [
                  _Stat('Pendientes', '${req['PENDING'] ?? 0}', Icons.inbox_outlined),
                  const SizedBox(width: 10),
                  _Stat('Finalizados', '${req['COMPLETED'] ?? 0}', Icons.task_alt),
                  const SizedBox(width: 10),
                  _Stat('Calificación', (stats['rating']['ratingCount'] ?? 0) == 0 ? '—' : '${stats['rating']['ratingAvg']}', Icons.star_outline,
                      onTap: () => context.push('/pro/${profile['id']}/reviews')),
                ]),
                const SizedBox(height: 10),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.person_outline, color: NetJobColors.primary),
                    title: const Text('Mi perfil profesional'),
                    subtitle: const Text('Foto, descripción, zona, horarios y portafolio'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await context.push('/pro/profile');
                      reload();
                    },
                  ),
                ),
                const SizedBox(height: 10),
                Card(
                  color: NetJobColors.night,
                  child: ListTile(
                    leading: const Icon(Icons.star_rounded, color: NetJobColors.lime),
                    title: const Text('Mis reseñas', style: TextStyle(color: Colors.white)),
                    subtitle: Text(
                      (stats['rating']['ratingCount'] ?? 0) == 0
                          ? 'Aún no tienes reseñas'
                          : '${stats['rating']['ratingAvg']} de 5 · ${stats['rating']['ratingCount']} opiniones',
                      style: const TextStyle(color: NetJobColors.onDarkSoft),
                    ),
                    trailing: const Icon(Icons.chevron_right, color: Colors.white),
                    onTap: () => context.push('/pro/${profile['id']}/reviews'),
                  ),
                ),
                const SizedBox(height: 10),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.home_repair_service_outlined, color: NetJobColors.primary),
                    title: const Text('Mis servicios'),
                    subtitle: Text((usage['services'] as Map)['max'] == null
                        ? '${(profile['services'] as List).length} publicados · sin límite en tu plan'
                        : '${(usage['services'] as Map)['used']} de ${(usage['services'] as Map)['max']} publicados'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await context.push('/pro/services');
                      reload();
                    },
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.payments_outlined, color: NetJobColors.primary),
                    title: Text(cop(stats['income']['total']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                    subtitle: Text((stats['income']['held'] ?? 0) > 0
                        ? 'Disponible · ${cop(stats['income']['held'])} retenido hasta que los clientes confirmen'
                        : 'Disponible por ${stats['income']['payments']} pagos (visitas y servicios)'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/payments'),
                  ),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: Card(
                      child: ListTile(
                        dense: true,
                        leading: Icon(sub?['plan']?['hasStats'] == true ? Icons.insights_rounded : Icons.lock_outline_rounded, color: NetJobColors.primary),
                        title: const Text('Estadísticas'),
                        subtitle: Text(sub?['plan']?['hasStats'] == true ? 'Ingresos por mes' : 'Desde plan Intermedio'),
                        onTap: () => open('/pro/insights'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Card(
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.campaign_rounded, color: NetJobColors.star),
                        title: Text(plan['featuredUntil'] != null ? 'Destacado' : 'Destacar perfil'),
                        subtitle: Text(plan['featuredUntil'] != null ? 'Hasta el ${fmtDate(plan['featuredUntil'])}' : 'Aparece primero'),
                        onTap: () => open('/pro/promotions'),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                // La disponibilidad se activa y desactiva sola según el horario del perfil;
                // el interruptor permite pausarla (vacaciones, enfermedad…).
                Builder(builder: (context) {
                  final (on, text) = availabilityText(profile['availabilityNow'], enabled: profile['isAvailable'] == true, own: true);
                  return Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    decoration: BoxDecoration(
                      color: NetJobColors.card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: on ? const Color(0x662E8B57) : NetJobColors.border),
                    ),
                    child: Row(children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: on ? NetJobColors.mint : NetJobColors.muted,
                          boxShadow: on ? const [BoxShadow(color: Color(0x992E8B57), blurRadius: 10)] : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(on ? 'Disponible ahora' : 'No disponible ahora', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                          Text(text, style: const TextStyle(color: NetJobColors.subtle, fontSize: 13)),
                          const Text('Se activa y desactiva solo según tus horarios.', style: TextStyle(color: NetJobColors.muted, fontSize: 12)),
                        ]),
                      ),
                    ]),
                  );
                }),
                const SizedBox(height: 8),
                SwitchListTile(
                  tileColor: NetJobColors.card,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: NetJobColors.border)),
                  title: const Text('Recibir solicitudes en mi horario'),
                  subtitle: const Text('Apágalo para pausar tu disponibilidad (vacaciones, incapacidad…)'),
                  value: profile['isAvailable'] == true,
                  onChanged: (v) async {
                    try {
                      await Api.instance.patch('/professionals/me/profile', {'isAvailable': v});
                      reload();
                    } catch (e) {
                      if (context.mounted) toast(context, e);
                    }
                  },
                ),
                if (missing.isNotEmpty) ...[
                  const SectionTitle('Completa tu perfil'),
                  Card(
                    child: Column(children: [
                      for (final m in missing)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.radio_button_unchecked, size: 20),
                          title: Text(m),
                          onTap: () async {
                            await context.push(m.contains('identidad')
                                ? '/pro/verification'
                                : m.contains('plan')
                                ? '/pro/subscription'
                                : m.contains('servicio')
                                    ? '/pro/services'
                                    : '/pro/profile');
                            reload();
                          },
                        ),
                    ]),
                  ),
                ],
                SectionTitle('Trabajos activos (${active.length})',
                    trailing: TextButton(onPressed: () => context.go('/requests'), child: const Text('Ver todos'))),
                if (active.isEmpty) Text('No tienes trabajos activos.', style: TextStyle(color: NetJobColors.muted)),
                for (final r in active.take(5))
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(r['service']['title']),
                      subtitle: Text('${r['client']['name']} · ${fmtDateTime(r['scheduledAt'])}'),
                      trailing: StatusChip(r['status']),
                      onTap: () async {
                        await context.push('/requests/${r['id']}');
                        reload();
                      },
                    ),
                  ),
              ]),
            );
          },
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.icon, {this.onTap});
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Expanded(
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: NetJobColors.primary, size: 20),
              const SizedBox(height: 6),
              Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              Text(label, style: TextStyle(fontSize: 12, color: NetJobColors.muted)),
            ]),
          ),
          ),
        ),
      );
}

// ============================ Mis servicios ============================

class MyServicesScreen extends StatelessWidget {
  const MyServicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AsyncView<List>(
      load: () => Future.wait([Api.instance.get('/services'), Api.instance.get('/subscriptions/me')]),
      builder: (context, data, reload) {
        final services = data[0] as List;
        final sub = data[1] as Map;
        final usage = (sub['usage'] as Map)['services'] as Map;
        final planName = sub['active']?['plan']?['name'];
        return Scaffold(
        appBar: AppBar(title: const Text('Mis servicios')),
        floatingActionButton: FloatingActionButton.extended(
          icon: const Icon(Icons.add),
          label: const Text('Publicar servicio'),
          onPressed: () async {
            // Con el límite alcanzado se ofrece mejorar el plan antes de llenar el formulario
            if (planName != null && usage['reached'] == true) {
              await handlePlanLimit(context, ApiException(403, 'Tu plan $planName permite máximo ${usage['max']} servicios publicados', code: 'PLAN_LIMIT'));
              return;
            }
            if (await context.push<bool>('/pro/services/edit') == true) reload();
          },
        ),
        body: services.isEmpty
            ? const EmptyState(
                icon: Icons.home_repair_service_outlined,
                title: 'Aún no has publicado servicios',
                message: 'Publica lo que sabes hacer con un precio de referencia ("desde") para que los clientes te encuentren.',
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                itemCount: services.length + 1,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, k) {
                  if (k == 0) {
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: UsageMeter(
                          label: planName == null ? 'Servicios publicados' : 'Servicios de tu plan $planName',
                          usage: usage,
                          onUpgrade: () async {
                            await context.push('/pro/subscription');
                            reload();
                          },
                        ),
                      ),
                    );
                  }
                  final s = services[k - 1];
                  return Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      title: Text(s['title'], style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${s['category']['name']}\nDesde ${cop(s['price'])} ${priceUnitLabel[s['priceUnit']]}'),
                      isThreeLine: true,
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'edit') {
                            if (await context.push<bool>('/pro/services/edit', extra: s) == true) reload();
                          } else if (v == 'delete') {
                            if (await confirm(context, 'Eliminar servicio', '¿Quitar "${s['title']}" de tu perfil?', ok: 'Eliminar')) {
                              try {
                                await Api.instance.delete('/services/${s['id']}');
                                reload();
                              } catch (e) {
                                if (context.mounted) toast(context, e);
                              }
                            }
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Editar')),
                          PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                        ],
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

class ServiceFormScreen extends StatefulWidget {
  const ServiceFormScreen({super.key, this.service});
  final Map? service;
  @override
  State<ServiceFormScreen> createState() => _ServiceFormScreenState();
}

class _ServiceFormScreenState extends State<ServiceFormScreen> {
  final _form = GlobalKey<FormState>();
  late final s = widget.service;
  late final _title = TextEditingController(text: s?['title']);
  late final _description = TextEditingController(text: s?['description']);
  late final _price = TextEditingController(text: s?['price']?.toString());
  late final _conditions = TextEditingController(text: s?['conditions']);
  late final _coverage = TextEditingController(text: s?['coverageArea']);
  late String? _categoryId = s?['categoryId'];
  late String _unit = s?['priceUnit'] ?? 'FIXED';
  final List<XFile> _newPhotos = [];
  bool _saving = false;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final body = {
        'categoryId': _categoryId,
        'title': _title.text.trim(),
        'description': _description.text.trim(),
        'price': int.parse(_price.text.replaceAll(RegExp(r'\D'), '')),
        'priceUnit': _unit,
        'conditions': _conditions.text.trim().isEmpty ? null : _conditions.text.trim(),
        'coverageArea': _coverage.text.trim().isEmpty ? null : _coverage.text.trim(),
      };
      final saved = s == null ? await Api.instance.post('/services', body) : await Api.instance.patch('/services/${s!['id']}', body);
      if (_newPhotos.isNotEmpty) await Api.instance.upload('/services/${saved['id']}/photos', _newPhotos, field: 'files');
      if (mounted) context.pop(true);
    } catch (e) {
      if (!mounted) return;
      final handled = await handlePlanLimit(context, e);
      if (!handled && mounted) toast(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(s == null ? 'Publicar servicio' : 'Editar servicio')),
      body: AsyncView<List>(
        load: () async => await Api.instance.get('/categories') as List,
        builder: (context, categories, _) => Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            DropdownButtonFormField<String>(
              initialValue: _categoryId,
              decoration: const InputDecoration(labelText: 'Categoría'),
              items: [for (final c in categories) DropdownMenuItem(value: c['id'] as String, child: Text(c['name']))],
              onChanged: (v) => _categoryId = v,
              validator: (v) => v == null ? 'Elige una categoría' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Nombre del servicio', hintText: 'Ej: Reparación de fugas'),
              validator: (v) => (v ?? '').trim().length >= 3 ? null : 'Mínimo 3 caracteres',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Descripción', alignLabelWithHint: true),
              validator: (v) => (v ?? '').trim().length >= 10 ? null : 'Mínimo 10 caracteres',
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _price,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Precio desde (COP)', prefixText: r'$ '),
                  validator: (v) => (int.tryParse((v ?? '').replaceAll(RegExp(r'\D'), '')) ?? 0) >= 1000 ? null : 'Mínimo \$1.000',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _unit,
                  decoration: const InputDecoration(labelText: 'Cobro'),
                  items: const [
                    DropdownMenuItem(value: 'FIXED', child: Text('Por trabajo')),
                    DropdownMenuItem(value: 'HOUR', child: Text('Por hora')),
                    DropdownMenuItem(value: 'VISIT', child: Text('Por visita')),
                  ],
                  onChanged: (v) => _unit = v!,
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: NetJobColors.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
              child: const Text(
                'Los clientes verán "Desde \$…": es un precio de referencia. El cliente paga primero la visita de diagnóstico y, después de revisar, tú le envías la cotización final según materiales y complejidad.',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _conditions,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Condiciones (opcional)', hintText: 'Materiales, garantía, recargos…', alignLabelWithHint: true),
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _coverage, decoration: const InputDecoration(labelText: 'Zona de cobertura (opcional)', hintText: 'Barrios o localidades')),
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (var k = 0; k < (s?['photos'] as List? ?? []).length; k++)
                PhotoThumb(urls: [for (final x in s!['photos']) x as String], index: k, heroPrefix: 'mi-servicio', width: 64, height: 64),
              for (final f in _newPhotos) Chip(label: Text(f.name), onDeleted: () => setState(() => _newPhotos.remove(f))),
              ActionChip(
                avatar: const Icon(Icons.add_a_photo_outlined, size: 18),
                label: const Text('Agregar fotos'),
                onPressed: () async {
                  final files = await ImagePicker().pickMultiImage(imageQuality: 75, maxWidth: 1600);
                  setState(() => _newPhotos.addAll(files));
                },
              ),
            ]),
            const SizedBox(height: 20),
            FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Guardando…' : 'Guardar')),
          ]),
        ),
      ),
    );
  }
}

// ============================ Perfil profesional / onboarding ============================

const _missingLabel = {
  'avatar': 'Foto de perfil',
  'headline': 'Título profesional',
  'bio': 'Descripción',
  'categories': 'Especialidades',
  'location': 'Zona de trabajo (ciudad, barrios y ubicación)',
  'availability': 'Horarios de atención',
  'portfolio': 'Fotos de portafolio',
  'training': 'Capacitación y reglas',
};

/// Perfil del profesional. Con [onboarding] es el paso obligatorio después del registro:
/// no se puede usar la app hasta completar foto, título, descripción, zona, horarios y portafolio.
class ProProfileEditScreen extends StatefulWidget {
  const ProProfileEditScreen({super.key, this.onboarding = false});
  final bool onboarding;
  @override
  State<ProProfileEditScreen> createState() => _ProProfileEditScreenState();
}

class _ProProfileEditScreenState extends State<ProProfileEditScreen> {
  Map? _p;
  List _categories = [];
  final _headline = TextEditingController();
  final _bio = TextEditingController();
  final _years = TextEditingController();
  final _diagFee = TextEditingController();
  final _city = TextEditingController();
  final _coverage = TextEditingController();
  double? _lat;
  double? _lng;
  bool _locating = false;
  Set<String> _cats = {};
  List<Map<String, dynamic>> _slots = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool keepForm = false}) async {
    try {
      final r = await Future.wait([Api.instance.get('/professionals/me/profile'), Api.instance.get('/categories')]);
      final p = r[0] as Map;
      if (!mounted) return;
      setState(() {
        _p = p;
        _categories = r[1] as List;
        if (keepForm) return;
        _headline.text = p['headline'] ?? '';
        _bio.text = p['bio'] ?? '';
        _years.text = '${p['yearsExperience'] ?? 0}';
        _diagFee.text = '${p['diagnosticFee'] ?? 0}';
        _city.text = p['city'] ?? '';
        _coverage.text = p['coverageArea'] ?? '';
        _lat = (p['lat'] as num?)?.toDouble();
        _lng = (p['lng'] as num?)?.toDouble();
        _cats = {for (final c in p['categories']) c['id'] as String};
        _slots = [for (final a in p['availability']) {'dayOfWeek': a['dayOfWeek'], 'startTime': a['startTime'], 'endTime': a['endTime']}];
      });
    } catch (e) {
      if (mounted) toast(context, e);
    }
  }

  int get _minPortfolio => (_p?['minPortfolio'] as num?)?.toInt() ?? 2;

  /// Qué falta según lo que hay en pantalla (para mostrar el progreso antes de guardar).
  Map<String, bool> _checks(Map? user) => {
        'avatar': user?['avatarUrl'] != null,
        'headline': _headline.text.trim().isNotEmpty,
        'bio': _bio.text.trim().isNotEmpty,
        'categories': _cats.isNotEmpty,
        'location': _city.text.trim().isNotEmpty && _coverage.text.trim().isNotEmpty && _lat != null,
        'availability': _slots.isNotEmpty,
        'portfolio': ((_p?['portfolio'] as List?)?.length ?? 0) >= _minPortfolio,
        'training': _p?['trainingPassedAt'] != null,
      };

  int get _maxDiagFee => (_p?['maxDiagnosticFee'] as num?)?.toInt() ?? 35000;

  Future<void> _save() async {
    final fee = int.tryParse(_diagFee.text.replaceAll(RegExp(r'\D'), '')) ?? 0;
    if (fee > _maxDiagFee) {
      return toast(context, 'La visita de diagnóstico puede costar máximo ${cop(_maxDiagFee)}');
    }
    if (fee > 0 && fee < 1000) {
      return toast(context, 'Si cobras la visita, el mínimo es \$1.000. Pon 0 para que sea gratis.');
    }
    setState(() => _saving = true);
    String? nn(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    try {
      await Api.instance.patch('/professionals/me/profile', {
        'diagnosticFee': fee,
        'headline': nn(_headline),
        'bio': nn(_bio),
        'yearsExperience': int.tryParse(_years.text) ?? 0,
        'city': nn(_city),
        'coverageArea': nn(_coverage),
        'lat': _lat,
        'lng': _lng,
        'categoryIds': _cats.toList(),
      });
      await Api.instance.put('/professionals/me/availability', {'slots': _slots});
      if (!mounted) return;
      final auth = context.read<AuthState>();
      await auth.reloadUser();
      if (!mounted) return;
      final missing = auth.proMissing;
      if (widget.onboarding) {
        if (missing.isEmpty) {
          toast(context, '¡Perfil completo! Ahora verifica tu identidad y activa tu plan para aparecer en las búsquedas.', error: false);
          context.go('/home');
          return;
        }
        toast(context, 'Te falta: ${missing.map((m) => _missingLabel[m] ?? m).join(', ')}');
      } else {
        toast(context, 'Perfil actualizado', error: false);
      }
      await _load();
    } catch (e) {
      if (mounted) toast(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addPortfolio() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 1600);
    if (file == null || !mounted) return;
    final title = await promptText(context, 'Título del trabajo', hint: 'Ej: Remodelación de baño', ok: 'Subir', minLength: 2);
    if (title == null) return;
    try {
      await Api.instance.upload('/professionals/me/portfolio', [file], fields: {'title': title});
      await _load(keepForm: true);
    } catch (e) {
      if (!mounted) return;
      final handled = await handlePlanLimit(context, e);
      if (!handled && mounted) toast(context, e);
    }
  }

  Future<void> _changeAvatar() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 800);
    if (file == null) return;
    try {
      await Api.instance.upload('/me/avatar', [file]);
      if (mounted) await context.read<AuthState>().reloadUser();
    } catch (e) {
      if (mounted) toast(context, e);
    }
  }

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    final loc = context.read<LocationState>();
    await loc.useDeviceLocation();
    if (!mounted) return;
    setState(() => _locating = false);
    if (loc.hasLocation && !loc.manual) {
      setState(() {
        _lat = loc.lat;
        _lng = loc.lng;
        if (_city.text.trim().isEmpty) _city.text = nearestCity(loc.lat!, loc.lng!) ?? '';
      });
    } else {
      toast(context, loc.message ?? 'No pudimos obtener tu ubicación. Elige tu ciudad.');
    }
  }

  Future<void> _pickCity() async {
    final c = await showModalBottomSheet<(String, double, double)>(
      context: context,
      showDragHandle: true,
      builder: (s) => ListView(children: [
        for (final c in colombianCities) ListTile(title: Text(c.$1), onTap: () => Navigator.pop(s, c)),
      ]),
    );
    if (c == null) return;
    setState(() {
      _city.text = c.$1;
      _lat = c.$2;
      _lng = c.$3;
    });
  }

  Future<void> _addSlot() async {
    int day = 1;
    TimeOfDay start = const TimeOfDay(hour: 8, minute: 0);
    TimeOfDay end = const TimeOfDay(hour: 17, minute: 0);
    String f(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Agregar horario'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<int>(
              initialValue: day,
              items: [for (var i = 0; i < 7; i++) DropdownMenuItem(value: i, child: Text(weekdays[i]))],
              onChanged: (v) => set(() => day = v!),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () async {
                final t = await showTimePicker(context: c, initialTime: start);
                if (t != null) set(() => start = t);
              }, child: Text('Desde ${f(start)}'))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton(onPressed: () async {
                final t = await showTimePicker(context: c, initialTime: end);
                if (t != null) set(() => end = t);
              }, child: Text('Hasta ${f(end)}'))),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Agregar')),
          ],
        ),
      ),
    );
    if (ok == true) {
      if (f(start).compareTo(f(end)) >= 0) {
        if (mounted) toast(context, 'La hora de inicio debe ser antes de la hora de fin');
        return;
      }
      setState(() => _slots
        ..add({'dayOfWeek': day, 'startTime': f(start), 'endTime': f(end)})
        ..sort((a, b) => (a['dayOfWeek'] as int).compareTo(b['dayOfWeek'] as int)));
    }
  }

  /// Encabezado de sección con indicador de completado.
  Widget _step(String key, String title, Map<String, bool> checks, {Widget? trailing}) {
    final done = checks[key] ?? true;
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Row(children: [
        Icon(done ? Icons.check_circle : Icons.radio_button_unchecked, size: 20, color: done ? NetJobColors.accent : NetJobColors.muted),
        const SizedBox(width: 8),
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
        ?trailing,
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    final auth = context.watch<AuthState>();
    final user = auth.user;
    final checks = _checks(user);
    final done = checks.values.where((v) => v).length;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.onboarding,
        title: Text(widget.onboarding ? 'Completa tu perfil' : 'Mi perfil profesional'),
        actions: [
          if (widget.onboarding)
            TextButton(onPressed: auth.logout, child: const Text('Salir'))
          else if (p != null)
            TextButton(onPressed: () => context.push('/pro/${p['id']}'), child: const Text('Vista pública')),
        ],
      ),
      bottomNavigationBar: p == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Guardando…' : widget.onboarding ? 'Guardar y continuar ($done/${checks.length})' : 'Guardar cambios'),
                ),
              ),
            ),
      body: p == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
              if (widget.onboarding)
                Card(
                  color: NetJobColors.primary.withValues(alpha: 0.06),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Antes de empezar', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      const SizedBox(height: 4),
                      Text('Los clientes contratan a quien les da confianza. Completa todos los puntos para que tu perfil aparezca en las búsquedas.',
                          style: TextStyle(color: NetJobColors.subtle)),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(value: done / checks.length, minHeight: 6, borderRadius: BorderRadius.circular(4)),
                    ]),
                  ),
                ),
              _step('avatar', '1. Foto de perfil', checks),
              Center(
                child: Stack(children: [
                  GestureDetector(
                    onTap: user?['avatarUrl'] == null ? null : () => openPhotoViewer(context, [user!['avatarUrl']], heroPrefix: 'mi-avatar'),
                    child: Hero(
                      tag: photoHeroTag('mi-avatar', 0, user?['avatarUrl'] ?? ''),
                      child: UserAvatar(url: user?['avatarUrl'], name: user?['name'] ?? '', radius: 48),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: IconButton.filled(iconSize: 18, onPressed: _changeAvatar, icon: const Icon(Icons.camera_alt)),
                  ),
                ]),
              ),
              if (checks['avatar'] != true)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Una foto clara de tu cara genera más confianza.', textAlign: TextAlign.center, style: TextStyle(color: NetJobColors.muted, fontSize: 12)),
                ),
              _step('headline', '2. Título y descripción', {'headline': checks['headline']! && checks['bio']!}),
              TextField(
                controller: _headline,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Título', hintText: 'Ej: Electricista certificado con 10 años de experiencia'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bio,
                maxLines: 4,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Descripción: qué haces y cómo trabajas', alignLabelWithHint: true),
              ),
              const SizedBox(height: 12),
              TextField(controller: _years, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Años de experiencia')),
              const SizedBox(height: 12),
              TextField(
                controller: _diagFee,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Valor de tu visita de diagnóstico',
                  prefixText: '\$ ',
                  helperText: 'Lo paga el cliente cuando aceptas, sin comisión. Máximo ${cop(_maxDiagFee)}. Pon 0 si es gratis.',
                  helperMaxLines: 2,
                ),
              ),
              _step('categories', '3. Especialidades', checks),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final c in _categories)
                  FilterChip(
                    label: Text(c['name']),
                    selected: _cats.contains(c['id']),
                    onSelected: (v) => setState(() => v ? _cats.add(c['id']) : _cats.remove(c['id'])),
                  ),
              ]),
              _step('location', '4. Zona de trabajo', checks),
              Text('Los clientes te encuentran si estás a máximo 12 km de ellos.', style: TextStyle(color: NetJobColors.subtle, fontSize: 13)),
              const SizedBox(height: 10),
              TextField(controller: _city, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Ciudad')),
              const SizedBox(height: 12),
              TextField(
                controller: _coverage,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Barrios o zonas que cubres', hintText: 'Ej: Bocagrande, Manga, Crespo'),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                OutlinedButton.icon(
                  onPressed: _locating ? null : _useMyLocation,
                  icon: _locating
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.my_location),
                  label: const Text('Usar mi ubicación actual'),
                ),
                OutlinedButton.icon(onPressed: _pickCity, icon: const Icon(Icons.location_city), label: const Text('Elegir ciudad')),
              ]),
              const SizedBox(height: 8),
              Text(
                _lat == null ? 'Aún no has marcado tu ubicación.' : 'Ubicación marcada (${_lat!.toStringAsFixed(4)}, ${_lng!.toStringAsFixed(4)})',
                style: TextStyle(fontSize: 12, color: _lat == null ? const Color(0xFFC77A12) : NetJobColors.accent),
              ),
              if (mapsAvailable) ...[
                const SizedBox(height: 8),
                Text('También puedes tocar el mapa para ajustar el punto central de tu zona.', style: TextStyle(fontSize: 12, color: NetJobColors.muted)),
                const SizedBox(height: 8),
                LocationPickerMap(lat: _lat, lng: _lng, onChanged: (a, b) => setState(() {
                  _lat = a;
                  _lng = b;
                })),
              ],
              _step('availability', '5. Horarios de atención', checks,
                  trailing: TextButton.icon(onPressed: _addSlot, icon: const Icon(Icons.add), label: const Text('Agregar'))),
              if (_slots.isEmpty) Text('Agrega al menos un día y horario.', style: TextStyle(color: NetJobColors.muted)),
              for (final s in List.of(_slots))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${weekdays[s['dayOfWeek']]}  ${s['startTime']} – ${s['endTime']}'),
                  trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _slots.remove(s))),
                ),
              _step('portfolio', '6. Portafolio (mínimo $_minPortfolio fotos)', checks,
                  trailing: TextButton.icon(onPressed: _addPortfolio, icon: const Icon(Icons.add_photo_alternate_outlined), label: const Text('Subir foto'))),
              if (p['usage'] != null && ((p['usage'] as Map)['portfolio'] as Map)['max'] != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: UsageMeter(
                    label: 'Fotos de tu plan',
                    usage: (p['usage'] as Map)['portfolio'],
                    onUpgrade: widget.onboarding ? null : () => context.push('/pro/subscription'),
                  ),
                ),
              if ((p['portfolio'] as List).isEmpty)
                Text('Sube fotos de trabajos que hayas hecho: es lo primero que miran los clientes.', style: TextStyle(color: NetJobColors.muted)),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: [
                  for (final (k, item) in (p['portfolio'] as List).indexed)
                    Stack(fit: StackFit.expand, children: [
                      PhotoThumb(
                        urls: [for (final x in p['portfolio']) x['imageUrl'] as String],
                        captions: [for (final x in p['portfolio']) x['title'] as String?],
                        index: k,
                        heroPrefix: 'mi-portafolio',
                      ),
                      Positioned(
                        right: 2,
                        top: 2,
                        child: IconButton.filledTonal(
                          iconSize: 16,
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            try {
                              await Api.instance.delete('/professionals/me/portfolio/${item['id']}');
                              await _load(keepForm: true);
                            } catch (e) {
                              if (context.mounted) toast(context, e);
                            }
                          },
                        ),
                      ),
                    ]),
                ],
              ),
              _step('training', '7. Capacitación y reglas', checks),
              Card(
                color: checks['training'] == true ? null : NetJobColors.primary.withValues(alpha: 0.06),
                child: ListTile(
                  leading: Icon(checks['training'] == true ? Icons.workspace_premium_rounded : Icons.school_rounded,
                      color: checks['training'] == true ? NetJobColors.mint : NetJobColors.primary),
                  title: Text(checks['training'] == true ? 'Capacitación aprobada' : 'Lee los instructivos y responde el cuestionario'),
                  subtitle: Text(checks['training'] == true
                      ? 'Puedes volver a leer los instructivos cuando quieras'
                      : 'Atención al cliente, cumplimiento, seguridad y reglas de NetJob. Es obligatoria para aparecer en las búsquedas.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await context.push(checks['training'] == true && !widget.onboarding ? '/pro/guides' : '/pro/training');
                    if (!mounted) return;
                    await _load(keepForm: true);
                  },
                ),
              ),
            ]),
    );
  }
}
