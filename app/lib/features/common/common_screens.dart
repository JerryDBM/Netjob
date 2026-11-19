import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/support.dart';
import '../../core/theme.dart';
import '../../state/auth_state.dart';
import '../../widgets/photo_viewer.dart';
import '../../widgets/common.dart';
import '../../widgets/design.dart';

// ============================ Cuenta ============================

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final u = auth.user ?? {};
    return Scaffold(
      appBar: AppBar(title: const Text('Mi cuenta')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(12),
            leading: GestureDetector(
              onTap: () async {
                final f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 800);
                if (f == null) return;
                try {
                  await Api.instance.upload('/me/avatar', [f]);
                  await auth.reloadUser();
                } catch (e) {
                  if (context.mounted) toast(context, e);
                }
              },
              child: UserAvatar(url: u['avatarUrl'], name: u['name'] ?? '', radius: 28),
            ),
            title: Text(u['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${u['email']}\n${{'CLIENT': 'Cliente', 'PROFESSIONAL': 'Profesional', 'ADMIN': 'Administrador'}[u['role']]}'),
            isThreeLine: true,
            trailing: IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => context.push('/account/edit')),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(children: [
            if (auth.isPro) ...[
              _tile(context, Icons.badge_outlined, 'Perfil profesional y portafolio', '/pro/profile'),
              _tile(context, Icons.home_repair_service_outlined, 'Mis servicios', '/pro/services'),
              _tile(context, Icons.workspace_premium_outlined, 'Suscripción y beneficios del plan', '/pro/subscription'),
              _tile(context, Icons.campaign_outlined, 'Destacar mi perfil', '/pro/promotions'),
              _tile(context, Icons.verified_user_outlined, 'Verificación de identidad', '/pro/verification'),
              _tile(context, Icons.menu_book_outlined, 'Instructivos y reglas', '/pro/guides'),
            ],
            if (!auth.isPro && !auth.isAdmin) _tile(context, Icons.star_outline_rounded, 'Mis reseñas como cliente', '/clients/${auth.userId}/reviews'),
            _tile(context, Icons.receipt_long_outlined, auth.isPro ? 'Ingresos y pagos' : 'Historial de pagos', '/payments'),
            if (!auth.isAdmin) _tile(context, Icons.card_giftcard_outlined, 'Beneficios e invitados', '/benefits'),
            if (!auth.isAdmin) _tile(context, Icons.fact_check_outlined, 'Reclamaciones y garantía', '/claims'),
            _tile(context, Icons.notifications_none, 'Notificaciones', '/notifications'),
            _tile(context, Icons.lock_outline, 'Cambiar contraseña', '/account/password'),
          ]),
        ),
        const SizedBox(height: 12),
        Card(child: _SupportTile(isPro: auth.isPro, name: '${u['name'] ?? ''}')),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          icon: const Icon(Icons.logout),
          label: const Text('Cerrar sesión'),
          onPressed: () => auth.logout(),
        ),
      ]),
    );
  }

  Widget _tile(BuildContext context, IconData icon, String title, String route) => ListTile(
        leading: Icon(icon, color: NetJobColors.primary),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(route),
      );
}

/// Soporte por WhatsApp Business. Los profesionales con soporte prioritario (plan Premium)
/// lo ven indicado y su mensaje llega marcado para atenderlos primero.
class _SupportTile extends StatefulWidget {
  const _SupportTile({required this.isPro, required this.name});
  final bool isPro;
  final String name;
  @override
  State<_SupportTile> createState() => _SupportTileState();
}

class _SupportTileState extends State<_SupportTile> {
  bool _priority = false;

