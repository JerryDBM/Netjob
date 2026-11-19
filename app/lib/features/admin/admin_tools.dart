import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

// ---------------- Categorías de servicios ----------------

/// Categorías que ven los clientes al buscar y los profesionales al publicar servicios.
class AdminCategoriesTab extends StatelessWidget {
  const AdminCategoriesTab({super.key});

  static String slugify(String s) {
    const from = 'áéíóúüñÁÉÍÓÚÜÑ';
    const to = 'aeiouunAEIOUUN';
    var out = s.trim();
    for (var i = 0; i < from.length; i++) {
      out = out.replaceAll(from[i], to[i]);
    }
    return out.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  }

  Future<void> _edit(BuildContext context, Map? c, int nextOrder, Future<void> Function() reload) async {
    final body = await showDialog<Map>(context: context, builder: (_) => _CategoryDialog(category: c, nextOrder: nextOrder));
    if (body == null) return;
    try {
      if (c == null) {
        await Api.instance.post('/admin/categories', body);
      } else {
        await Api.instance.patch('/admin/categories/${c['id']}', body);
      }
      if (context.mounted) toast(context, c == null ? 'Categoría creada' : 'Categoría actualizada', error: false);
      await reload();
    } catch (e) {
      if (context.mounted) toast(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AsyncView<List>(
      load: () async => await Api.instance.get('/admin/categories') as List,
      builder: (context, items, reload) {
        final cats = items.cast<Map>();
        final nextOrder = cats.fold<int>(0, (m, c) => (c['sortOrder'] as num).toInt() > m ? (c['sortOrder'] as num).toInt() : m) + 1;
        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _edit(context, null, nextOrder, reload),
            icon: const Icon(Icons.add),
            label: const Text('Nueva categoría'),
          ),
          body: RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
              const Text(
                'Las categorías inactivas no aparecen en la búsqueda ni al publicar servicios. Los servicios que ya existen conservan su categoría.',
                style: TextStyle(color: NetJobColors.muted, fontSize: 12.5),
              ),
              const SizedBox(height: 10),
              if (cats.isEmpty) const EmptyState(icon: Icons.category_outlined, title: 'Aún no hay categorías'),
              for (final c in cats)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: NetJobColors.cardHigh,
                      child: Icon(categoryIcon(c['icon']), color: c['active'] == true ? NetJobColors.primary : NetJobColors.muted),
                    ),
                    title: Text(c['name'], style: TextStyle(fontWeight: FontWeight.w700, color: c['active'] == true ? null : NetJobColors.muted)),
                    subtitle: Text('${c['slug']} · orden ${c['sortOrder']}${c['active'] == true ? '' : ' · inactiva'}',
                        style: const TextStyle(fontSize: 12.5, color: NetJobColors.subtle)),
                    onTap: () => _edit(context, c, nextOrder, reload),
                    trailing: Switch(
                      value: c['active'] == true,
                      onChanged: (v) async {
                        try {
                          await Api.instance.patch('/admin/categories/${c['id']}', {'active': v});
                          await reload();
                        } catch (e) {
                          if (context.mounted) toast(context, e);
                        }
                      },
                    ),
                  ),
                ),
            ]),
          ),
        );
      },
    );
  }
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({this.category, required this.nextOrder});
  final Map? category;
  final int nextOrder;
  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final _name = TextEditingController(text: widget.category?['name']);
  late final _slug = TextEditingController(text: widget.category?['slug']);
  late final _order = TextEditingController(text: '${widget.category?['sortOrder'] ?? widget.nextOrder}');
  late String _icon = widget.category?['icon'] ?? 'build';
  late bool _slugTouched = widget.category != null;

  bool get _valid => _name.text.trim().length >= 2 && RegExp(r'^[a-z0-9-]+$').hasMatch(_slug.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.category == null ? 'Nueva categoría' : 'Editar categoría'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: _name,
            autofocus: widget.category == null,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Ej. Jardinería'),
            onChanged: (v) => setState(() {
              if (!_slugTouched) _slug.text = AdminCategoriesTab.slugify(v);
            }),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _slug,
            decoration: const InputDecoration(labelText: 'Identificador', helperText: 'Minúsculas, números y guiones'),
            onChanged: (_) => setState(() => _slugTouched = true),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _order,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Orden en la lista'),
          ),
          const SizedBox(height: 14),
          const Text('Ícono', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in categoryIcons.entries)
              ChoiceChip(
                label: Icon(e.value, size: 20),
                selected: _icon == e.key,
                onSelected: (_) => setState(() => _icon = e.key),
              ),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: !_valid
              ? null
              : () => Navigator.pop(context, {
                    'name': _name.text.trim(),
                    'slug': _slug.text.trim(),
                    'icon': _icon,
                    'sortOrder': int.tryParse(_order.text) ?? widget.nextOrder,
                  }),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

// ---------------- Pagos y transacciones ----------------

