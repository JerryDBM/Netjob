import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../state/auth_state.dart';
import '../../state/location_state.dart';
import '../../widgets/photo_viewer.dart';
import '../../widgets/common.dart';
import '../../widgets/maps.dart';
import '../pro/plan_screens.dart';
import '../reviews/reviews_screens.dart';

// ============================ Inicio del cliente ============================

class ClientHomeScreen extends StatefulWidget {
  const ClientHomeScreen({super.key});
  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final loc = context.read<LocationState>();
      if (loc.status == LocationStatus.idle) loc.start();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final name = (auth.user?['name'] ?? '').toString().split(' ').first;
    final loc = context.watch<LocationState>();
    return Scaffold(
      body: SafeArea(
        child: AsyncView<List<dynamic>>(
          // Se recarga cuando la ubicación cambia (~1 km): si cambias de ciudad, cambian los profesionales
          key: ValueKey('${loc.key}-${auth.dataVersion}'),
          load: () => Future.wait([
            Api.instance.get('/categories'),
            Api.instance.get('/requests', {'status': 'PENDING,ACCEPTED,IN_PROGRESS'}),
            loc.hasLocation
                ? Api.instance.get('/professionals', {'lat': loc.lat, 'lng': loc.lng, 'pageSize': 50})
                : Future.value({'items': [], 'radiusKm': 12, 'total': 0}),
            // Recomendados según lo que el cliente ya contrató (si falla, la pantalla sigue)
            loc.hasLocation
                ? Api.instance.get('/professionals/recommended', {'lat': loc.lat, 'lng': loc.lng}).catchError((_) => {'items': [], 'basedOn': []})
                : Future.value({'items': [], 'basedOn': []}),
          ]),
          builder: (context, data, reload) {
            final categories = data[0] as List;
            final active = data[1] as List;
            final nearby = data[2]['items'] as List;
            final radius = (data[2]['radiusKm'] as num?)?.toDouble() ?? 12;
            final recommended = data[3]['items'] as List;
            final basedOn = (data[3]['basedOn'] as List).join(', ');
            return RefreshIndicator(
              onRefresh: reload,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Text('Hola${name.isEmpty ? '' : ', $name'}', style: TextStyle(color: NetJobColors.subtle)),
                const SizedBox(height: 4),
                Text('¿Qué servicio necesitas hoy?',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const LocationBar(),
                const SizedBox(height: 10),
                TextField(
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    hintText: 'Ej: fuga de agua, instalar lámpara…',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onSubmitted: (q) => context.push(Uri(path: '/search', queryParameters: {'q': q}).toString()),
                ),
                if (active.isNotEmpty) ...[
                  SectionTitle('Tus servicios (${active.length})',
                      trailing: TextButton(onPressed: () => context.go('/requests'), child: const Text('Ver todos'))),
                  for (final r in active.take(4))
                    _ActiveRequestCard(r: r, onReturn: reload),
                ],
                if (recommended.isNotEmpty) ...[
                  const SectionTitle('Recomendados para ti'),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('Porque ya contrataste $basedOn', style: TextStyle(fontSize: 12.5, color: NetJobColors.subtle)),
                  ),
                  for (final p in recommended.take(3)) ...[
                    ProCard(pro: p, note: p['hiredBefore'] == true ? 'Ya lo contrataste' : null),
                    const SizedBox(height: 10),
                  ],
                ],
                SectionTitle('Profesionales a menos de ${radius.round()} km'),
                if (!loc.hasLocation)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(children: [
                        const Icon(Icons.location_searching, size: 40, color: NetJobColors.primary),
                        const SizedBox(height: 8),
                        Text(
                          loc.status == LocationStatus.loading
                              ? 'Buscando tu ubicación…'
                              : 'Necesitamos tu ubicación para mostrarte profesionales cercanos.',
                          textAlign: TextAlign.center,
                        ),
                        if (loc.message != null) ...[
                          const SizedBox(height: 6),
                          Text(loc.message!, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: NetJobColors.subtle)),
                        ],
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: () => showLocationSheet(context),
                          icon: const Icon(Icons.place_outlined),
                          label: const Text('Elegir ubicación'),
                        ),
                      ]),
                    ),
                  )
                else ...[
                  NearbyMap(
                    lat: loc.lat!,
                    lng: loc.lng!,
                    radiusKm: radius,
                    pros: nearby,
                    onProTap: (p) => context.push('/pro/${p['id']}'),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    nearby.isEmpty
                        ? 'Aún no hay profesionales disponibles cerca de ${loc.label}.'
                        : '${nearby.length} ${nearby.length == 1 ? 'profesional disponible' : 'profesionales disponibles'} cerca de ${loc.label}',
                    style: TextStyle(fontSize: 12, color: NetJobColors.subtle),
                  ),
                ],
                const SectionTitle('Categorías'),
                GridView.count(
                  crossAxisCount: MediaQuery.of(context).size.width > 700 ? 6 : 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.05,
                  children: [
                    for (final c in categories)
                      Card(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => context.push(Uri(
                            path: '/search',
                            queryParameters: {'categoryId': c['id'], 'title': c['name']},
                          ).toString()),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              CircleAvatar(
                                backgroundColor: NetJobColors.primary.withValues(alpha: 0.1),
                                child: Icon(categoryIcon(c['icon']), color: NetJobColors.primary),
                              ),
                              const SizedBox(height: 8),
                              Text(c['name'],
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            ]),
                          ),
                        ),
                      ),
                  ],
                ),
                if (nearby.isNotEmpty) ...[
                  SectionTitle('Cerca de ti',
                      trailing: TextButton(onPressed: () => context.push('/search'), child: const Text('Ver todos'))),
                  for (final p in nearby.take(10)) ...[ProCard(pro: p), const SizedBox(height: 10)],
                ],
              ]),
            );
          },
        ),
      ),
    );
  }
}