  @override
  void initState() {
    super.initState();
    if (widget.isPro) {
      Api.instance.get('/subscriptions/me').then((r) {
        if (mounted) setState(() => _priority = r['active']?['plan']?['prioritySupport'] == true);
      }).catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(Icons.support_agent, color: _priority ? NetJobColors.star : NetJobColors.accent),
        title: Text(_priority ? 'Soporte prioritario por WhatsApp' : 'Soporte por WhatsApp'),
        subtitle: Text(_priority
            ? 'Incluido en tu plan Premium: tu mensaje se atiende primero'
            : 'Dudas, urgencias y ayuda con tus servicios'),
        trailing: const Icon(Icons.open_in_new_rounded, size: 18),
        onTap: () => openSupport(priority: _priority, name: widget.name),
      );
}

class EditAccountScreen extends StatefulWidget {
  const EditAccountScreen({super.key});
  @override
  State<EditAccountScreen> createState() => _EditAccountScreenState();
}

class _EditAccountScreenState extends State<EditAccountScreen> {
  late final u = context.read<AuthState>().user!;
  late final _name = TextEditingController(text: u['name']);
  late final _phone = TextEditingController(text: u['phone']);
  late final _city = TextEditingController(text: u['city']);
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Datos de la cuenta')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nombre')),
        const SizedBox(height: 12),
        TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Celular')),
        const SizedBox(height: 12),
        TextField(controller: _city, decoration: const InputDecoration(labelText: 'Ciudad')),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _saving
              ? null
              : () async {
                  setState(() => _saving = true);
                  try {
                    await Api.instance.patch('/me', {
                      'name': _name.text.trim(),
                      'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
                      'city': _city.text.trim().isEmpty ? null : _city.text.trim(),
                    });
                    if (!context.mounted) return;
                    await context.read<AuthState>().reloadUser();
                    if (context.mounted) context.pop();
                  } catch (e) {
                    if (context.mounted) toast(context, e);
                  } finally {
                    if (mounted) setState(() => _saving = false);
                  }
                },
          child: const Text('Guardar'),
        ),
      ]),
    );
  }
}

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});
  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _new = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cambiar contraseña')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: _current, obscureText: true, decoration: const InputDecoration(labelText: 'Contraseña actual')),
        const SizedBox(height: 12),
        TextField(controller: _new, obscureText: true, decoration: const InputDecoration(labelText: 'Nueva contraseña', helperText: 'Mínimo 8 caracteres')),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () async {
            try {
              await Api.instance.post('/me/change-password', {'currentPassword': _current.text, 'newPassword': _new.text});
              if (!context.mounted) return;
              toast(context, 'Contraseña actualizada', error: false);
              context.pop();
            } catch (e) {
              if (context.mounted) toast(context, e);
            }
          },
          child: const Text('Actualizar'),
        ),
      ]),
    );
  }
}

// ============================ Notificaciones ============================

/// Ícono y color por tipo de aviso.
const _notifStyle = <String, (IconData, Color)>{
  'REQUEST_NEW': (Icons.inbox_rounded, Color(0xFF1B4332)),
  'REQUEST_STATUS': (Icons.sync_alt_rounded, Color(0xFFE4602B)),
  'REQUEST_QUOTE': (Icons.request_quote_rounded, Color(0xFFE4602B)),
  'MESSAGE_NEW': (Icons.chat_bubble_rounded, Color(0xFF3F7CAC)),
  'PAYMENT': (Icons.payments_rounded, Color(0xFF2E8B57)),
  'REVIEW_NEW': (Icons.star_rounded, Color(0xFFD19A1E)),
  'SUBSCRIPTION': (Icons.workspace_premium_rounded, Color(0xFF3D7A5C)),
  'REMINDER': (Icons.alarm_rounded, Color(0xFFC65D3B)),
  'TRIP': (Icons.navigation_rounded, Color(0xFF2E8B57)),
  'CLAIM': (Icons.fact_check_rounded, Color(0xFFE4602B)),
  'VERIFICATION': (Icons.verified_user_rounded, Color(0xFF3F7CAC)),
  'REWARD': (Icons.card_giftcard_rounded, Color(0xFFD19A1E)),
  'ACCOUNT': (Icons.manage_accounts_rounded, Color(0xFFC65D3B)),
};

/// A dónde lleva un aviso al tocarlo (null = no navega).
String? _notifRoute(Map n, {required bool isPro}) {
  final data = (n['data'] as Map?) ?? const {};
  final requestId = data['requestId'];
  switch (n['type']) {
    case 'TRIP':
      // "Va en camino" abre directo el mapa de seguimiento
      return requestId == null ? null : (data['track'] == true ? '/requests/$requestId/track' : '/requests/$requestId');
    case 'VERIFICATION':
      return isPro ? '/pro/verification' : null;
    case 'REWARD':
      return isPro ? '/pro/subscription' : '/benefits';
    case 'SUBSCRIPTION':
      return isPro ? '/pro/subscription' : null;
  }
  return requestId == null ? null : '/requests/$requestId';
}

