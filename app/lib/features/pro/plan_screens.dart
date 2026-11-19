import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

// ============================ Piezas compartidas ============================

/// Insignia del plan visible para clientes y profesionales ("Plus", "Premium").
class PlanBadge extends StatelessWidget {
  const PlanBadge(this.badge, {super.key, this.compact = false});
  final String? badge;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (badge == null || badge!.isEmpty) return const SizedBox.shrink();
    final premium = badge!.toLowerCase() == 'premium';
    return Tooltip(
      message: premium ? 'Profesional con plan Premium' : 'Profesional con plan $badge',
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 9, vertical: compact ? 2 : 4),
        decoration: BoxDecoration(
          gradient: premium ? const LinearGradient(colors: [Color(0xFFFFD98A), Color(0xFFFFB86B)]) : null,
          color: premium ? null : NetJobColors.primary.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(8),
          border: premium ? null : Border.all(color: NetJobColors.primary.withValues(alpha: 0.5)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(premium ? Icons.workspace_premium_rounded : Icons.bolt_rounded, size: compact ? 11 : 14, color: premium ? const Color(0xFF3A2400) : NetJobColors.primaryLight),
          const SizedBox(width: 3),
          Text(badge!,
              style: TextStyle(fontSize: compact ? 10 : 12, fontWeight: FontWeight.w800, color: premium ? const Color(0xFF3A2400) : NetJobColors.primaryLight)),
        ]),
      ),
    );
  }
}

/// "2 de 3 servicios": barra de uso frente al límite del plan.
class UsageMeter extends StatelessWidget {
  const UsageMeter({super.key, required this.label, required this.usage, this.onUpgrade});
  final String label;
  final Map usage;
  final VoidCallback? onUpgrade;

  @override
  Widget build(BuildContext context) {
    final used = (usage['used'] as num).toInt();
    final max = (usage['max'] as num?)?.toInt();
    final reached = usage['reached'] == true;
    final near = usage['near'] == true;
    final color = reached ? NetJobColors.danger : near ? NetJobColors.warning : NetJobColors.mint;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
        Text(max == null ? '$used · ilimitado' : '$used de $max', style: TextStyle(fontWeight: FontWeight.w800, color: max == null ? NetJobColors.mint : color)),
      ]),
      const SizedBox(height: 6),
      LinearProgressIndicator(
        value: max == null ? 1 : (used / max).clamp(0.0, 1.0),
        minHeight: 7,
        borderRadius: BorderRadius.circular(6),
        color: max == null ? NetJobColors.mint.withValues(alpha: 0.5) : color,
      ),
      if (max != null && (reached || near) && onUpgrade != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(children: [
            Expanded(
              child: Text(reached ? 'Llegaste al límite de tu plan.' : 'Te queda 1 antes del límite de tu plan.', style: TextStyle(fontSize: 12.5, color: color)),
            ),
            TextButton(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
              onPressed: onUpgrade,
              child: const Text('Mejorar plan'),
            ),
          ]),
        ),
    ]);
  }
}

/// Cuando el backend rechaza algo por el plan (límite o función no incluida), en lugar de un
/// error se ofrece mejorar la suscripción. Devuelve true si el error era de plan.
Future<bool> handlePlanLimit(BuildContext context, Object error) async {
  if (error is! ApiException || !error.isPlanLimit) return false;
  final go = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.workspace_premium_rounded, color: NetJobColors.star, size: 36),
      title: Text(error.code == 'PLAN_REQUIRED' ? 'Incluido en un plan superior' : 'Llegaste al límite de tu plan'),
      content: Text('${error.message}.\n\nMejora tu plan para publicar más, subir más fotos y aparecer antes en las búsquedas.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Ahora no')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Ver planes')),
      ],
    ),
  );
  if (go == true && context.mounted) context.push('/pro/subscription');
  return true;
}