/// Servicio en espera o contratado, con la etapa en la que va.
class _ActiveRequestCard extends StatelessWidget {
  const _ActiveRequestCard({required this.r, required this.onReturn});
  final Map r;
  final Future<void> Function() onReturn;

  @override
  Widget build(BuildContext context) {
    final stage = requestStage(r);
    final needsAction = stage == 'PAY_DIAGNOSTIC' || stage == 'PAY_SERVICE';
    final pro = r['professional']['user'];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: needsAction ? const Color(0xFFFBEBDA) : null,
      child: ListTile(
        leading: UserAvatar(url: pro['avatarUrl'], name: pro['name']),
        title: Text(r['service']['title'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${pro['name']} · ${fmtDateTime(r['scheduledAt'])}\n${stageLabel(stage, isPro: false)}', maxLines: 2),
        isThreeLine: true,
        trailing: needsAction
            ? const Icon(Icons.payments_outlined, color: Color(0xFFC77A12))
            : StatusChip(r['status']),
        onTap: () async {
          await context.push('/requests/${r['id']}');
          onReturn();
        },
      ),
    );
  }
}

/// Tarjeta resumida de un profesional para comparar en resultados.
class ProCard extends StatelessWidget {
  const ProCard({super.key, required this.pro, this.note});
  final Map pro;

  /// Texto destacado bajo el nombre (ej. "Ya lo contrataste").
  final String? note;

