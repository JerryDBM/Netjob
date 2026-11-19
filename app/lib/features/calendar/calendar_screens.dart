import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../state/auth_state.dart';
import '../../widgets/common.dart';

/// Agenda de citas del cliente y del profesional: vista por mes, semana o día, detalle de
/// cada cita (qué hay que hacer, dónde y con quién), propuestas de cambio de hora, notas
/// privadas y, para el profesional, bloqueos de agenda.
class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key});
  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

enum _Mode { month, week, day }

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime _local(String iso) => DateTime.parse(iso).toLocal();
String _iso(DateTime d) => d.toUtc().toIso8601String();
bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
DateTime _weekStart(DateTime d) => _dateOnly(d).subtract(Duration(days: d.weekday - 1));

/// "3:00 pm" (intl escribe "p. m." con espacios especiales).
String _hour(DateTime d) =>
    DateFormat('h:mm a', 'es').format(d).replaceAllMapped(RegExp(r'\s*([ap])\.\s*m\.'), (m) => ' ${m[1]}m');
String _longDay(DateTime d) {
  final s = DateFormat("EEEE d 'de' MMMM", 'es').format(d);
  return s[0].toUpperCase() + s.substring(1);
}

/// "jueves 20 de noviembre · 3:00 pm"
String apptWhen(String iso) {
  final d = _local(iso);
  return '${_longDay(d)} · ${_hour(d)}';
}

Color _apptColor(Map a) => statusColor[a['status']] ?? NetJobColors.primary;

class _AgendaScreenState extends State<AgendaScreen> {
  _Mode _mode = _Mode.month;
  DateTime _anchor = _dateOnly(DateTime.now());
  DateTime _selected = _dateOnly(DateTime.now());
  int _version = 0;

  (DateTime, DateTime) get _range => switch (_mode) {
        _Mode.month => () {
            final first = DateTime(_anchor.year, _anchor.month, 1);
            final start = _weekStart(first);
            return (start, start.add(const Duration(days: 42)));
          }(),
        _Mode.week => (_weekStart(_anchor), _weekStart(_anchor).add(const Duration(days: 7))),
        _Mode.day => (_anchor, _anchor.add(const Duration(days: 1))),
      };

  Future<Map> _load() async {
    final (from, to) = _range;
    final now = DateTime.now();
    final r = await Future.wait([
      Api.instance.get('/calendar', {'from': _iso(from), 'to': _iso(to)}),
      // Propuestas de cambio pendientes de mi respuesta, en cualquier fecha próxima
      Api.instance.get('/calendar', {'from': _iso(now.subtract(const Duration(days: 1))), 'to': _iso(now.add(const Duration(days: 190)))}),
    ]);
    final upcoming = ((r[1] as Map)['appointments'] as List).cast<Map>();
    return {
      ...(r[0] as Map),
      'proposals': upcoming.where((a) => a['reschedule'] != null && a['reschedule']['byMe'] != true).toList(),
      'next': upcoming
          .where((a) => ['PENDING', 'ACCEPTED', 'IN_PROGRESS'].contains(a['status']) && _local(a['scheduledAt']).isAfter(now.subtract(const Duration(hours: 2))))
          .take(1)
          .toList(),
    };
  }

  void _reload() => setState(() => _version++);

  void _move(int dir) {
    setState(() {
      switch (_mode) {
        case _Mode.month:
          _anchor = DateTime(_anchor.year, _anchor.month + dir, 1);
          final now = DateTime.now();
          _selected = _anchor.year == now.year && _anchor.month == now.month ? _dateOnly(now) : _anchor;
        case _Mode.week:
          _anchor = _anchor.add(Duration(days: 7 * dir));
          _selected = _anchor;
        case _Mode.day:
          _anchor = _anchor.add(Duration(days: dir));
          _selected = _anchor;
      }
    });
  }

  void _today() => setState(() {
        _anchor = _dateOnly(DateTime.now());
        _selected = _anchor;
      });