/// Completa un checkout: abre Wompi o, en modo pruebas, simula la respuesta de la pasarela.
/// Devuelve true si el pago quedó aprobado (en Wompi se confirma después, al volver).
Future<bool> completeCheckout(BuildContext context, Map co, {required String what}) async {
  if (co['mode'] == 'wompi') {
    await launchUrl(Uri.parse(co['checkoutUrl']), mode: LaunchMode.externalApplication);
    if (context.mounted) toast(context, 'Completa el pago de $what en Wompi. Se activará al confirmarse.', error: false);
    return false;
  }
  final approve = await confirm(
    context,
    'Pago en modo pruebas',
    'Pago de $what: ${cop(co['payment']['totalAmount'])}\n\nWompi no está configurado en el servidor. ¿Simular pago aprobado?',
    ok: 'Simular aprobado',
  );
  if (!approve) return false;
  final p = await Api.instance.post('/payments/${co['payment']['id']}/simulate', {'status': 'APPROVED'});
  return p['status'] == 'APPROVED';
}

// ============================ Suscripción ============================

class SubscriptionScreen extends StatelessWidget {
  const SubscriptionScreen({super.key});

  Future<void> _choose(BuildContext context, Map plan, int discountPct, Future<void> Function() reload) async {
    final price = (plan['priceMonthly'] as num).toInt();
    final total = price - (price * discountPct / 100).round();
    final msg = discountPct > 0
        ? 'Pagarás ${cop(total)} por 30 días (${cop(price)} menos $discountPct % por tu calificación y actividad).'
        : 'Pagarás ${cop(price)} por 30 días de suscripción.';
    if (!await confirm(context, 'Plan ${plan['name']}', msg, ok: 'Continuar al pago')) return;
    try {
      final co = await Api.instance.post('/subscriptions/checkout', {'planId': plan['id']});
      if (!context.mounted) return;
      final ok = await completeCheckout(context, co, what: 'el plan ${plan['name']}');
      if (ok && context.mounted) toast(context, 'Plan ${plan['name']} activado', error: false);
      await reload();
    } catch (e) {
      if (context.mounted) toast(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mi suscripción')),
      body: AsyncView<List>(
        load: () => Future.wait([Api.instance.get('/subscriptions/plans'), Api.instance.get('/subscriptions/me')]),
        builder: (context, data, reload) {
          final plans = (data[0] as List).cast<Map>();
          final me = data[1] as Map;
          final active = me['active'] as Map?;
          final history = me['history'] as List;
          final usage = me['usage'] as Map;
          final value = me['value'] as Map?;
          final perf = me['performance'] as Map;
          final discount = (perf['discountPct'] as num).toInt();
          final currentId = active?['planId'];
          final currentIdx = plans.indexWhere((p) => p['id'] == currentId);
          void scrollToPlans() => Scrollable.ensureVisible(_plansKey.currentContext!, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);

          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              _header(context, active, me, plans, reload, discount),
              if (value != null) ...[const SizedBox(height: 12), _valueCard(context, value, active!)],
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(active == null ? 'Lo que puedes publicar' : 'Uso de tu plan', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 12),
                    UsageMeter(label: 'Servicios publicados', usage: usage['services'], onUpgrade: scrollToPlans),
                    const SizedBox(height: 14),
                    UsageMeter(label: 'Fotos de portafolio', usage: usage['portfolio'], onUpgrade: scrollToPlans),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              _performanceCard(context, perf),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.campaign_rounded, color: NetJobColors.star),
                  title: Text(me['featuredUntil'] != null ? 'Tu perfil está destacado' : 'Destaca tu perfil'),
                  subtitle: Text(me['featuredUntil'] != null
                      ? 'Apareces primero en tu zona hasta el ${fmtDate(me['featuredUntil'])}'
                      : 'Aparece primero en las búsquedas de tu zona'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await context.push('/pro/promotions');
                    reload();
                  },
                ),
              ),
              SectionTitle('Compara los planes', key: _plansKey),
              _comparison(context, plans, currentIdx),
              const SizedBox(height: 4),
              for (final plan in plans) _planCard(context, plan, active, discount, reload),
              if (history.isNotEmpty) ...[
                const SectionTitle('Historial'),
                for (final h in history)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('Plan ${h['plan']['name']} · ${cop(h['plan']['priceMonthly'])}'),
                    subtitle: Text('${fmtDate(h['startsAt'])} – ${fmtDate(h['endsAt'])}'),
                    trailing: Text({'ACTIVE': 'Activa', 'EXPIRED': 'Vencida', 'CANCELLED': 'Cancelada'}[h['status']] ?? h['status']),
                  ),
              ],
              const SizedBox(height: 24),
            ]),
          );
        },
      ),
    );
  }

  static final _plansKey = GlobalKey();

  /// Plan actual, días que quedan y aviso de renovación.
  Widget _header(BuildContext context, Map? active, Map me, List<Map> plans, Future<void> Function() reload, int discount) {
    if (active == null) {
      return const Card(
        color: Color(0xFF2A1A33),
        child: ListTile(
          leading: Icon(Icons.info_outline, color: NetJobColors.warning),
          title: Text('Elige un plan para empezar'),
          subtitle: Text('Sin un plan activo no apareces en las búsquedas, no puedes publicar servicios ni aceptar solicitudes.'),
        ),
      );
    }
    final plan = active['plan'] as Map;
    final days = (me['daysLeft'] as num?)?.toInt() ?? 0;
    final soon = me['expiringSoon'] == true;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: NetJobColors.heroGradient,
        borderRadius: BorderRadius.circular(24),
        border: soon ? Border.all(color: NetJobColors.warning, width: 1.5) : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Plan ${plan['name']}', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800))),
          PlanBadge(plan['badge']),
        ]),
        const SizedBox(height: 4),
        Text(
          soon
              ? (days <= 1 ? 'Vence mañana (${fmtDate(active['endsAt'])}). Renueva para no desaparecer de las búsquedas.' : 'Vence en $days días (${fmtDate(active['endsAt'])}). Renueva para no desaparecer de las búsquedas.')
              : 'Activo hasta el ${fmtDate(active['endsAt'])} · quedan $days días',
          style: TextStyle(color: soon ? NetJobColors.warning : NetJobColors.textSoft, fontWeight: soon ? FontWeight.w700 : null),
        ),
        const SizedBox(height: 12),
        Row(children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => _choose(context, plans.firstWhere((p) => p['id'] == active['planId'], orElse: () => plan), discount, reload),
            icon: const Icon(Icons.autorenew_rounded, size: 18),
            label: const Text('Renovar'),
          ),
          const SizedBox(width: 10),
          const Expanded(child: Text('Renovar suma 30 días a tu fecha actual.', style: TextStyle(color: NetJobColors.subtle, fontSize: 12.5))),
        ]),
      ]),
    );
  }

  /// "Este mes tu plan te trajo 8 solicitudes y $450.000".
  Widget _valueCard(BuildContext context, Map v, Map active) {
    Widget kpi(String value, String label, IconData icon) => Expanded(
          child: Column(children: [
            Icon(icon, size: 20, color: NetJobColors.primary),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontFamily: NetJobFonts.display, fontSize: 20, fontWeight: FontWeight.w800)),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(color: NetJobColors.subtle, fontSize: 12)),
          ]),
        );
    final none = (v['requests'] as num) == 0 && (v['views'] as num) == 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Lo que tu plan te ha traído', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          Text('Desde el ${fmtDate(v['since'])}', style: const TextStyle(color: NetJobColors.muted, fontSize: 12.5)),
          const SizedBox(height: 14),
          Row(children: [
            kpi('${v['views']}', 'visitas al perfil', Icons.visibility_outlined),
            kpi('${v['requests']}', 'solicitudes', Icons.inbox_outlined),
            kpi('${v['completed']}', 'finalizados', Icons.task_alt),
          ]),
          const Divider(height: 26),
          Row(children: [
            const Icon(Icons.payments_outlined, color: NetJobColors.mint),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                none ? 'Completa tu perfil y publica más servicios para empezar a recibir solicitudes.' : 'Ingresos por servicios en este periodo',
                style: const TextStyle(color: NetJobColors.subtle),
              ),
            ),
            if (!none) Text(cop(v['income']), style: TextStyle(fontFamily: NetJobFonts.display, fontSize: 20, fontWeight: FontWeight.w800, color: NetJobColors.mint)),
          ]),
          if ((active['plan'] as Map)['hasStats'] == true)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => context.push('/pro/insights'),
                icon: const Icon(Icons.insights_rounded, size: 18),
                label: const Text('Ver estadísticas detalladas'),
              ),
            ),
        ]),
      ),
    );
  }

  /// Premio por desempeño: descuento en la siguiente suscripción y potenciador.
  Widget _performanceCard(BuildContext context, Map perf) {
    final goals = perf['goals'] as Map;
    final discount = (perf['discountPct'] as num).toInt();
    final rating = (perf['ratingAvg'] as num).toDouble();
    final count = (perf['ratingCount'] as num).toInt();
    final recent = (perf['recentServices'] as num).toInt();
    final ratingOk = count >= (goals['minReviews'] as num) && rating >= (goals['minRating'] as num);
    final boost = perf['boostUntil'];
    Widget goal(bool ok, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked, size: 18, color: ok ? NetJobColors.mint : NetJobColors.muted),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5, height: 1.3))),
          ]),
        );
    return Card(
      color: discount > 0 ? NetJobColors.accent.withValues(alpha: 0.07) : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.trending_up_rounded, color: discount > 0 ? NetJobColors.mint : NetJobColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(discount > 0 ? '¡Tienes $discount % de descuento!' : 'Premios por buen desempeño', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            discount > 0
                ? 'Se aplica solo en tu próxima renovación o cambio de plan.'
                : 'Mantén una calificación alta y actividad constante para pagar menos por tu plan y subir en los resultados.',
            style: const TextStyle(color: NetJobColors.subtle, height: 1.35),
          ),
          const SizedBox(height: 12),
          goal(ratingOk, 'Calificación de ${goals['minRating']} o más con al menos ${goals['minReviews']} reseñas · tienes ${count == 0 ? 'sin reseñas' : '$rating ($count)'}'),
          goal(recent >= (goals['services'] as num), '${goals['services']} servicios finalizados en 30 días → 10 % de descuento · llevas $recent'),
          goal(recent >= (goals['servicesTop'] as num), '${goals['servicesTop']} servicios finalizados en 30 días → 12 % de descuento'),
          if (boost != null) ...[
            const Divider(height: 20),
            Row(children: [
              const Icon(Icons.rocket_launch_rounded, size: 18, color: NetJobColors.star),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Potenciador de recomendación activo hasta el ${fmtDate(boost)}: apareces más arriba y con la etiqueta "Recomendado".',
                    style: const TextStyle(fontSize: 13.5, height: 1.3)),
              ),
            ]),
          ],
        ]),
      ),
    );
  }

  /// Tabla comparativa: los beneficios de los tres planes lado a lado.
  Widget _comparison(BuildContext context, List<Map> plans, int currentIdx) {
    final boosts = plans.map((p) => (p['searchBoost'] as num).toInt()).toList();
    final maxBoost = boosts.fold<int>(0, (a, b) => a > b ? a : b);
    String position(int b) => b == 0 ? 'Normal' : b == maxBoost ? 'Máxima' : 'Media';
    String limit(dynamic v) => v == null ? 'Sin límite' : '$v';

    final rows = <(String, List<Object>)>[
      ('Servicios publicados', [for (final p in plans) limit(p['maxServices'])]),
      ('Fotos de portafolio', [for (final p in plans) limit(p['maxPortfolio'])]),
      ('Posición en búsquedas', [for (final b in boosts) position(b)]),
      ('Insignia visible al cliente', [for (final p in plans) p['badge'] ?? false]),
      ('Estadísticas de ingresos', [for (final p in plans) p['hasStats'] == true]),
      ('Perfil destacado incluido', [for (final p in plans) (p['featuredDays'] as num) > 0 ? '${p['featuredDays']} días' : false]),
      ('Primero en recomendados', [for (final p in plans) p['recommendationPriority'] == true]),
      ('Verificación prioritaria', [for (final p in plans) p['verificationPriority'] == true]),
      ('Soporte prioritario', [for (final p in plans) p['prioritySupport'] == true]),
      ('Chat y pagos en la app', [for (final _ in plans) true]),
    ];

    Widget cell(Object v, bool current) => Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
          color: current ? NetJobColors.primary.withValues(alpha: 0.10) : null,
          child: v is bool
              ? Icon(v ? Icons.check_circle_rounded : Icons.remove_rounded, size: 18, color: v ? NetJobColors.mint : const Color(0xFF5E5275))
              : Text('$v', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
        );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Table(
        columnWidths: const {0: FlexColumnWidth(1.5)},
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        border: const TableBorder(horizontalInside: BorderSide(color: Color(0xFF241834))),
        children: [
          TableRow(children: [
            const SizedBox.shrink(),
            for (final (i, p) in plans.indexed)
              Container(
                padding: const EdgeInsets.fromLTRB(2, 10, 2, 10),
                color: i == currentIdx ? NetJobColors.primary.withValues(alpha: 0.10) : null,
                child: Column(children: [
                  if (p['popular'] == true)
                    Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(gradient: NetJobColors.gradient, borderRadius: BorderRadius.circular(8)),
                      child: const Text('Más popular', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: NetJobColors.onPrimary)),
                    )
                  else
                    const SizedBox(height: 19),
                  Text(p['name'], textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                  Text(cop(p['priceMonthly']), style: const TextStyle(fontSize: 11.5, color: NetJobColors.primary, fontWeight: FontWeight.w700)),
                  if (i == currentIdx) const Text('Tu plan', style: TextStyle(fontSize: 10.5, color: NetJobColors.mint, fontWeight: FontWeight.w700)),
                ]),
              ),
          ]),
          for (final r in rows)
            TableRow(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 9, 4, 9),
                child: Text(r.$1, style: const TextStyle(fontSize: 12.5, color: NetJobColors.textSoft)),
              ),
              for (final (i, v) in r.$2.indexed) cell(v, i == currentIdx),
            ]),
        ],
      ),
    );
  }

  Widget _planCard(BuildContext context, Map plan, Map? active, int discount, Future<void> Function() reload) {
    final current = active?['planId'] == plan['id'];
    final popular = plan['popular'] == true;
    final price = (plan['priceMonthly'] as num).toInt();
    final total = price - (price * discount / 100).round();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: current ? NetJobColors.primary : popular ? NetJobColors.primary.withValues(alpha: 0.45) : const Color(0xFF2A1E3D), width: current ? 2 : 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(plan['name'], style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
              const SizedBox(width: 8),
              PlanBadge(plan['badge']),
              if (popular) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(gradient: NetJobColors.gradient, borderRadius: BorderRadius.circular(8)),
                  child: const Text('Más popular', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: NetJobColors.onPrimary)),
                ),
              ],
              const Spacer(),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                if (discount > 0) Text(cop(price), style: const TextStyle(fontSize: 12.5, color: NetJobColors.muted, decoration: TextDecoration.lineThrough)),
                Text.rich(TextSpan(children: [
                  TextSpan(text: cop(total), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: NetJobColors.primary)),
                  const TextSpan(text: ' /mes', style: TextStyle(fontSize: 12.5)),
                ])),
              ]),
            ]),
            if (plan['description'] != null) Text(plan['description'], style: const TextStyle(color: NetJobColors.subtle)),
            const SizedBox(height: 10),
            for (final f in plan['features'])
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.check, size: 18, color: NetJobColors.accent),
                  const SizedBox(width: 6),
                  Expanded(child: Text(f)),
                ]),
              ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: current
                  ? OutlinedButton(onPressed: () => _choose(context, plan, discount, reload), child: const Text('Renovar'))
                  : FilledButton(onPressed: () => _choose(context, plan, discount, reload), child: Text(active == null ? 'Elegir plan' : 'Cambiar a este plan')),
            ),
          ]),
        ),
      ),
    );
  }
}