  @override
  Widget build(BuildContext context) {
    final cats = (pro['categories'] as List).map((c) => c['name']).join(' · ');
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/pro/${pro['id']}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            UserAvatar(url: pro['avatarUrl'], name: pro['name'], radius: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(pro['name'],
                        overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                  if (pro['verified'] == true) ...[
                    const SizedBox(width: 4),
                    const Tooltip(message: 'Identidad y antecedentes verificados', child: Icon(Icons.verified, size: 18, color: NetJobColors.primary)),
                  ],
                ]),
                if (pro['planBadge'] != null || pro['featured'] == true || pro['recommended'] == true || note != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 2),
                    child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      PlanBadge(pro['planBadge'], compact: true),
                      if (pro['featured'] == true) const _Tag('Destacado', Color(0xFFC77A12), Icons.campaign_rounded),
                      if (pro['recommended'] == true) const _Tag('Recomendado', NetJobColors.mint, Icons.rocket_launch_rounded),
                      if (note != null) _Tag(note!, NetJobColors.sky, Icons.replay_rounded),
                    ]),
                  ),
                if (pro['headline'] != null)
                  Text(pro['headline'], maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: NetJobColors.subtle)),
                const SizedBox(height: 4),
                Text(cats, style: TextStyle(fontSize: 12, color: NetJobColors.muted)),
                const SizedBox(height: 8),
                Wrap(spacing: 12, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  RatingStars(rating: pro['ratingAvg'], count: pro['ratingCount']),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.place_outlined, size: 15, color: NetJobColors.muted),
                    Text(
                      pro['distanceKm'] != null ? '${pro['distanceKm']} km' : (pro['city'] ?? '—'),
                      style: TextStyle(fontSize: 12, color: NetJobColors.subtle),
                    ),
                  ]),
                  if (pro['isAvailable'] == true)
                    const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.circle, size: 8, color: Color(0xFF2E8B57)),
                      SizedBox(width: 4),
                      Text('Disponible', style: TextStyle(fontSize: 12, color: Color(0xFF2E8B57))),
                    ]),
                ]),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('Desde', style: TextStyle(fontSize: 11, color: NetJobColors.muted)),
              Text(cop(pro['minPrice']), style: const TextStyle(fontWeight: FontWeight.w800, color: NetJobColors.primary)),
              if (pro['diagnosticFee'] != null)
                Text(
                  pro['diagnosticFee'] == 0 ? 'Visita gratis' : 'Visita ${cop(pro['diagnosticFee'])}',
                  style: TextStyle(fontSize: 11, color: pro['diagnosticFee'] == 0 ? NetJobColors.mint : NetJobColors.muted),
                ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Etiqueta pequeña de una tarjeta de profesional.
class _Tag extends StatelessWidget {
  const _Tag(this.text, this.color, this.icon);
  final String text;
  final Color color;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color)),
        ]),
      );
}