  String get _title => switch (_mode) {
        _Mode.month => toBeginningOfSentenceCase(DateFormat('MMMM y', 'es').format(_anchor)),
        _Mode.week => () {
            final s = _weekStart(_anchor);
            final e = s.add(const Duration(days: 6));
            return s.month == e.month
                ? '${s.day} – ${e.day} de ${DateFormat('MMMM', 'es').format(e)}'
                : '${DateFormat('d MMM', 'es').format(s)} – ${DateFormat('d MMM', 'es').format(e)}';
          }(),
        _Mode.day => _longDay(_anchor),
      };

  Future<void> _open(Map a) async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: NetJobColors.bgSoft,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => AppointmentSheet(appointment: a),
    );
    // Al cerrar, se recarga por si cambió la hora, la propuesta o la nota
    if (mounted) _reload();
  }

  Future<void> _addBlock() async {
    final created = await showDialog<bool>(context: context, builder: (_) => _BlockDialog(initial: _selected));
    if (created == true) _reload();
  }

  Future<void> _deleteBlock(Map b) async {
    if (!await confirm(context, 'Quitar bloqueo', 'Los clientes podrán volver a pedirte citas en ese horario.', ok: 'Quitar')) return;
    try {
      await Api.instance.delete('/calendar/blocks/${b['id']}');
      _reload();
    } catch (e) {
      if (mounted) toast(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPro = context.watch<AuthState>().isPro;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi agenda'),
        actions: [
          TextButton(onPressed: _today, child: const Text('Hoy')),
        ],
      ),
      floatingActionButton: isPro
          ? FloatingActionButton.extended(
              onPressed: _addBlock,
              icon: const Icon(Icons.event_busy_outlined),
              label: const Text('Bloquear agenda'),
            )
          : null,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: SegmentedButton<_Mode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: _Mode.month, label: Text('Mes')),
              ButtonSegment(value: _Mode.week, label: Text('Semana')),
              ButtonSegment(value: _Mode.day, label: Text('Día')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() {
              _mode = s.first;
              _anchor = _selected;
            }),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(children: [
            IconButton(onPressed: () => _move(-1), icon: const Icon(Icons.chevron_left_rounded), tooltip: 'Anterior'),
            Expanded(child: Text(_title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            IconButton(onPressed: () => _move(1), icon: const Icon(Icons.chevron_right_rounded), tooltip: 'Siguiente'),
          ]),
        ),
        Expanded(
          child: AsyncView<Map>(
            key: ValueKey('$_mode-$_anchor-$_version'),
            load: _load,
            builder: (context, data, reload) {
              final appts = (data['appointments'] as List).cast<Map>();
              final blocks = (data['blocks'] as List).cast<Map>();
              final proposals = (data['proposals'] as List).cast<Map>();
              final next = (data['next'] as List).cast<Map>();
              final header = <Widget>[
                for (final p in proposals) _ProposalBanner(appointment: p, onTap: () => _open(p)),
                if (next.isNotEmpty && _mode == _Mode.month) _NextUp(appointment: next.first, onTap: () => _open(next.first)),
              ];
              return RefreshIndicator(
                onRefresh: () async => _reload(),
                child: switch (_mode) {
                  _Mode.month => ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 96), children: [
                      ...header,
                      _MonthGrid(
                        month: _anchor,
                        selected: _selected,
                        appointments: appts,
                        blocks: blocks,
                        onSelect: (d) => setState(() => _selected = d),
                      ),
                      const SizedBox(height: 10),
                      _DayList(
                        day: _selected,
                        appointments: appts,
                        blocks: blocks,
                        isPro: isPro,
                        onOpen: _open,
                        onDeleteBlock: _deleteBlock,
                      ),
                    ]),
                  _Mode.week => ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 96), children: [
                      ...header,
                      for (var i = 0; i < 7; i++)
                        _DayList(
                          day: _weekStart(_anchor).add(Duration(days: i)),
                          appointments: appts,
                          blocks: blocks,
                          isPro: isPro,
                          onOpen: _open,
                          onDeleteBlock: _deleteBlock,
                          compact: true,
                        ),
                    ]),
                  _Mode.day => ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 96), children: [
                      ...header,
                      _DayList(
                        day: _anchor,
                        appointments: appts,
                        blocks: blocks,
                        isPro: isPro,
                        onOpen: _open,
                        onDeleteBlock: _deleteBlock,
                        showTitle: false,
                      ),
                    ]),
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ---------------- Vista por mes ----------------

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({required this.month, required this.selected, required this.appointments, required this.blocks, required this.onSelect});
  final DateTime month;
  final DateTime selected;
  final List<Map> appointments;
  final List<Map> blocks;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final start = _weekStart(DateTime(month.year, month.month, 1));
    final today = _dateOnly(DateTime.now());
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(children: [
          Row(children: [
            for (final d in const ['L', 'M', 'M', 'J', 'V', 'S', 'D'])
              Expanded(child: Center(child: Text(d, style: const TextStyle(color: NetJobColors.muted, fontWeight: FontWeight.w700, fontSize: 12)))),
          ]),
          const SizedBox(height: 4),
          for (var w = 0; w < 6; w++)
            Row(children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Builder(builder: (context) {
                    final day = start.add(Duration(days: w * 7 + i));
                    final inMonth = day.month == month.month;
                    final dayAppts = appointments.where((a) => _sameDay(_local(a['scheduledAt']), day)).toList();
                    final blocked = _isBlocked(day, blocks);
                    final isSel = _sameDay(day, selected);
                    final isToday = _sameDay(day, today);
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => onSelect(day),
                      child: Container(
                        height: 50,
                        margin: const EdgeInsets.all(1.5),
                        decoration: BoxDecoration(
                          color: isSel
                              ? NetJobColors.primary.withValues(alpha: 0.22)
                              : blocked
                                  ? NetJobColors.danger.withValues(alpha: 0.10)
                                  : null,
                          borderRadius: BorderRadius.circular(12),
                          border: isToday ? Border.all(color: NetJobColors.primary, width: 1.4) : null,
                        ),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text(
                            '${day.day}',
                            style: TextStyle(
                              fontWeight: isSel || isToday ? FontWeight.w800 : FontWeight.w500,
                              color: !inMonth ? NetJobColors.muted.withValues(alpha: 0.5) : blocked ? NetJobColors.danger : NetJobColors.ink,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            for (final a in dayAppts.take(3))
                              Container(
                                width: 6,
                                height: 6,
                                margin: const EdgeInsets.symmetric(horizontal: 1),
                                decoration: BoxDecoration(color: _apptColor(a), shape: BoxShape.circle),
                              ),
                            if (dayAppts.length > 3) const Text('+', style: TextStyle(fontSize: 9, color: NetJobColors.subtle)),
                          ]),
                        ]),
                      ),
                    );
                  }),
                ),
            ]),
          const SizedBox(height: 6),
          Wrap(spacing: 12, runSpacing: 4, alignment: WrapAlignment.center, children: [
            for (final s in const ['PENDING', 'ACCEPTED', 'IN_PROGRESS', 'COMPLETED'])
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: statusColor[s], shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text(statusLabel[s]!, style: const TextStyle(fontSize: 11, color: NetJobColors.subtle)),
              ]),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: NetJobColors.danger.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 4),
              const Text('Sin agenda', style: TextStyle(fontSize: 11, color: NetJobColors.subtle)),
            ]),
          ]),
        ]),
      ),
    );
  }
}