// ============================ Estadísticas detalladas (desde Intermedio) ============================

class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Estadísticas de ingresos')),
      body: AsyncView<Map>(
        // Sin el plan adecuado no es un error: se muestra qué incluye y cómo obtenerlo
        load: () async {
          try {
            return await Api.instance.get('/professionals/me/insights') as Map;
          } on ApiException catch (e) {
            if (e.isPlanLimit) return {'locked': e.message};
            rethrow;
          }
        },
        builder: (context, s, reload) {
          if (s['locked'] != null) return _locked(context, s['locked']);
          final months = (s['months'] as List).cast<Map>();
          final top = (s['topServices'] as List).cast<Map>();
          final req = s['requests'] as Map;
          final max = months.fold<num>(1, (m, x) => (x['income'] as num) > m ? x['income'] as num : m);
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Ingresos de los últimos 6 meses', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    Text(cop(s['total']), style: TextStyle(fontFamily: NetJobFonts.display, fontSize: 28, fontWeight: FontWeight.w800, color: NetJobColors.mint)),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 150,
                      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        for (final m in months)
                          Expanded(
                            child: Tooltip(
                              message: '${cop(m['income'])} · ${m['payments']} pagos',
                              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                                if ((m['income'] as num) > 0)
                                  Text(_short(m['income'] as num), style: const TextStyle(fontSize: 10.5, color: NetJobColors.subtle)),
                                const SizedBox(height: 3),
                                Container(
                                  height: 4 + 100 * (m['income'] as num) / max,
                                  margin: const EdgeInsets.symmetric(horizontal: 5),
                                  decoration: BoxDecoration(
                                    gradient: (m['income'] as num) > 0 ? NetJobColors.gradient : null,
                                    color: (m['income'] as num) > 0 ? null : NetJobColors.cardHigh,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(_month(m['key']), style: const TextStyle(fontSize: 11.5, color: NetJobColors.muted)),
                              ]),
                            ),
                          ),
                      ]),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                _kpi('${s['conversion']} %', 'solicitudes que aceptaste', Icons.swap_vert_rounded),
                const SizedBox(width: 10),
                _kpi('${s['views']}', 'visitas a tu perfil', Icons.visibility_outlined),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                _kpi('${req['received']}', 'solicitudes recibidas', Icons.inbox_outlined),
                const SizedBox(width: 10),
                _kpi('${req['completed']}', 'servicios finalizados', Icons.task_alt),
              ]),
              const SectionTitle('Servicios que más ingresos te dan'),
              if (top.isEmpty) const Text('Aún no hay servicios pagados en este periodo.', style: TextStyle(color: NetJobColors.muted)),
              for (final t in top)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(t['title']),
                    subtitle: Text('${t['count']} ${t['count'] == 1 ? 'vez contratado' : 'veces contratado'}'),
                    trailing: Text(cop(t['income']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  ),
                ),
            ]),
          );
        },
      ),
    );
  }

  static String _short(num v) => v >= 1000000 ? '${(v / 1000000).toStringAsFixed(1)}M' : '${(v / 1000).round()}k';
  static String _month(String key) => DateFormat('MMM', 'es').format(DateTime.parse('$key-01'));

  Widget _kpi(String value, String label, IconData icon) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: NetJobColors.primary, size: 20),
              const SizedBox(height: 6),
              Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              Text(label, style: const TextStyle(fontSize: 12, color: NetJobColors.muted)),
            ]),
          ),
        ),
      );

  Widget _locked(BuildContext context, String message) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.insights_rounded, size: 64, color: NetJobColors.primary),
            const SizedBox(height: 12),
            Text('Estadísticas detalladas', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('$message\n\nVerás tus ingresos mes a mes, los servicios que más te dejan, cuántas solicitudes conviertes y las visitas a tu perfil.',
                textAlign: TextAlign.center, style: const TextStyle(color: NetJobColors.subtle, height: 1.4)),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => context.pushReplacement('/pro/subscription'),
              icon: const Icon(Icons.workspace_premium_rounded),
              label: const Text('Ver planes'),
            ),
          ]),
        ),
      );
}