// ============================ Búsqueda y filtros ============================

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.q, this.categoryId, this.title});
  final String? q;
  final String? categoryId;
  final String? title;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final _q = TextEditingController(text: widget.q);
  late Map<String, dynamic> _filters = {'categoryId': widget.categoryId, 'sort': 'relevance'};
  int _version = 0;

  int get _activeFilters =>
      ['minRating', 'maxPrice', 'available', 'day'].where((k) => _filters[k] != null && _filters[k] != false).length;

  void _apply(Map<String, dynamic> f) => setState(() {
        _filters = f;
        _version++;
      });

  Future<void> _openFilters(List categories) async {
    final r = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FiltersSheet(initial: _filters, categories: categories),
    );
    if (r != null) _apply(r);
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocationState>();
    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? 'Buscar profesionales')),
      body: AsyncView<List>(
        load: () async => await Api.instance.get('/categories') as List,
        builder: (context, categories, _) => Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _q,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(hintText: '¿Qué necesitas?', prefixIcon: Icon(Icons.search), isDense: true),
                  onSubmitted: (_) => setState(() => _version++),
                ),
              ),
              const SizedBox(width: 8),
              Badge(
                isLabelVisible: _activeFilters > 0,
                label: Text('$_activeFilters'),
                child: IconButton.filledTonal(
                  icon: const Icon(Icons.tune),
                  tooltip: 'Filtros',
                  onPressed: () => _openFilters(categories),
                ),
              ),
            ]),
          ),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: LocationBar()),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              for (final s in const [
                ['relevance', 'Relevancia'],
                ['rating', 'Mejor calificados'],
                ['price', 'Menor precio'],
                ['distance', 'Más cercanos'],
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(s[1]),
                    selected: _filters['sort'] == s[0],
                    onSelected: (_) => _apply({..._filters, 'sort': s[0]}),
                  ),
                ),
            ]),
          ),
          Expanded(
            child: !loc.hasLocation
                ? EmptyState(
                    icon: Icons.location_searching,
                    title: 'Elige tu ubicación',
                    message: 'Mostramos profesionales a máximo 12 km de donde estás.',
                    action: FilledButton(onPressed: () => showLocationSheet(context), child: const Text('Elegir ubicación')),
                  )
                : AsyncView<Map>(
              key: ValueKey('$_version-${loc.key}'),
              load: () async => await Api.instance.get('/professionals', {
                ..._filters,
                'q': _q.text.trim(),
                'lat': loc.lat,
                'lng': loc.lng,
                'pageSize': 50,
              }) as Map,
              builder: (context, data, reload) {
                final items = data['items'] as List;
                if (items.isEmpty) {
                  return EmptyState(
                    icon: Icons.search_off,
                    title: 'No encontramos profesionales',
                    message: 'No hay resultados a menos de ${data['radiusKm']} km de ${loc.label}. Prueba con otra palabra o ajusta los filtros.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: reload,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length + 1,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => i == 0
                        ? Text('${data['total']} profesionales a menos de ${data['radiusKm']} km', style: TextStyle(color: NetJobColors.muted))
                        : ProCard(pro: items[i - 1]),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

class _FiltersSheet extends StatefulWidget {
  const _FiltersSheet({required this.initial, required this.categories});
  final Map<String, dynamic> initial;
  final List categories;
  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  late final Map<String, dynamic> f = Map.of(widget.initial);
  late final _maxPrice = TextEditingController(text: f['maxPrice']?.toString());

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text('Filtros', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          DropdownButtonFormField<String?>(
            initialValue: f['categoryId'],
            decoration: const InputDecoration(labelText: 'Categoría'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Todas')),
              for (final c in widget.categories) DropdownMenuItem(value: c['id'] as String, child: Text(c['name'])),
            ],
            onChanged: (v) => f['categoryId'] = v,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _maxPrice,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Precio máximo (COP)', prefixText: r'$ '),
          ),
          const SizedBox(height: 16),
          const Text('Calificación mínima'),
          Wrap(spacing: 8, children: [
            for (final r in [null, 3, 4, 4.5])
              ChoiceChip(
                label: r == null
                    ? const Text('Todas')
                    : Row(mainAxisSize: MainAxisSize.min, children: [Text('$r'), const Icon(Icons.star_rounded, size: 16, color: NetJobColors.star), const Text('+')]),
                selected: f['minRating'] == r,
                onSelected: (_) => setState(() => f['minRating'] = r),
              ),
          ]),
          const SizedBox(height: 12),
          DropdownButtonFormField<int?>(
            initialValue: f['day'],
            decoration: const InputDecoration(labelText: 'Atiende el día'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Cualquier día')),
              for (var i = 0; i < 7; i++) DropdownMenuItem(value: i, child: Text(weekdays[i])),
            ],
            onChanged: (v) => f['day'] = v,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Solo disponibles ahora'),
            value: f['available'] == true,
            onChanged: (v) => setState(() => f['available'] = v ? true : null),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, {'sort': f['sort'], 'categoryId': f['categoryId']}),
                child: const Text('Limpiar'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: () {
                  f['maxPrice'] = int.tryParse(_maxPrice.text.replaceAll(RegExp(r'\D'), ''));
                  Navigator.pop(context, f);
                },
                child: const Text('Aplicar'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ============================ Perfil público ============================

class ProfessionalScreen extends StatelessWidget {
  const ProfessionalScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil del profesional')),
      body: AsyncView<Map>(
        load: () async => await Api.instance.get('/professionals/$id') as Map,
        builder: (context, p, reload) {
          final user = p['user'] as Map;
          final services = p['services'] as List;
          final portfolio = p['portfolio'] as List;
          final availability = p['availability'] as List;
          final canRequest = auth.role == 'CLIENT' && p['canReceiveRequests'] == true;
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    GestureDetector(
                      onTap: user['avatarUrl'] == null
                          ? null
                          : () => openPhotoViewer(context, [user['avatarUrl']], captions: [user['name']], heroPrefix: 'avatar'),
                      child: Hero(
                        tag: photoHeroTag('avatar', 0, user['avatarUrl'] ?? ''),
                        child: UserAvatar(url: user['avatarUrl'], name: user['name'], radius: 42),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Flexible(child: Text(user['name'], style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
                      if (p['verified'] == true) const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Tooltip(message: 'Identidad y antecedentes verificados', child: Icon(Icons.verified, color: NetJobColors.primary)),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      PlanBadge(p['planBadge']),
                      if (p['verified'] == true) const _Tag('Antecedentes verificados', NetJobColors.primary, Icons.verified_user_rounded),
                      if (p['trained'] == true) const _Tag('Capacitado por NetJob', NetJobColors.sky, Icons.school_rounded),
                      if (p['featured'] == true) const _Tag('Destacado', Color(0xFFC77A12), Icons.campaign_rounded),
                      if (p['recommended'] == true) const _Tag('Recomendado', NetJobColors.mint, Icons.rocket_launch_rounded),
                    ]),
                    if (p['headline'] != null) Text(p['headline'], textAlign: TextAlign.center, style: TextStyle(color: NetJobColors.subtle)),
                    const SizedBox(height: 10),
                    Wrap(alignment: WrapAlignment.center, spacing: 16, runSpacing: 6, children: [
                      RatingStars(rating: p['ratingAvg'], count: p['ratingCount'], size: 18),
                      _Info(Icons.work_history_outlined, '${p['yearsExperience']} años de experiencia'),
                      if (p['city'] != null) _Info(Icons.place_outlined, p['city']),
                      () {
                        final (on, text) = availabilityText(p['availabilityNow'], enabled: p['availabilityNow']?['enabled'] != false);
                        return Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.circle, size: 10, color: on ? NetJobColors.mint : NetJobColors.muted),
                          const SizedBox(width: 6),
                          Text(text, style: TextStyle(fontSize: 13, color: on ? NetJobColors.mint : NetJobColors.subtle, fontWeight: FontWeight.w600)),
                        ]);
                      }(),
                    ]),
                    const SizedBox(height: 10),
                    Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
                      for (final c in p['categories']) Chip(label: Text(c['name']), visualDensity: VisualDensity.compact),
                    ]),
                    if (p['canReceiveRequests'] != true)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('Este profesional no está recibiendo solicitudes por ahora.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFC77A12))),
                      ),
                  ]),
                ),
              ),
              if (p['bio'] != null) ...[const SectionTitle('Sobre mí'), Text(p['bio'])],
              if (p['coverageArea'] != null) ...[
                const SectionTitle('Zona de cobertura'),
                Text([p['coverageArea'], p['city']].whereType<String>().join(' · ')),
              ],
              const SectionTitle('Servicios y precios'),
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: NetJobColors.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
                child: Text(
                  (p['diagnosticFee'] ?? 0) == 0
                      ? 'Los precios son de referencia: cada caso es distinto (materiales, complejidad). La visita de diagnóstico es gratis y el profesional te cotiza el valor final.'
                      : 'Los precios son de referencia: cada caso es distinto (materiales, complejidad). Pagas ${cop(p['diagnosticFee'])} por la visita de diagnóstico y el profesional te cotiza el valor final.',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              for (final s in services)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(s['title'], style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text('Desde', style: TextStyle(fontSize: 11, color: NetJobColors.muted)),
                            Text('${cop(s['price'])} ${priceUnitLabel[s['priceUnit']]}',
                                style: const TextStyle(fontWeight: FontWeight.w800, color: NetJobColors.primary)),
                          ]),
                        ]),
                        Text(s['category']['name'], style: TextStyle(fontSize: 12, color: NetJobColors.muted)),
                        const SizedBox(height: 6),
                        Text(s['description']),
                        if (s['conditions'] != null) ...[
                          const SizedBox(height: 6),
                          Text('Condiciones: ${s['conditions']}', style: TextStyle(fontSize: 12, color: NetJobColors.subtle)),
                        ],
                        if ((s['photos'] as List).isNotEmpty) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 70,
                            child: ListView(scrollDirection: Axis.horizontal, children: [
                              for (var k = 0; k < (s['photos'] as List).length; k++)
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: PhotoThumb(
                                    urls: [for (final x in s['photos']) x as String],
                                    index: k,
                                    captions: [for (final _ in s['photos']) s['title'] as String],
                                    heroPrefix: 'servicio-${s['id']}',
                                    width: 70,
                                    height: 70,
                                  ),
                                ),
                            ]),
                          ),
                        ],
                        if (canRequest) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              icon: const Icon(Icons.send_outlined),
                              label: const Text('Solicitar este servicio'),
                              onPressed: () => context.push('/request/new', extra: {
                                ...s,
                                'professionalName': user['name'],
                                'diagnosticFee': p['diagnosticFee'] ?? 0,
                                'blocks': p['blocks'] ?? const [],
                              }),
                            ),
                          ),
                        ],
                      ]),
                    ),
                  ),
                ),
              if (portfolio.isNotEmpty) ...[
                const SectionTitle('Trabajos realizados'),
                SizedBox(
                  height: 150,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: portfolio.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (_, i) => SizedBox(
                      width: 160,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        PhotoThumb(
                          urls: [for (final x in portfolio) x['imageUrl'] as String],
                          captions: [for (final x in portfolio) x['title'] as String?],
                          index: i,
                          heroPrefix: 'portafolio',
                          width: 160,
                          height: 120,
                        ),
                        const SizedBox(height: 4),
                        Text(portfolio[i]['title'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                      ]),
                    ),
                  ),
                ),
              ],
              if (availability.isNotEmpty) ...[
                const SectionTitle('Disponibilidad'),
                for (final a in availability)
                  Text('${weekdays[a['dayOfWeek']]}: ${a['startTime']} – ${a['endTime']}'),
              ],
              const SizedBox(height: 20),
              ReviewsPreview(profile: p),
              const SizedBox(height: 24),
            ]),
          );
        },
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info(this.icon, this.text);
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: NetJobColors.muted),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 13, color: NetJobColors.subtle)),
      ]);
}