class AdminPaymentsTab extends StatefulWidget {
  const AdminPaymentsTab({super.key});
  @override
  State<AdminPaymentsTab> createState() => _AdminPaymentsTabState();
}

class _AdminPaymentsTabState extends State<AdminPaymentsTab> {
  String? _kind;
  String? _status = 'APPROVED';
  final _q = TextEditingController();
  int _version = 0;

  static const _payoutLabel = {'HELD': 'Retenido', 'RELEASED': 'Liberado al profesional', 'REFUNDED': 'Devuelto al cliente'};

  Widget _chips<T>(List<(T, String)> options, T selected, ValueChanged<T> onSelect) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final o in options)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(label: Text(o.$2), selected: selected == o.$1, onSelected: (_) => onSelect(o.$1)),
            ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(children: [
          TextField(
            controller: _q,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(hintText: 'Referencia, nombre o correo de quien pagó', prefixIcon: Icon(Icons.search), isDense: true),
            onSubmitted: (_) => setState(() => _version++),
          ),
          const SizedBox(height: 8),
          _chips<String?>([(null, 'Todos'), ...paymentKindLabel.entries.map((e) => (e.key, e.value))], _kind, (v) => setState(() => _kind = v)),
          const SizedBox(height: 4),
          _chips<String?>([(null, 'Cualquier estado'), ...paymentStatusLabel.entries.map((e) => (e.key, e.value))], _status, (v) => setState(() => _status = v)),
        ]),
      ),
      Expanded(
        child: AsyncView<Map>(
          key: ValueKey('$_kind-$_status-$_version'),
          load: () async => await Api.instance.get('/admin/payments', {'kind': _kind, 'status': _status, 'q': _q.text.trim()}) as Map,
          builder: (context, data, reload) {
            final items = (data['items'] as List).cast<Map>();
            final t = data['totals'] as Map;
            Widget kpi(String label, String value, {Color? color}) => Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(label, style: const TextStyle(color: NetJobColors.muted, fontSize: 11.5)),
                        const SizedBox(height: 2),
                        FittedBox(child: Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color))),
                      ]),
                    ),
                  ),
                );
            return RefreshIndicator(
              onRefresh: reload,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Row(children: [
                  kpi('Recaudado (aprobados)', cop(t['collected'])),
                  kpi('Comisiones NetJob', cop(t['commissions']), color: NetJobColors.mint),
                ]),
                Row(children: [
                  kpi('Pagos aprobados', '${t['approved']}'),
                  kpi('Retenido a profesionales', cop(t['held']), color: (t['held'] as num) > 0 ? NetJobColors.warning : null),
                ]),
                const SizedBox(height: 6),
                Text('${items.length == 300 ? 'Últimos 300' : items.length} movimientos', style: const TextStyle(color: NetJobColors.muted, fontSize: 12.5)),
                const SizedBox(height: 6),
                if (items.isEmpty) const EmptyState(icon: Icons.receipt_long_outlined, title: 'No hay pagos con estos filtros'),
                for (final p in items) _paymentCard(p),
              ]),
            );
          },
        ),
      ),
    ]);
  }

  Widget _paymentCard(Map p) {
    final req = p['request'] as Map?;
    final approved = p['status'] == 'APPROVED';
    final payout = _payoutLabel[p['payoutStatus']];
    final detail = [
      if (req != null) '${req['service']['title']} · ${req['professional']['user']['name']}',
      'Pagó ${p['payer']['name']} (${p['payer']['email']})',
      if ((p['commissionAmount'] as num) > 0) 'Valor ${cop(p['serviceAmount'])} + tarifa ${pct(p['commissionRate'])} ${cop(p['commissionAmount'])}${p['loyaltyApplied'] == true ? ' (reducida)' : ''}',
      if ((p['discountAmount'] as num? ?? 0) > 0) 'Descuento ${cop(p['discountAmount'])}',
      if (approved && payout != null) payout,
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(paymentKindLabel[p['kind']] ?? p['kind'], style: const TextStyle(fontWeight: FontWeight.w800))),
            Text(cop(p['totalAmount']), style: TextStyle(fontWeight: FontWeight.w800, color: approved ? NetJobColors.ink : NetJobColors.muted)),
          ]),
          const SizedBox(height: 2),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: (approved ? NetJobColors.mint : p['status'] == 'PENDING' ? NetJobColors.warning : NetJobColors.danger).withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(paymentStatusLabel[p['status']] ?? p['status'],
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: approved ? NetJobColors.mint : p['status'] == 'PENDING' ? NetJobColors.warning : NetJobColors.danger,
                  )),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text('${fmtDateTime(p['createdAt'])}${p['paymentMethod'] != null ? ' · ${p['paymentMethod']}' : ''}', style: const TextStyle(color: NetJobColors.muted, fontSize: 12))),
          ]),
          const SizedBox(height: 6),
          for (final d in detail) Text(d, style: const TextStyle(color: NetJobColors.subtle, fontSize: 12.5)),
          const SizedBox(height: 2),
          SelectableText(p['reference'], style: const TextStyle(color: NetJobColors.muted, fontSize: 11.5)),
        ]),
      ),
    );
  }
}