// ============================ Perfil destacado (promoción pagada) ============================

class PromotionsScreen extends StatelessWidget {
  const PromotionsScreen({super.key});

  Future<void> _buy(BuildContext context, Map option, Future<void> Function() reload) async {
    if (!await confirm(context, 'Destacar por ${option['label']}', 'Pagarás ${cop(option['price'])} para aparecer primero en las búsquedas de tu zona durante ${option['days']} días.', ok: 'Continuar al pago')) {
      return;
    }
    try {
      final co = await Api.instance.post('/promotions/checkout', {'optionId': option['id']});
      if (!context.mounted) return;
      final ok = await completeCheckout(context, co, what: 'tu perfil destacado');
      if (ok && context.mounted) toast(context, '¡Listo! Tu perfil ya está destacado.', error: false);
      await reload();
    } catch (e) {
      if (context.mounted) toast(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Destacar mi perfil')),
      body: AsyncView<Map>(
        load: () async => await Api.instance.get('/promotions') as Map,
        builder: (context, d, reload) {
          final options = (d['options'] as List).cast<Map>();
          final until = d['featuredUntil'];
          final included = (d['includedDays'] as num).toInt();
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(gradient: NetJobColors.heroGradient, borderRadius: BorderRadius.circular(24)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.campaign_rounded, color: NetJobColors.star, size: 34),
                  const SizedBox(height: 8),
                  Text(until != null ? 'Tu perfil está destacado' : 'Sé el primero que ven los clientes',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(
                    until != null
                        ? 'Apareces primero en tu zona, con la etiqueta "Destacado", hasta el ${fmtDate(until)}. Si compras más días, se suman.'
                        : 'Un perfil destacado aparece antes que todos los demás en las búsquedas de tu zona y lleva la etiqueta "Destacado".',
                    style: const TextStyle(color: NetJobColors.textSoft, height: 1.35),
                  ),
                ]),
              ),
              if (included > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(children: [
                    const Icon(Icons.card_giftcard_rounded, size: 18, color: NetJobColors.mint),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Tu plan ${d['planName']} incluye $included días destacados en cada renovación.', style: const TextStyle(color: NetJobColors.mint))),
                  ]),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(children: [
                    const Icon(Icons.info_outline, size: 18, color: NetJobColors.muted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('El plan Premium incluye 7 días destacados cada mes sin costo adicional.', style: const TextStyle(color: NetJobColors.subtle, fontSize: 13)),
                    ),
                    TextButton(onPressed: () => context.push('/pro/subscription'), child: const Text('Ver planes')),
                  ]),
                ),
              const SizedBox(height: 8),
              for (final o in options)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(o['label'], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                            Text('${o['days']} días · ${cop(((o['price'] as num) / (o['days'] as num)).round())} por día', style: const TextStyle(color: NetJobColors.subtle, fontSize: 13)),
                          ]),
                        ),
                        Text(cop(o['price']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: NetJobColors.primary)),
                        const SizedBox(width: 12),
                        FilledButton(
                          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                          onPressed: () => _buy(context, o, reload),
                          child: const Text('Destacar'),
                        ),
                      ]),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
            ]),
          );
        },
      ),
    );
  }
}
