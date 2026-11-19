import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/support.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/photo_viewer.dart';

/// Etiqueta de estado de una reclamación.
class ClaimChip extends StatelessWidget {
  const ClaimChip(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext context) {
    final color = claimStatusColor[status] ?? NetJobColors.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
      child: Text(claimStatusLabel[status] ?? status, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}

/// Abre el formulario para reclamar sobre una solicitud. Devuelve true si se creó.
Future<bool> openClaimSheet(BuildContext context, Map request, {required bool isPro}) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ClaimSheet(request: request, isPro: isPro),
  );
  return r == true;
}

class _ClaimSheet extends StatefulWidget {
  const _ClaimSheet({required this.request, required this.isPro});
  final Map request;
  final bool isPro;
  @override
  State<_ClaimSheet> createState() => _ClaimSheetState();
}

class _ClaimSheetState extends State<_ClaimSheet> {
  String? _type;
  final _text = TextEditingController();
  final List<XFile> _photos = [];
  bool _sending = false;

  /// Motivos que aplican según quién reclama y en qué va la solicitud.
  List<String> get _types {
    final completed = widget.request['status'] == 'COMPLETED';
    if (widget.isPro) return ['BEHAVIOR', 'PAYMENT', 'OTHER'];
    return [
      if (completed) 'WARRANTY',
      'QUALITY',
      if (!completed) 'NO_SHOW',
      'EXTRA_CHARGE',
      'BEHAVIOR',
      'DAMAGE',
      if (!completed) 'PAYMENT',
      'OTHER',
    ];
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      final c = await Api.instance.post('/claims', {'requestId': widget.request['id'], 'type': _type, 'description': _text.text.trim()});
      if (_photos.isNotEmpty) await Api.instance.upload('/claims/${c['id']}/photos', _photos, field: 'files');
      if (!mounted) return;
      toast(context, 'Reclamación enviada. El equipo de NetJob la revisará y te avisará.', error: false);
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) toast(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final paidHeld = (widget.request['payments'] as List? ?? const []).any((p) => p['kind'] == 'SERVICE' && p['status'] == 'APPROVED' && p['payoutStatus'] == 'HELD');
    final valid = _type != null && _text.text.trim().length >= 20;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('¿Qué pasó?', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            paidHeld
                ? 'El pago del servicio está retenido por NetJob y seguirá así hasta que resolvamos tu caso.'
                : 'El equipo de NetJob revisa el chat, las fotos y el historial de la solicitud para resolverlo.',
            style: const TextStyle(color: NetJobColors.subtle),
          ),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final t in _types)
              ChoiceChip(label: Text(claimTypeLabel[t]!), selected: _type == t, onSelected: (_) => setState(() => _type = t)),
          ]),
          if (_type == 'DAMAGE')
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text('Los daños se remiten a la aseguradora aliada. Adjunta fotos claras del daño.', style: TextStyle(color: NetJobColors.sky, fontSize: 13)),
            ),
          if (_type == 'WARRANTY')
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text('Si el arreglo falló dentro de la garantía, el profesional debe volver a revisarlo sin costo.', style: TextStyle(color: NetJobColors.sky, fontSize: 13)),
            ),
          const SizedBox(height: 14),
          TextField(
            controller: _text,
            maxLines: 5,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Cuéntanos con detalle',
              hintText: 'Qué se acordó, qué ocurrió y cómo te gustaría que se resuelva (mín. 20 caracteres)',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final f in _photos) Chip(label: Text(f.name, overflow: TextOverflow.ellipsis), onDeleted: () => setState(() => _photos.remove(f))),
            if (_photos.length < 6)
              ActionChip(
                avatar: const Icon(Icons.add_a_photo_outlined, size: 18),
                label: const Text('Adjuntar fotos'),
                onPressed: () async {
                  final files = await ImagePicker().pickMultiImage(imageQuality: 75, maxWidth: 1600);
                  setState(() => _photos.addAll(files.take(6 - _photos.length)));
                },
              ),
          ]),
          const SizedBox(height: 16),
          FilledButton(onPressed: valid && !_sending ? _send : null, child: Text(_sending ? 'Enviando…' : 'Enviar reclamación')),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => openSupport(message: 'Hola NetJob, necesito ayuda urgente con un servicio.'),
            icon: const Icon(Icons.support_agent_rounded),
            label: const Text('Es urgente: escribir a soporte por WhatsApp'),
          ),
        ]),
      ),
    );
  }
}

/// Contenido de una reclamación (lo usan el usuario y el administrador).
class ClaimBody extends StatelessWidget {
  const ClaimBody({super.key, required this.claim, this.showParties = false});
  final Map claim;
  final bool showParties;

  @override
  Widget build(BuildContext context) {
    final req = claim['request'] as Map?;
    final photos = (claim['photos'] as List? ?? const []).cast<String>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(claimTypeLabel[claim['type']] ?? '${claim['type']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
        ClaimChip(claim['status']),
      ]),
      const SizedBox(height: 2),
      Text('${req?['service']?['title'] ?? 'Servicio'} · ${fmtDate(claim['createdAt'])}', style: const TextStyle(color: NetJobColors.muted, fontSize: 12.5)),
      if (showParties) ...[
        const SizedBox(height: 6),
        Text('Reclama: ${claim['openedBy']?['name']} (${claim['openedBy']?['role'] == 'CLIENT' ? 'cliente' : 'profesional'})', style: const TextStyle(color: NetJobColors.textSoft, fontSize: 13)),
        Text('Contra: ${claim['against']?['name']}', style: const TextStyle(color: NetJobColors.textSoft, fontSize: 13)),
      ],
      const SizedBox(height: 8),
      Text(claim['description'], style: const TextStyle(height: 1.35)),
      if (photos.isNotEmpty) ...[
        const SizedBox(height: 10),
        SizedBox(
          height: 72,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (var k = 0; k < photos.length; k++)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: PhotoThumb(urls: photos, index: k, heroPrefix: 'reclamo-${claim['id']}', width: 72, height: 72),
              ),
          ]),
        ),
      ],
      if (claim['resolution'] != null) ...[
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: NetJobColors.cardHigh, borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Decisión de NetJob · ${claimActionLabel[claim['action']] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: NetJobColors.primaryLight)),
            const SizedBox(height: 4),
            Text(claim['resolution'], style: const TextStyle(height: 1.35)),
          ]),
        ),
      ],
    ]);
  }
}

/// Mis reclamaciones: las que abrí y las que me abrieron.
class ClaimsScreen extends StatelessWidget {
  const ClaimsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reclamaciones y garantía')),
      body: AsyncView<List>(
        load: () async => await Api.instance.get('/claims') as List,
        builder: (context, items, reload) {
          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.verified_user_outlined,
              title: 'No tienes reclamaciones',
              message: 'Si algo sale mal con un servicio, abre la solicitud y toca "Tengo un problema". Para urgencias, escríbenos por WhatsApp.',
              action: OutlinedButton.icon(
                onPressed: () => openSupport(),
                icon: const Icon(Icons.support_agent_rounded),
                label: const Text('Soporte por WhatsApp'),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final c = items[i] as Map;
                return Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => context.push('/requests/${c['requestId']}'),
                    child: Padding(padding: const EdgeInsets.all(14), child: ClaimBody(claim: c)),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