const _notifFilters = <String, List<String>>{
  'all': [],
  'requests': ['REQUEST_NEW', 'REQUEST_STATUS', 'REQUEST_QUOTE', 'TRIP', 'CLAIM'],
  'payments': ['PAYMENT', 'SUBSCRIPTION', 'REWARD'],
  'messages': ['MESSAGE_NEW'],
  'reviews': ['REVIEW_NEW', 'REMINDER'],
};

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    return Scaffold(
      body: SafeArea(
        child: AsyncView<Map>(
          load: () async {
            final r = await Api.instance.get('/notifications') as Map;
            // Se marcan como leídas, pero se muestran con el punto azul en esta visita
            await Api.instance.post('/notifications/read');
            if (context.mounted) context.read<AuthState>().markNotificationsRead();
            return r;
          },
          builder: (context, data, reload) {
            final all = data['items'] as List;
            final unread = (data['unread'] as num?)?.toInt() ?? 0;
            final types = _notifFilters[_filter]!;
            final items = types.isEmpty ? all : all.where((n) => types.contains(n['type'])).toList();
            // Destacado: el aviso más reciente (últimas 24 h) que pide una acción
            final featured = all.cast<Map>().where((n) =>
                DateTime.now().difference(DateTime.tryParse(n['createdAt'] ?? '') ?? DateTime(2000)).inHours < 24 &&
                (n['data'] as Map?)?['requestId'] != null &&
                ['REQUEST_QUOTE', 'PAYMENT', 'REQUEST_NEW', 'REQUEST_STATUS', 'TRIP', 'CLAIM'].contains(n['type'])).firstOrNull;
            final rows = <Widget>[];
            String? group;
            for (final n in items) {
              if (identical(n, featured)) continue;
              final g = dayGroup(n['createdAt']);
              if (g != group) {
                group = g;
                rows.add(GroupLabel(g));
              }
              rows.add(_NotificationRow(n: n));
            }
            return RefreshIndicator(
              onRefresh: reload,
              child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
                ScreenHeader(
                  title: 'Avisos',
                  subtitle: unread == 0 ? 'Estás al día' : '$unread sin leer',
                  avatarName: auth.user?['name'] ?? '',
                  avatarUrl: auth.user?['avatarUrl'],
                ),
                PillTabs(
                  selected: _filter,
                  onSelected: (v) => setState(() => _filter = v),
                  items: const [
                    ('all', 'Todos', Icons.mail_outline_rounded),
                    ('requests', 'Solicitudes', Icons.assignment_outlined),
                    ('payments', 'Pagos', Icons.receipt_long_outlined),
                    ('messages', 'Mensajes', Icons.chat_bubble_outline_rounded),
                    ('reviews', 'Reseñas', Icons.star_outline_rounded),
                  ],
                ),
                if (featured != null && (types.isEmpty || types.contains(featured['type'])))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                    child: HighlightCard(
                      title: featured['title'],
                      subtitle: '${featured['body']}',
                      icon: _notifStyle[featured['type']]?.$1 ?? Icons.notifications,
                      color: _notifStyle[featured['type']]?.$2 ?? NetJobColors.primary,
                      onTap: () => context.push(_notifRoute(featured, isPro: auth.isPro) ?? '/requests/${(featured['data'] as Map)['requestId']}'),
                    ),
                  ),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 60),
                    child: EmptyState(icon: Icons.mark_email_read_outlined, title: 'No hay avisos aquí'),
                  ),
                if (rows.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    decoration: BoxDecoration(color: NetJobColors.card, borderRadius: BorderRadius.circular(24), border: Border.all(color: NetJobColors.border)),
                    clipBehavior: Clip.antiAlias,
                    child: Column(children: rows),
                  ),
              ]),
            );
          },
        ),
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.n});
  final Map n;

  @override
  Widget build(BuildContext context) {
    final style = _notifStyle[n['type']] ?? (Icons.notifications, NetJobColors.primary);
    final route = _notifRoute(n, isPro: context.read<AuthState>().isPro);
    final unread = n['readAt'] == null;
    return InkWell(
      onTap: route == null ? null : () => context.push(route),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE6E9DE)))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          IconBubble(icon: style.$1, color: style.$2),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (unread) ...[
                  Container(width: 9, height: 9, decoration: const BoxDecoration(color: NetJobColors.primary, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(n['title'],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 16, fontWeight: unread ? FontWeight.w900 : FontWeight.w600, color: NetJobColors.ink)),
                ),
                const SizedBox(width: 8),
                Text(timeAgo(n['createdAt']), style: const TextStyle(fontSize: 13, color: NetJobColors.muted)),
              ]),
              const SizedBox(height: 4),
              Text(n['body'], maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, color: NetJobColors.muted, height: 1.3)),
            ]),
          ),
          if (route != null) ...[
            const SizedBox(width: 6),
            const Padding(padding: EdgeInsets.only(top: 14), child: Icon(Icons.chevron_right_rounded, color: Color(0xFFB3B9B1))),
          ],
        ]),
      ),
    );
  }
}