bool _isBlocked(DateTime day, List<Map> blocks) {
  final start = _dateOnly(day);
  final end = start.add(const Duration(days: 1));
  return blocks.any((b) => _local(b['startsAt']).isBefore(end) && _local(b['endsAt']).isAfter(start));
}

// ---------------- Lista de un día ----------------

class _DayList extends StatelessWidget {
  const _DayList({
    required this.day,
    required this.appointments,
    required this.blocks,
    required this.isPro,
    required this.onOpen,
    required this.onDeleteBlock,
    this.compact = false,
    this.showTitle = true,
  });
  final DateTime day;
  final List<Map> appointments;
  final List<Map> blocks;
  final bool isPro;
  final ValueChanged<Map> onOpen;
  final ValueChanged<Map> onDeleteBlock;
  final bool compact;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final start = _dateOnly(day);
    final end = start.add(const Duration(days: 1));
    final items = appointments.where((a) => _sameDay(_local(a['scheduledAt']), day)).toList()
      ..sort((a, b) => a['scheduledAt'].compareTo(b['scheduledAt']));
    // Citas que tienen una propuesta para moverse a este día
    final proposedHere = appointments
        .where((a) => a['reschedule'] != null && _sameDay(_local(a['reschedule']['at']), day) && !_sameDay(_local(a['scheduledAt']), day))
        .toList();
    final dayBlocks = blocks.where((b) => _local(b['startsAt']).isBefore(end) && _local(b['endsAt']).isAfter(start)).toList();
    final isToday = _sameDay(day, DateTime.now());

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (showTitle)
        Padding(
          padding: EdgeInsets.fromLTRB(4, compact ? 14 : 4, 4, 6),
          child: Row(children: [
            Text(isToday ? 'Hoy · ${_longDay(day)}' : _longDay(day), style: const TextStyle(fontWeight: FontWeight.w800)),
            const Spacer(),
            if (items.isNotEmpty) Text('${items.length} ${items.length == 1 ? 'cita' : 'citas'}', style: const TextStyle(color: NetJobColors.muted, fontSize: 12)),
          ]),
        ),
      for (final b in dayBlocks)
        Card(
          color: NetJobColors.danger.withValues(alpha: 0.08),
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.event_busy_rounded, color: NetJobColors.danger),
            title: Text(isPro ? (b['reason'] ?? 'Sin agenda') : 'El profesional no tiene agenda', style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${fmtDateTime(b['startsAt'])} → ${fmtDateTime(b['endsAt'])}', style: const TextStyle(fontSize: 12)),
            trailing: isPro ? IconButton(tooltip: 'Quitar bloqueo', icon: const Icon(Icons.delete_outline), onPressed: () => onDeleteBlock(b)) : null,
          ),
        ),
      if (items.isEmpty && dayBlocks.isEmpty && proposedHere.isEmpty)
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: compact ? 2 : 16),
          child: Text(
            compact ? 'Libre' : (isPro ? 'No tienes citas este día.' : 'No tienes citas este día. Busca un profesional y agenda una visita.'),
            style: const TextStyle(color: NetJobColors.muted),
          ),
        ),
      for (final a in items) _AppointmentTile(appointment: a, onTap: () => onOpen(a)),
      for (final a in proposedHere) _AppointmentTile(appointment: a, onTap: () => onOpen(a), proposedView: true),
    ]);
  }
}