// ---------------- Configuración general ----------------

/// Parámetros del negocio que el administrador puede cambiar sin redesplegar la API.
class AdminSettingsTab extends StatefulWidget {
  const AdminSettingsTab({super.key});
  @override
  State<AdminSettingsTab> createState() => _AdminSettingsTabState();
}

/// (clave, etiqueta, ayuda, es porcentaje, admite decimales)
const _fields = [
  ('Cobros', [
    ('commissionRate', 'Comisión NetJob (%)', 'Se suma al valor del servicio y la paga el cliente', true, true),
    ('loyaltyCommissionRate', 'Comisión reducida (%)', 'Clientes frecuentes y referidos', true, true),
    ('diagnosticFee', 'Visita de diagnóstico inicial (\$)', 'Valor con el que empiezan los perfiles nuevos', false, false),
    ('maxDiagnosticFee', 'Tope de la visita de diagnóstico (\$)', 'Máximo que un profesional puede cobrar', false, false),
    ('subscriptionDays', 'Duración de la suscripción (días)', 'Lo que suma cada pago o renovación', false, false),
  ]),
  ('Búsqueda y perfiles', [
    ('searchRadiusKm', 'Radio de búsqueda (km)', 'Distancia máxima entre el cliente y el profesional', false, false),
    ('minPortfolio', 'Fotos mínimas de portafolio', 'Para que el perfil quede completo', false, false),
    ('trainingPassScore', 'Respuestas correctas para aprobar (de 25)', 'Capacitación inicial obligatoria', false, false),
  ]),
  ('Calidad y fidelización', [
    ('warrantyDays', 'Garantía de la mano de obra (días)', 'Desde que el servicio se finaliza', false, false),
    ('reviewThreshold', 'Calificación que activa la revisión', 'Con al menos 3 reseñas por debajo de este promedio', false, true),
    ('loyaltyEvery', 'Servicios para ganar la tarifa reducida', 'Cliente frecuente: cada cuántos servicios finalizados', false, false),
    ('loyaltyMinRating', 'Calificación mínima del cliente frecuente', 'Debe ser mayor a este valor', false, true),
  ]),
];

class _AdminSettingsTabState extends State<AdminSettingsTab> {
  final _ctrl = <String, TextEditingController>{};
  bool _saving = false;
  late Future<void> _loading = _load();

  String _show(num v, bool percent) {
    final n = percent ? v * 100 : v;
    return n == n.roundToDouble() ? '${n.round()}' : n.toString().replaceAll('.', ',');
  }

  Future<void> _load() async {
    final s = await Api.instance.get('/admin/settings') as Map;
    for (final g in _fields) {
      for (final f in g.$2) {
        (_ctrl[f.$1] ??= TextEditingController()).text = _show(s[f.$1] as num, f.$4);
      }
    }
  }

  Future<void> _save() async {
    final body = <String, num>{};
    for (final g in _fields) {
      for (final f in g.$2) {
        final raw = _ctrl[f.$1]!.text.trim().replaceAll('.', '').replaceAll(',', '.');
        final n = num.tryParse(f.$5 ? raw : raw.split('.').first);
        if (n == null) {
          toast(context, 'Revisa el campo "${f.$2}"');
          return;
        }
        body[f.$1] = f.$4 ? (n / 100) : (f.$5 ? n : n.toInt());
      }
    }
    setState(() => _saving = true);
    try {
      await Api.instance.put('/admin/settings', body);
      await _load();
      if (mounted) toast(context, 'Configuración guardada. Ya aplica para toda la plataforma.', error: false);
    } catch (e) {
      if (mounted) toast(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _loading,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snap.hasError) {
          return EmptyState(
            icon: Icons.cloud_off,
            title: 'No se pudo cargar la configuración',
            message: snap.error.toString(),
            action: FilledButton(onPressed: () => setState(() => _loading = _load()), child: const Text('Reintentar')),
          );
        }
        return ListView(padding: const EdgeInsets.all(16), children: [
          const Text(
            'Los cambios aplican de inmediato a los nuevos cobros, búsquedas y solicitudes. Lo que ya se pagó o cotizó no cambia.',
            style: TextStyle(color: NetJobColors.muted, fontSize: 12.5),
          ),
          for (final g in _fields) ...[
            SectionTitle(g.$1),
            for (final f in g.$2)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TextField(
                  controller: _ctrl[f.$1],
                  keyboardType: TextInputType.numberWithOptions(decimal: f.$5),
                  decoration: InputDecoration(labelText: f.$2, helperText: f.$3, isDense: true),
                ),
              ),
          ],
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
            label: const Text('Guardar configuración'),
          ),
          const SizedBox(height: 24),
        ]);
      },
    );
  }
}