// ============================ Pagos ============================

/// Historial de pagos estilo "recibos": cada pago con su contraparte y monto.
class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});
  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    return Scaffold(
      appBar: AppBar(),
      body: AsyncView<List>(
        load: () async => await Api.instance.get('/payments') as List,
        builder: (context, all, reload) {
          // El profesional ve lo que recibe (sin la comisión que paga el cliente)
          bool earned(Map p) => p['kind'] == 'SERVICE' || p['kind'] == 'DIAGNOSTIC';
          int amountOf(Map p) => (auth.isPro && earned(p) ? p['serviceAmount'] : p['totalAmount']) as int;
          // No cuenta lo que se devolvió al cliente tras una reclamación
          final approved = all.cast<Map>().where((p) => p['status'] == 'APPROVED' && p['payoutStatus'] != 'REFUNDED' && (auth.isPro ? earned(p) : true));
          final total = approved.fold<int>(0, (s, p) => s + amountOf(p));
          final items = switch (_filter) {
            'services' => all.where((p) => p['kind'] == 'SERVICE').toList(),
            'visits' => all.where((p) => p['kind'] == 'DIAGNOSTIC').toList(),
            'subscription' => all.where((p) => p['kind'] == 'SUBSCRIPTION' || p['kind'] == 'PROMOTION').toList(),
            _ => all,
          };
          final featured = items.cast<Map>().where((p) => p['status'] == 'APPROVED' && p['request'] != null).firstOrNull;
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
              ScreenHeader(
                title: auth.isPro ? 'Ingresos' : 'Mis pagos',
                subtitle: auth.isPro ? 'Recibido en total: ${cop(total)}' : 'Pagado en total: ${cop(total)}',
                avatarName: auth.user?['name'] ?? '',
                avatarUrl: auth.user?['avatarUrl'],
              ),
              PillTabs(
                selected: _filter,
                onSelected: (v) => setState(() => _filter = v),
                items: [
                  ('all', 'Todos', Icons.receipt_long_outlined),
                  ('services', 'Servicios', Icons.home_repair_service_outlined),
                  ('visits', 'Visitas', Icons.directions_walk_rounded),
                  if (auth.isPro) ('subscription', 'Plan y destacados', Icons.workspace_premium_outlined),
                ],
              ),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: EmptyState(icon: Icons.receipt_long_outlined, title: 'Aún no hay pagos aquí'),
                )
              else
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  decoration: BoxDecoration(color: NetJobColors.card, borderRadius: BorderRadius.circular(24), border: Border.all(color: NetJobColors.border)),
                  clipBehavior: Clip.antiAlias,
                  child: Column(children: [
                    for (final p in items)
                      identical(p, featured)
                          ? _ReceiptRow(p: p, amount: amountOf(p), isPro: auth.isPro, featured: true)
                          : _ReceiptRow(p: p, amount: amountOf(p), isPro: auth.isPro),
                  ]),
                ),
            ]),
          );
        },
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({required this.p, required this.amount, required this.isPro, this.featured = false});
  final Map p;
  final int amount;
  final bool isPro;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    final kind = p['kind'] as String;
    final req = p['request'] as Map?;
    final status = p['status'] as String;
    final other = req == null ? null : (isPro ? req['client'] : req['professional']?['user']) as Map?;
    final service = req?['service']?['title'] ?? 'Servicio';
    final toNetJob = kind == 'SUBSCRIPTION' || kind == 'PROMOTION';
    final refunded = p['payoutStatus'] == 'REFUNDED';
    final title = toNetJob ? 'NetJob' : (other?['name'] ?? service);
    final subtitle = switch (kind) {
      'SUBSCRIPTION' => 'Plan ${p['subscription']?['plan']?['name'] ?? ''}${(p['discountAmount'] ?? 0) > 0 ? ' · con descuento' : ''}',
      'PROMOTION' => 'Perfil destacado · ${p['promoDays']} días',
      'SERVICE' when p['loyaltyApplied'] == true && !isPro => '$service · tarifa reducida',
      'DIAGNOSTIC' => 'Visita de diagnóstico · $service',
      _ => service,
    };
    final photos = (req?['photos'] as List?) ?? const [];
    final leading = toNetJob
        ? IconBubble(icon: kind == 'PROMOTION' ? Icons.campaign_rounded : Icons.workspace_premium_rounded, color: const Color(0xFF3D7A5C), size: 52)
        : other?['avatarUrl'] != null
            ? UserAvatar(url: other!['avatarUrl'], name: other['name'] ?? '', radius: 26)
            : IconBubble(
                icon: categoryIcon(req?['service']?['category']?['icon']),
                color: kind == 'DIAGNOSTIC' ? const Color(0xFF3F7CAC) : NetJobColors.primary,
                size: 52,
              );

    final content = Padding(
      padding: EdgeInsets.fromLTRB(16, featured ? 18 : 14, 16, featured ? 18 : 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          leading,
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: featured ? 19 : 16.5, fontWeight: FontWeight.w700, color: NetJobColors.ink)),
              const SizedBox(height: 3),
              Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: featured ? 15.5 : 14.5, color: const Color(0xFF3C4A42))),
            ]),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${isPro && !toNetJob ? '+' : ''}${cop(amount)}',
                style: TextStyle(
                  fontSize: featured ? 21 : 17,
                  fontWeight: FontWeight.w800,
                  color: status == 'APPROVED' && !refunded ? NetJobColors.ink : NetJobColors.muted,
                  decoration: (status == 'APPROVED' && !refunded) || status == 'PENDING' ? null : TextDecoration.lineThrough,
                )),
            const SizedBox(height: 3),
            Text(
                status != 'APPROVED'
                    ? paymentStatusLabel[status] ?? status
                    : refunded
                        ? (isPro ? 'Devuelto al cliente' : 'Devuelto')
                        : p['payoutStatus'] == 'HELD'
                            ? 'Retenido'
                            : timeAgo(p['createdAt']),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: p['payoutStatus'] == 'HELD' ? FontWeight.w700 : null,
                  color: status != 'APPROVED'
                      ? const Color(0xFFC77A12)
                      : p['payoutStatus'] == 'HELD'
                          ? NetJobColors.primary
                          : NetJobColors.muted,
                )),
          ]),
        ]),
        if (featured && photos.isNotEmpty) ...[
          const SizedBox(height: 14),
          Row(children: [
            const SizedBox(width: 66),
            for (var k = 0; k < photos.length && k < 3; k++)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: PhotoThumb(
                  urls: [for (final x in photos) x as String],
                  index: k,
                  heroPrefix: 'pago-${p['id']}',
                  width: 84,
                  height: 84,
                  radius: 14,
                ),
              ),
          ]),
        ],
      ]),
    );

    // Un pago aprobado abre su comprobante; los demás, la solicitud
    final onTap = status == 'APPROVED'
        ? () => context.push('/payments/${p['id']}/receipt')
        : req == null
            ? null
            : () => context.push('/requests/${req['id']}');
    if (featured) {
      return Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: NetJobColors.primary, width: 3.5),
          boxShadow: const [BoxShadow(color: Color(0x141B4332), blurRadius: 20, offset: Offset(0, 8))],
          color: NetJobColors.card,
        ),
        child: Material(color: Colors.transparent, child: InkWell(borderRadius: BorderRadius.circular(20), onTap: onTap, child: content)),
      );
    }
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE6E9DE)))),
        child: content,
      ),
    );
  }
}