class _AppointmentTile extends StatelessWidget {
  const _AppointmentTile({required this.appointment, required this.onTap, this.proposedView = false});
  final Map appointment;
  final VoidCallback onTap;
  final bool proposedView;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final isPro = context.read<AuthState>().isPro;
    final when = _local(proposedView ? a['reschedule']['at'] : a['scheduledAt']);
    final end = when.add(const Duration(hours: 2));
    final color = _apptColor(a);
    final other = a['counterpart'] as Map;
    final faded = ['COMPLETED', 'CANCELLED', 'REJECTED'].contains(a['status']) || proposedView;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 5, color: color.withValues(alpha: faded ? 0.4 : 1)),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
              child: SizedBox(
                width: 62,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_hour(when), style: TextStyle(fontWeight: FontWeight.w800, color: faded ? NetJobColors.subtle : NetJobColors.ink)),
                  Text(_hour(end), style: const TextStyle(fontSize: 11.5, color: NetJobColors.muted)),
                ]),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 10, 12, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(categoryIcon(a['service']['icon']), size: 16, color: color),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(a['service']['title'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ]),
                  const SizedBox(height: 2),
                  Text(
                    '${isPro ? 'Cliente' : 'Con'} ${other['name']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: NetJobColors.textSoft),
                  ),
                  Text(a['address'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: NetJobColors.muted)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    _Pill(proposedView ? 'Hora propuesta' : stageLabel(a['stage'] ?? a['status'], isPro: isPro), color),
                    if (!proposedView && a['reschedule'] != null)
                      _Pill(a['reschedule']['byMe'] == true ? 'Propusiste otra hora' : 'Proponen otra hora', NetJobColors.warning),
                    if (a['myNote'] != null) const _Pill('Con nota', NetJobColors.sky, icon: Icons.sticky_note_2_outlined),
                  ]),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.color, {this.icon});
  final String text;
  final Color color;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 12, color: color), const SizedBox(width: 3)],
          Flexible(child: Text(text, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color))),
        ]),
      );
}