// ============================ Nueva solicitud ============================

class NewRequestScreen extends StatefulWidget {
  const NewRequestScreen({super.key, required this.service});
  final Map service;
  @override
  State<NewRequestScreen> createState() => _NewRequestScreenState();
}

class _NewRequestScreenState extends State<NewRequestScreen> {
  final _form = GlobalKey<FormState>();
  final _description = TextEditingController();
  final _address = TextEditingController();
  final _info = TextEditingController();
  DateTime? _date;
  TimeOfDay? _time;
  final List<XFile> _photos = [];
  bool _sending = false;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
      initialDate: _firstFreeDay(_date ?? now.add(const Duration(days: 1)), now.add(const Duration(days: 90))),
      selectableDayPredicate: (d) => !_dayFullyBlocked(d),
      helpText: _blocks.isEmpty ? null : 'Los días sin agenda del profesional no se pueden elegir',
    );
    if (d != null) setState(() => _date = d);
  }

  DateTime _firstFreeDay(DateTime from, DateTime last) {
    var d = from;
    while (_dayFullyBlocked(d) && d.isBefore(last)) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _time ?? const TimeOfDay(hour: 9, minute: 0));
    if (t != null) setState(() => _time = t);
  }

  Future<void> _pickPhotos() async {
    final files = await ImagePicker().pickMultiImage(imageQuality: 75, maxWidth: 1600);
    setState(() => _photos.addAll(files.take(6 - _photos.length)));
  }

  /// Días que el profesional bloqueó en su agenda (vacaciones, compromisos).
  List<(DateTime, DateTime)> get _blocks => [
        for (final b in (widget.service['blocks'] as List? ?? const []))
          (DateTime.parse(b['startsAt']).toLocal(), DateTime.parse(b['endsAt']).toLocal()),
      ];

  bool _dayFullyBlocked(DateTime d) {
    final start = DateTime(d.year, d.month, d.day);
    final end = start.add(const Duration(days: 1));
    return _blocks.any((b) => !b.$1.isAfter(start) && !b.$2.isBefore(end));
  }

  (DateTime, DateTime)? _blockAt(DateTime when) {
    final end = when.add(const Duration(hours: 2));
    for (final b in _blocks) {
      if (b.$1.isBefore(end) && b.$2.isAfter(when)) return b;
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_date == null || _time == null) return toast(context, 'Elige la fecha y la hora deseadas');
    final when = DateTime(_date!.year, _date!.month, _date!.day, _time!.hour, _time!.minute);
    final blocked = _blockAt(when);
    if (blocked != null) {
      return toast(context, 'El profesional no tiene agenda del ${fmtDateTime(blocked.$1.toUtc().toIso8601String())} al ${fmtDateTime(blocked.$2.toUtc().toIso8601String())}. Elige otra hora.');
    }
    setState(() => _sending = true);
    final loc = context.read<LocationState>();
    final auth = context.read<AuthState>();
    final router = GoRouter.of(context);
    try {
      final r = await Api.instance.post('/requests', {
        'serviceId': widget.service['id'],
        if (loc.hasLocation) 'lat': loc.lat,
        if (loc.hasLocation) 'lng': loc.lng,
        'description': _description.text.trim(),
        'address': _address.text.trim(),
        'scheduledAt': when.toUtc().toIso8601String(),
        if (_info.text.trim().isNotEmpty) 'additionalInfo': _info.text.trim(),
      });
      if (_photos.isNotEmpty) {
        await Api.instance.upload('/requests/${r['id']}/photos', _photos, field: 'files');
      }
      if (!mounted) return;
      toast(context, 'Solicitud enviada. Te avisaremos cuando el profesional responda.', error: false);
      auth.dataChanged();
      // Queda Inicio debajo del detalle: el botón atrás vuelve al inicio
      router.go('/home');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      router.push('/requests/${r['id']}');
    } catch (e) {
      if (mounted) toast(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    return Scaffold(
      appBar: AppBar(title: const Text('Solicitar servicio')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Card(
            child: ListTile(
              title: Text(s['title'], style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('con ${s['professionalName']}'),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('Desde', style: TextStyle(fontSize: 11, color: NetJobColors.muted)),
                Text('${cop(s['price'])} ${priceUnitLabel[s['priceUnit']]}',
                    style: const TextStyle(fontWeight: FontWeight.w800, color: NetJobColors.primary)),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _description,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Describe el problema o lo que necesitas', alignLabelWithHint: true),
            validator: (v) => (v ?? '').trim().length >= 10 ? null : 'Danos un poco más de detalle (mín. 10 caracteres)',
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _address,
            decoration: const InputDecoration(labelText: 'Dirección del servicio', prefixIcon: Icon(Icons.home_outlined), hintText: 'Calle, número, barrio, ciudad'),
            validator: (v) => (v ?? '').trim().length >= 5 ? null : 'Ingresa la dirección',
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(_date == null ? 'Fecha' : '${_date!.day}/${_date!.month}/${_date!.year}'),
                onPressed: _pickDate,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.schedule),
                label: Text(_time == null ? 'Hora' : _time!.format(context)),
                onPressed: _pickTime,
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextFormField(
            controller: _info,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Información adicional (opcional)', hintText: 'Ej: portería, parqueadero, mascotas…'),
          ),
          const SizedBox(height: 16),
          Text('Fotos (opcional)', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final f in _photos)
              Chip(label: Text(f.name, overflow: TextOverflow.ellipsis), onDeleted: () => setState(() => _photos.remove(f))),
            if (_photos.length < 6)
              ActionChip(avatar: const Icon(Icons.add_a_photo_outlined, size: 18), label: const Text('Agregar fotos'), onPressed: _pickPhotos),
          ]),
          const SizedBox(height: 20),
          FutureBuilder<Map<String, dynamic>>(
            future: appConfig(),
            builder: (context, snap) {
              final fee = (widget.service['diagnosticFee'] as num?) ?? 0;
              final rate = pct(snap.data?['commissionRate'] ?? 0.03);
              final warranty = snap.data?['warrantyDays'] ?? 30;
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: NetJobColors.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('¿Cómo funciona el pago?', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(
                      fee == 0
                          ? '1. Cuando el profesional acepte, va a revisar el problema. La visita de diagnóstico es gratis.'
                          : '1. Cuando el profesional acepte, pagas ${cop(fee)} por la visita de diagnóstico (lo fija cada profesional).',
                      style: const TextStyle(fontSize: 13)),
                  const Text('2. El profesional revisa el problema y te envía el precio final.', style: TextStyle(fontSize: 13)),
                  Text('3. Si estás de acuerdo, pagas ese valor más la tarifa NetJob del $rate (menos si tienes un beneficio de cliente frecuente o invitado) y empieza el trabajo.', style: const TextStyle(fontSize: 13)),
                  Text('4. Tu pago queda retenido por NetJob hasta que confirmes que el trabajo terminó. Incluye $warranty días de garantía.', style: const TextStyle(fontSize: 13)),
                ]),
              );
            },
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _sending ? null : _submit, child: Text(_sending ? 'Enviando…' : 'Enviar solicitud')),
        ]),
      ),
    );
  }
}