class _ProposalBanner extends StatelessWidget {
  const _ProposalBanner({required this.appointment, required this.onTap});
  final Map appointment;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final a = appointment;
    return Card(
      color: NetJobColors.warning.withValues(alpha: 0.12),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        leading: const Icon(Icons.update_rounded, color: NetJobColors.warning),
        title: Text('${(a['counterpart']['name'] as String).split(' ').first} propone cambiar la hora', style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('${a['service']['title']}: ${apptWhen(a['scheduledAt'])} → ${apptWhen(a['reschedule']['at'])}'),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

class _NextUp extends StatelessWidget {
  const _NextUp({required this.appointment, required this.onTap});
  final Map appointment;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final when = _local(a['scheduledAt']);
    final diff = when.difference(DateTime.now());
    final soon = diff.isNegative
        ? 'Ahora'
        : diff.inMinutes < 60
            ? 'En ${diff.inMinutes} min'
            : diff.inHours < 24
                ? 'En ${diff.inHours} h'
                : 'En ${diff.inDays} ${diff.inDays == 1 ? 'día' : 'días'}';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(gradient: NetJobColors.heroGradient, borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Próxima cita · $soon', style: const TextStyle(color: NetJobColors.primaryLight, fontWeight: FontWeight.w700, fontSize: 12.5)),
                const SizedBox(height: 4),
                Text(a['service']['title'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
                Text('${apptWhen(a['scheduledAt'])} · ${a['counterpart']['name']}', style: const TextStyle(color: NetJobColors.textSoft, fontSize: 12.5)),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white),
          ]),
        ),
      ),
    );
  }
}

// ---------------- Detalle de una cita ----------------

class AppointmentSheet extends StatefulWidget {
  const AppointmentSheet({super.key, required this.appointment});
  final Map appointment;
  @override
  State<AppointmentSheet> createState() => _AppointmentSheetState();
}

class _AppointmentSheetState extends State<AppointmentSheet> {
  late Map _a = widget.appointment;

  @override
  Widget build(BuildContext context) {
    final a = _a;
    final isPro = context.read<AuthState>().isPro;
    final other = a['counterpart'] as Map;
    final when = _local(a['scheduledAt']);
    final color = _apptColor(a);
    Widget row(IconData icon, String text, {Color? c}) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 19, color: c ?? NetJobColors.subtle),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ]),
        );

    return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (context, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 10, 20, 28), children: [
          Center(
            child: Container(width: 40, height: 4, decoration: BoxDecoration(color: NetJobColors.border, borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Icon(categoryIcon(a['service']['icon']), color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(a['service']['title'], style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
            StatusChip(a['status']),
          ]),
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 14),
            child: Text('${a['service']['category']} · ${stageLabel(a['stage'] ?? a['status'], isPro: isPro)}', style: const TextStyle(color: NetJobColors.muted, fontSize: 12.5)),
          ),
          row(Icons.event_rounded, '${_longDay(when)}\n${_hour(when)} a ${_hour(when.add(const Duration(hours: 2)))} (tiempo estimado)', c: color),
          row(Icons.place_outlined, a['address']),
          Row(children: [
            UserAvatar(url: other['avatarUrl'], name: other['name'], radius: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(isPro ? 'Cliente' : 'Profesional', style: const TextStyle(fontSize: 11.5, color: NetJobColors.muted)),
                Text(other['name'], style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
            ),
            if (['PENDING', 'ACCEPTED', 'IN_PROGRESS'].contains(a['status']))
              IconButton.filledTonal(
                tooltip: 'Chat',
                onPressed: () => context.push('/requests/${a['id']}/chat', extra: other['name']),
                icon: const Icon(Icons.chat_bubble_outline_rounded),
              ),
          ]),
          const SectionTitle('Qué hay que hacer'),
          Text(a['description']),
          if (a['additionalInfo'] != null) ...[
            const SizedBox(height: 6),
            Text('Info adicional: ${a['additionalInfo']}', style: const TextStyle(color: NetJobColors.subtle)),
          ],
          if (a['quoteNote'] != null) ...[
            const SizedBox(height: 8),
            Text('Cotización: “${a['quoteNote']}”', style: const TextStyle(fontStyle: FontStyle.italic, color: NetJobColors.textSoft)),
          ],
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: [
            _Pill((a['diagnosticFee'] ?? 0) == 0 ? 'Visita gratis' : 'Visita ${cop(a['diagnosticFee'])}', NetJobColors.primary),
            if (a['agreedPrice'] != null) _Pill('Cotizado ${cop(a['agreedPrice'])}', NetJobColors.mint),
          ]),
          const SizedBox(height: 14),
          AppointmentTools(
            requestId: a['id'],
            status: a['status'],
            scheduledAt: a['scheduledAt'],
            reschedule: a['reschedule'] as Map?,
            myNote: a['myNote'],
            counterpartName: other['name'],
            onChanged: (r) => setState(() {
              _a = {
                ..._a,
                'scheduledAt': r['scheduledAt'] ?? _a['scheduledAt'],
                'reschedule': r.containsKey('reschedule') ? r['reschedule'] : _a['reschedule'],
                'myNote': r.containsKey('myNote') ? r['myNote'] : _a['myNote'],
              };
            }),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: () {
              final router = GoRouter.of(context);
              Navigator.of(context).pop();
              router.push('/requests/${a['id']}');
            },
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('Ver solicitud completa'),
          ),
        ]),
    );
  }
}

// ---------------- Reprogramar y notas (agenda y detalle de solicitud) ----------------

/// Propuesta de cambio de hora (proponer, aceptar, rechazar o retirar) y nota privada.
/// `onChanged` recibe lo que devolvió la API (scheduledAt, reschedule, myNote).
class AppointmentTools extends StatefulWidget {
  const AppointmentTools({
    super.key,
    required this.requestId,
    required this.status,
    required this.scheduledAt,
    required this.reschedule,
    required this.myNote,
    required this.counterpartName,
    required this.onChanged,
  });
  final String requestId;
  final String status;
  final String scheduledAt;
  final Map? reschedule;
  final String? myNote;
  final String counterpartName;
  final ValueChanged<Map> onChanged;

  @override
  State<AppointmentTools> createState() => _AppointmentToolsState();
}

class _AppointmentToolsState extends State<AppointmentTools> {
  bool _busy = false;

  bool get _canMove => widget.status == 'PENDING' || widget.status == 'ACCEPTED';

  Future<void> _run(Future<dynamic> Function() fn, String ok) async {
    setState(() => _busy = true);
    try {
      final r = await fn();
      if (r is Map) widget.onChanged(r);
      if (mounted) toast(context, ok, error: false);
    } catch (e) {
      if (mounted) toast(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _propose() async {
    final current = _local(widget.scheduledAt);
    final picked = await showDialog<(DateTime, String)>(context: context, builder: (_) => _ProposeDialog(current: current));
    if (picked == null) return;
    await _run(
      () => Api.instance.post('/requests/${widget.requestId}/reschedule', {
        'scheduledAt': _iso(picked.$1),
        if (picked.$2.isNotEmpty) 'note': picked.$2,
      }),
      'Propuesta enviada. ${widget.counterpartName.split(' ').first} debe aceptarla.',
    );
  }

  Future<void> _respond(bool accept, {bool withdraw = false}) async {
    await _run(
      () => Api.instance.post('/requests/${widget.requestId}/reschedule/respond', {'accept': accept}),
      withdraw ? 'Retiraste la propuesta' : (accept ? 'Cita reprogramada' : 'Propuesta rechazada: la cita sigue igual'),
    );
  }

  Future<void> _editNote() async {
    final text = await promptText(
      context,
      'Mi nota de la cita',
      hint: 'Solo tú la ves. Ej: llevar escalera, timbre dañado…',
      ok: 'Guardar',
      initial: widget.myNote,
    );
    if (text == null) return;
    await _run(() async {
      final r = await Api.instance.put('/requests/${widget.requestId}/note', {'note': text.trim()});
      return {'myNote': (r as Map)['note']};
    }, text.trim().isEmpty ? 'Nota borrada' : 'Nota guardada');
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.reschedule;
    final first = widget.counterpartName.split(' ').first;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (r != null && r['byMe'] != true)
        Card(
          color: NetJobColors.warning.withValues(alpha: 0.12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.update_rounded, color: NetJobColors.warning),
                const SizedBox(width: 8),
                Expanded(child: Text('$first propone cambiar la cita', style: const TextStyle(fontWeight: FontWeight.w800))),
              ]),
              const SizedBox(height: 6),
              Text('Nueva hora: ${apptWhen(r['at'])}', style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('Hora actual: ${apptWhen(widget.scheduledAt)}', style: const TextStyle(color: NetJobColors.subtle, fontSize: 12.5)),
              if (r['note'] != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('“${r['note']}”', style: const TextStyle(fontStyle: FontStyle.italic))),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: _busy ? null : () => _respond(false), child: const Text('Rechazar'))),
                const SizedBox(width: 10),
                Expanded(child: FilledButton(onPressed: _busy ? null : () => _respond(true), child: const Text('Aceptar cambio'))),
              ]),
            ]),
          ),
        )
      else if (r != null)
        Card(
          child: ListTile(
            leading: const Icon(Icons.schedule_send_rounded, color: NetJobColors.primary),
            title: Text('Propusiste: ${apptWhen(r['at'])}', style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('Esperando que $first responda'),
            trailing: TextButton(onPressed: _busy ? null : () => _respond(false, withdraw: true), child: const Text('Retirar')),
          ),
        )
      else if (_canMove)
        OutlinedButton.icon(
          onPressed: _busy ? null : _propose,
          icon: const Icon(Icons.edit_calendar_outlined),
          label: const Text('Proponer otra fecha u hora'),
        ),
      const SizedBox(height: 8),
      Card(
        child: ListTile(
          leading: const Icon(Icons.sticky_note_2_outlined, color: NetJobColors.sky),
          title: Text(widget.myNote ?? 'Agregar una nota privada', style: TextStyle(fontWeight: widget.myNote == null ? FontWeight.w600 : FontWeight.w500)),
          subtitle: Text(widget.myNote == null ? 'Solo tú la ves (ej. llevar escalera)' : 'Mi nota · solo tú la ves', style: const TextStyle(fontSize: 12)),
          trailing: const Icon(Icons.edit_outlined, size: 20),
          onTap: _busy ? null : _editNote,
        ),
      ),
    ]);
  }
}

class _ProposeDialog extends StatefulWidget {
  const _ProposeDialog({required this.current});
  final DateTime current;
  @override
  State<_ProposeDialog> createState() => _ProposeDialogState();
}

class _ProposeDialogState extends State<_ProposeDialog> {
  late DateTime _date = _dateOnly(widget.current.isAfter(DateTime.now()) ? widget.current : DateTime.now().add(const Duration(days: 1)));
  late TimeOfDay _time = TimeOfDay.fromDateTime(widget.current);
  final _note = TextEditingController();

  DateTime get _when => DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);

  @override
  Widget build(BuildContext context) {
    final valid = _when.isAfter(DateTime.now().add(const Duration(minutes: 30))) && _when != widget.current;
    return AlertDialog(
      title: const Text('Proponer otra hora'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Hora actual: ${_longDay(widget.current)} · ${_hour(widget.current)}', style: const TextStyle(color: NetJobColors.subtle, fontSize: 13)),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.event),
          label: Text(_longDay(_date)),
          onPressed: () async {
            final now = DateTime.now();
            final d = await showDatePicker(context: context, firstDate: _dateOnly(now), lastDate: now.add(const Duration(days: 120)), initialDate: _date);
            if (d != null) setState(() => _date = d);
          },
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.schedule),
          label: Text(_time.format(context)),
          onPressed: () async {
            final t = await showTimePicker(context: context, initialTime: _time);
            if (t != null) setState(() => _time = t);
          },
        ),
        const SizedBox(height: 12),
        TextField(controller: _note, maxLength: 300, decoration: const InputDecoration(labelText: 'Motivo (opcional)', hintText: 'Ej: ese día no estoy en casa')),
        if (!valid)
          const Text('Elige una hora distinta, al menos 30 minutos en el futuro.', style: TextStyle(color: NetJobColors.warning, fontSize: 12)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: valid ? () => Navigator.pop(context, (_when, _note.text.trim())) : null, child: const Text('Enviar propuesta')),
      ],
    );
  }
}

// ---------------- Bloqueos de agenda (profesional) ----------------

class _BlockDialog extends StatefulWidget {
  const _BlockDialog({required this.initial});
  final DateTime initial;
  @override
  State<_BlockDialog> createState() => _BlockDialogState();
}

class _BlockDialogState extends State<_BlockDialog> {
  late DateTimeRange _days = () {
    final today = _dateOnly(DateTime.now());
    final start = widget.initial.isBefore(today) ? today : widget.initial;
    return DateTimeRange(start: start, end: start);
  }();
  bool _allDay = true;
  TimeOfDay _from = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _to = const TimeOfDay(hour: 12, minute: 0);
  final _reason = TextEditingController();
  bool _saving = false;

  DateTime get _start => _allDay ? _days.start : DateTime(_days.start.year, _days.start.month, _days.start.day, _from.hour, _from.minute);
  DateTime get _end => _allDay
      ? _days.end.add(const Duration(days: 1))
      : DateTime(_days.end.year, _days.end.month, _days.end.day, _to.hour, _to.minute);

  Future<void> _save() async {
    if (!_end.isAfter(_start)) return toast(context, 'La hora final debe ser posterior a la inicial');
    setState(() => _saving = true);
    try {
      final r = await Api.instance.post('/calendar/blocks', {
        'startsAt': _iso(_start),
        'endsAt': _iso(_end),
        if (_reason.text.trim().isNotEmpty) 'reason': _reason.text.trim(),
      }) as Map;
      if (!mounted) return;
      final pending = (r['pendingInside'] as num?) ?? 0;
      toast(
        context,
        pending > 0
            ? 'Agenda bloqueada. Tienes $pending ${pending == 1 ? 'solicitud pendiente' : 'solicitudes pendientes'} en ese rango: recházalas o propón otra hora.'
            : 'Agenda bloqueada. Nadie podrá pedirte citas en ese rango.',
        error: pending > 0,
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) toast(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sameDay = _sameDay(_days.start, _days.end);
    return AlertDialog(
      title: const Text('Bloquear agenda'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Los clientes no podrán pedirte citas en ese tiempo. No puedes bloquear encima de citas ya aceptadas.',
              style: TextStyle(color: NetJobColors.subtle, fontSize: 13)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.date_range),
            label: Text(sameDay ? _longDay(_days.start) : '${DateFormat('d MMM', 'es').format(_days.start)} – ${DateFormat('d MMM', 'es').format(_days.end)}'),
            onPressed: () async {
              final now = DateTime.now();
              final r = await showDateRangePicker(
                context: context,
                firstDate: _dateOnly(now),
                lastDate: now.add(const Duration(days: 365)),
                initialDateRange: _days,
                helpText: 'Días sin agenda',
              );
              if (r != null) setState(() => _days = r);
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Todo el día'),
            value: _allDay,
            onChanged: (v) => setState(() => _allDay = v),
          ),
          if (!_allDay)
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final t = await showTimePicker(context: context, initialTime: _from);
                    if (t != null) setState(() => _from = t);
                  },
                  child: Text('Desde ${_from.format(context)}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final t = await showTimePicker(context: context, initialTime: _to);
                    if (t != null) setState(() => _to = t);
                  },
                  child: Text('Hasta ${_to.format(context)}'),
                ),
              ),
            ]),
          const SizedBox(height: 10),
          TextField(controller: _reason, maxLength: 200, decoration: const InputDecoration(labelText: 'Motivo (solo lo ves tú)', hintText: 'Ej: vacaciones, cita médica')),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Bloquear')),
      ],
    );
  }
}
