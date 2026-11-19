import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../state/auth_state.dart';
import '../../widgets/common.dart';

const _guideIcons = <String, IconData>{
  'support_agent': Icons.support_agent_rounded,
  'handshake': Icons.handshake_rounded,
  'health_and_safety': Icons.health_and_safety_rounded,
  'gavel': Icons.gavel_rounded,
};

/// Un instructivo desplegable. [onOpened] avisa cuando se abre (para saber que se leyó).
class _GuideCard extends StatelessWidget {
  const _GuideCard({required this.guide, this.read = false, this.onOpened});
  final Map guide;
  final bool read;
  final VoidCallback? onOpened;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          onExpansionChanged: (open) {
            if (open) onOpened?.call();
          },
          leading: Icon(_guideIcons[guide['icon']] ?? Icons.menu_book_rounded, color: NetJobColors.primary),
          title: Text(guide['title'], style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(guide['summary'], style: const TextStyle(color: NetJobColors.subtle, fontSize: 13)),
          trailing: read ? const Icon(Icons.check_circle, color: NetJobColors.mint) : null,
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final s in guide['sections'] as List) ...[
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Text(s['heading'], style: const TextStyle(fontWeight: FontWeight.w800, color: NetJobColors.primaryLight)),
              ),
              for (final p in s['points'] as List)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Padding(padding: EdgeInsets.only(top: 7), child: Icon(Icons.circle, size: 6, color: NetJobColors.muted)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(p, style: const TextStyle(height: 1.35))),
                  ]),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Capacitación inicial obligatoria del profesional:
///   1. leer los instructivos y aceptar las reglas y condiciones;
///   2. aprobar el cuestionario de 25 preguntas.
/// Con [guidesOnly] es la consulta posterior de los instructivos desde la cuenta.
class TrainingScreen extends StatefulWidget {
  const TrainingScreen({super.key, this.guidesOnly = false});
  final bool guidesOnly;
  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  Map? _data;
  Object? _error;
  final Set<String> _read = {};
  bool _accept = false;
  bool _busy = false;

  // Cuestionario
  bool _quiz = false;
  int _index = 0;
  late List<int?> _answers = [];
  Map? _result;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Api.instance.get('/training') as Map;
      if (!mounted) return;
      setState(() {
        _data = d;
        _answers = List<int?>.filled((d['questions'] as List).length, null);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Map get _state => _data!['state'] as Map;
  bool get _rulesAccepted => _state['rulesAcceptedAt'] != null;
  bool get _passed => _state['trainingPassedAt'] != null;

  Future<void> _acceptRules() async {
    setState(() => _busy = true);
    try {
      final st = await Api.instance.post('/training/accept-rules');
      if (!mounted) return;
      setState(() {
        _data = {..._data!, 'state': st};
        _quiz = true;
      });
    } catch (e) {
      if (mounted) toast(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final r = await Api.instance.post('/training/submit', {'answers': _answers}) as Map;
      if (!mounted) return;
      setState(() {
        _result = r;
        _data = {..._data!, 'state': r['state']};
      });
      if (r['passed'] == true) await context.read<AuthState>().reloadUser();
    } catch (e) {
      if (mounted) toast(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _retry() => setState(() {
        _result = null;
        _index = 0;
        _answers = List<int?>.filled(_answers.length, null);
      });

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.guidesOnly ? 'Instructivos y reglas' : _quiz ? 'Cuestionario' : 'Capacitación inicial'),
        leading: _quiz && _result == null
            ? IconButton(icon: const Icon(Icons.close), tooltip: 'Volver a los instructivos', onPressed: () => setState(() => _quiz = false))
            : null,
      ),
      body: d == null
          ? (_error != null
              ? EmptyState(icon: Icons.error_outline, title: 'No se pudo cargar', message: '$_error', action: FilledButton(onPressed: _load, child: const Text('Reintentar')))
              : const Center(child: CircularProgressIndicator()))
          : _result != null
              ? _resultView(d)
              : _quiz && !widget.guidesOnly
                  ? _quizView(d)
                  : _guidesView(d),
    );
  }

  // ---------- Paso 1: instructivos y reglas ----------

  Widget _guidesView(Map d) {
    final guides = d['guides'] as List;
    final allRead = guides.every((g) => _read.contains(g['id']));
    final needsRules = !widget.guidesOnly && !_rulesAccepted;
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (!widget.guidesOnly)
        Card(
          color: _passed ? NetJobColors.accent.withValues(alpha: 0.08) : NetJobColors.primary.withValues(alpha: 0.06),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(_passed ? Icons.workspace_premium_rounded : Icons.school_rounded, color: _passed ? NetJobColors.mint : NetJobColors.primary, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_passed ? 'Capacitación aprobada' : 'Antes de recibir clientes',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(
                    _passed
                        ? 'Obtuviste ${_state['trainingScore']} de ${_state['total']}. Los instructivos quedan disponibles aquí y en tu cuenta para cuando los necesites.'
                        : needsRules
                            ? 'Lee los cuatro instructivos, acepta las reglas y condiciones y luego responde un cuestionario de ${_state['total']} preguntas. Apruebas con ${_state['passScore']} respuestas correctas.'
                            : 'Ya aceptaste las reglas. Responde el cuestionario de ${_state['total']} preguntas: apruebas con ${_state['passScore']} correctas y puedes intentarlo las veces que necesites.',
                    style: const TextStyle(color: NetJobColors.subtle, height: 1.35),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      if (!widget.guidesOnly) const SizedBox(height: 14),
      for (final g in guides) ...[
        _GuideCard(guide: g, read: needsRules && _read.contains(g['id']), onOpened: () => setState(() => _read.add(g['id']))),
        const SizedBox(height: 10),
      ],
      if (needsRules) ...[
        const SizedBox(height: 4),
        CheckboxListTile(
          value: _accept,
          onChanged: allRead ? (v) => setState(() => _accept = v ?? false) : null,
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: const Text('Leí los instructivos y acepto las reglas y condiciones de NetJob', style: TextStyle(fontSize: 14.5)),
          subtitle: allRead ? null : Text('Abre los ${guides.length} instructivos para continuar (${_read.length}/${guides.length})', style: const TextStyle(color: NetJobColors.warning)),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _accept && allRead && !_busy ? _acceptRules : null,
          child: Text(_busy ? 'Guardando…' : 'Aceptar y empezar el cuestionario'),
        ),
      ] else if (!widget.guidesOnly && !_passed) ...[
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () => setState(() => _quiz = true),
          icon: const Icon(Icons.quiz_rounded),
          label: Text((_state['trainingAttempts'] ?? 0) > 0 ? 'Intentar de nuevo el cuestionario' : 'Empezar el cuestionario'),
        ),
        if ((_state['trainingAttempts'] ?? 0) > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Último intento: ${_state['trainingScore']} de ${_state['total']}', textAlign: TextAlign.center, style: const TextStyle(color: NetJobColors.muted)),
          ),
      ] else if (!widget.guidesOnly) ...[
        const SizedBox(height: 8),
        FilledButton(onPressed: () => context.canPop() ? context.pop() : context.go('/home'), child: const Text('Continuar')),
      ],
      const SizedBox(height: 24),
    ]);
  }

  // ---------- Paso 2: cuestionario ----------

  Widget _quizView(Map d) {
    final questions = d['questions'] as List;
    final q = questions[_index] as Map;
    final options = q['options'] as List;
    final answered = _answers.where((a) => a != null).length;
    final last = _index == questions.length - 1;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          LinearProgressIndicator(value: answered / questions.length, minHeight: 6, borderRadius: BorderRadius.circular(4)),
          const SizedBox(height: 8),
          Text('Pregunta ${_index + 1} de ${questions.length} · $answered respondidas', style: const TextStyle(color: NetJobColors.muted, fontSize: 13)),
        ]),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text(q['q'], style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, height: 1.25)),
          const SizedBox(height: 16),
          for (var o = 0; o < options.length; o++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: _answers[_index] == o ? NetJobColors.primary.withValues(alpha: 0.16) : NetJobColors.card,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(color: _answers[_index] == o ? NetJobColors.primary : NetJobColors.border, width: _answers[_index] == o ? 1.6 : 1),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => setState(() => _answers[_index] = o),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      Icon(_answers[_index] == o ? Icons.radio_button_checked : Icons.radio_button_off,
                          color: _answers[_index] == o ? NetJobColors.primary : NetJobColors.muted),
                      const SizedBox(width: 12),
                      Expanded(child: Text(options[o], style: const TextStyle(fontSize: 15.5, height: 1.3))),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      ),
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(children: [
            if (_index > 0) ...[
              OutlinedButton(onPressed: () => setState(() => _index--), child: const Text('Anterior')),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: last
                  ? FilledButton(
                      onPressed: answered == questions.length && !_busy ? _submit : null,
                      child: Text(_busy ? 'Calificando…' : answered == questions.length ? 'Enviar respuestas' : 'Faltan ${questions.length - answered} por responder'),
                    )
                  : FilledButton(
                      onPressed: _answers[_index] == null ? null : () => setState(() => _index++),
                      child: const Text('Siguiente'),
                    ),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _resultView(Map d) {
    final r = _result!;
    final passed = r['passed'] == true;
    final wrong = (r['wrong'] as List).cast<int>();
    final questions = d['questions'] as List;
    return ListView(padding: const EdgeInsets.all(20), children: [
      const SizedBox(height: 12),
      Icon(passed ? Icons.emoji_events_rounded : Icons.refresh_rounded, size: 72, color: passed ? NetJobColors.mint : NetJobColors.warning),
      const SizedBox(height: 12),
      Text(passed ? '¡Aprobaste la capacitación!' : 'Aún no alcanzas el puntaje',
          textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      Text('${r['score']} de ${r['total']} respuestas correctas · se aprueba con ${_state['passScore']}',
          textAlign: TextAlign.center, style: const TextStyle(color: NetJobColors.subtle)),
      const SizedBox(height: 20),
      if (wrong.isNotEmpty) ...[
        Text(passed ? 'Repasa estas preguntas' : 'Preguntas para repasar en los instructivos',
            style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        for (final i in wrong)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.close_rounded, size: 18, color: NetJobColors.danger),
              const SizedBox(width: 8),
              Expanded(child: Text(questions[i]['q'], style: const TextStyle(color: NetJobColors.textSoft))),
            ]),
          ),
        const SizedBox(height: 16),
      ],
      if (passed)
        FilledButton(onPressed: () => context.canPop() ? context.pop() : context.go('/home'), child: const Text('Continuar'))
      else ...[
        FilledButton(onPressed: _retry, child: const Text('Intentar de nuevo')),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: () => setState(() {
            _retry();
            _quiz = false;
          }),
          child: const Text('Volver a leer los instructivos'),
        ),
      ],
    ]);
  }
}

// ============================ Verificación de identidad ============================

const _docs = <(String, String, String, IconData)>[
  ('idFront', 'Cédula · frente', 'Foto clara, sin reflejos, con los cuatro bordes visibles', Icons.badge_rounded),
  ('idBack', 'Cédula · reverso', 'El lado de la huella y el código de barras', Icons.credit_card_rounded),
  ('selfie', 'Selfie con tu cédula', 'Tu cara y la cédula en la misma foto', Icons.face_rounded),
  ('backgroundCheck', 'Certificado de antecedentes', 'Captura del certificado de la Policía Nacional o Procuraduría, con fecha reciente', Icons.verified_user_rounded),
];

/// Imagen protegida del backend (documentos de identidad): viaja con el token de sesión.
class PrivateImage extends StatelessWidget {
  const PrivateImage(this.file, {super.key, this.width, this.height, this.fit = BoxFit.cover});
  final String file;
  final double? width;
  final double? height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => Image.network(
        '$apiBaseUrl/verification/files/$file',
        headers: Api.instance.authHeaders,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, _, _) => Container(
          width: width,
          height: height,
          color: NetJobColors.cardHigh,
          alignment: Alignment.center,
          child: const Icon(Icons.broken_image_outlined, color: NetJobColors.muted),
        ),
      );
}

/// Abre un documento en grande.
void showPrivateImage(BuildContext context, String file, String title) => showDialog(
      context: context,
      builder: (c) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 6, 6),
            child: Row(children: [
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(c)),
            ]),
          ),
          Flexible(child: InteractiveViewer(child: PrivateImage(file, fit: BoxFit.contain))),
        ]),
      ),
    );

/// El profesional sube sus documentos para que NetJob valide identidad y antecedentes.
class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});
  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  Map? _v;
  Object? _error;
  String? _uploading;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = await Api.instance.get('/verification') as Map;
      if (mounted) setState(() => _v = v);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _pick(String kind) async {
    // En el celular se puede tomar la foto en el momento; en web o escritorio se elige un archivo
    ImageSource source = ImageSource.gallery;
    final mobile = !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
    if (mobile) {
      final s = await showModalBottomSheet<ImageSource>(
        context: context,
        showDragHandle: true,
        builder: (c) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(leading: const Icon(Icons.photo_camera_rounded), title: const Text('Tomar foto'), onTap: () => Navigator.pop(c, ImageSource.camera)),
            ListTile(leading: const Icon(Icons.photo_library_rounded), title: const Text('Elegir de la galería'), onTap: () => Navigator.pop(c, ImageSource.gallery)),
          ]),
        ),
      );
      if (s == null) return;
      source = s;
    }
    final file = await ImagePicker().pickImage(source: source, imageQuality: 85, maxWidth: 2000);
    if (file == null) return;
    setState(() => _uploading = kind);
    try {
      final v = await Api.instance.upload('/verification/documents/$kind', [file]) as Map;
      if (mounted) setState(() => _v = v);
    } catch (e) {
      if (mounted) toast(context, e);
    } finally {
      if (mounted) setState(() => _uploading = null);
    }
  }

  Future<void> _submit() async {
    setState(() => _sending = true);
    try {
      final v = await Api.instance.post('/verification/submit') as Map;
      if (!mounted) return;
      setState(() => _v = v);
      toast(context, 'Documentos enviados. Te avisaremos cuando el equipo los revise.', error: false);
    } catch (e) {
      if (mounted) toast(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _v;
    return Scaffold(
      appBar: AppBar(title: const Text('Verificación de identidad')),
      body: v == null
          ? (_error != null
              ? EmptyState(icon: Icons.error_outline, title: 'No se pudo cargar', message: '$_error', action: FilledButton(onPressed: _load, child: const Text('Reintentar')))
              : const Center(child: CircularProgressIndicator()))
          : _body(v),
    );
  }

  Widget _body(Map v) {
    final status = v['status'] as String;
    final docs = v['documents'] as Map;
    final editable = status == 'NONE' || status == 'REJECTED';
    final complete = _docs.every((d) => docs[d.$1] != null);
    final (IconData icon, Color color, String title, String body) = switch (status) {
      'APPROVED' => (
          Icons.verified_rounded,
          NetJobColors.mint,
          'Identidad verificada',
          'Validamos tu identidad y tus antecedentes. Tu perfil muestra la insignia de verificado a los clientes.'
        ),
      'PENDING' => (
          Icons.hourglass_top_rounded,
          NetJobColors.sky,
          'Documentos en revisión',
          '${v['priority'] == true ? 'Tu plan incluye verificación prioritaria: estás al frente de la cola.' : 'El equipo de NetJob está revisando tus documentos.'} '
              '${v['required'] == true ? 'Mientras tanto no apareces en las búsquedas. ' : ''}Te avisaremos apenas haya respuesta.'
        ),
      'REJECTED' => (
          Icons.error_outline_rounded,
          NetJobColors.danger,
          'Necesitamos que corrijas tus documentos',
          '${v['note'] ?? 'Sube de nuevo los documentos.'}'
        ),
      _ => (
          Icons.shield_outlined,
          NetJobColors.primary,
          v['required'] == true ? 'Verificación obligatoria' : 'Gana la confianza de los clientes',
          v['required'] == true
              ? 'Para aparecer en las búsquedas y recibir solicitudes, NetJob debe validar tu identidad y tus antecedentes. Sube estos cuatro documentos y envíalos a revisión.'
              : 'Los clientes prefieren a profesionales verificados. Sube estos cuatro documentos y el equipo de NetJob valida tu identidad y tus antecedentes.'
        ),
    };
    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(
        color: color.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 4),
                Text(body, style: const TextStyle(color: NetJobColors.subtle, height: 1.35)),
                if (v['reviewedAt'] != null && status != 'PENDING')
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Revisado el ${fmtDate(v['reviewedAt'])}', style: const TextStyle(color: NetJobColors.muted, fontSize: 12)),
                  ),
              ]),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 14),
      for (final d in _docs) ...[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              docs[d.$1] != null
                  ? GestureDetector(
                      onTap: () => showPrivateImage(context, docs[d.$1], d.$2),
                      child: ClipRRect(borderRadius: BorderRadius.circular(12), child: PrivateImage(docs[d.$1], width: 64, height: 64)),
                    )
                  : Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(color: NetJobColors.cardHigh, borderRadius: BorderRadius.circular(12)),
                      child: Icon(d.$4, color: NetJobColors.muted),
                    ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text(d.$2, style: const TextStyle(fontWeight: FontWeight.w700))),
                    if (docs[d.$1] != null) ...[const SizedBox(width: 6), const Icon(Icons.check_circle, size: 16, color: NetJobColors.mint)],
                  ]),
                  Text(d.$3, style: const TextStyle(color: NetJobColors.subtle, fontSize: 12.5, height: 1.3)),
                ]),
              ),
              if (editable)
                _uploading == d.$1
                    ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                    : TextButton(onPressed: _uploading != null ? null : () => _pick(d.$1), child: Text(docs[d.$1] == null ? 'Subir' : 'Cambiar')),
            ]),
          ),
        ),
        const SizedBox(height: 10),
      ],
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: const [
        Icon(Icons.lock_outline_rounded, size: 16, color: NetJobColors.muted),
        SizedBox(width: 6),
        Expanded(
          child: Text(
            'Tus documentos son privados: solo los ve el equipo de NetJob para esta validación. No aparecen en tu perfil ni se comparten con los clientes.',
            style: TextStyle(color: NetJobColors.muted, fontSize: 12.5, height: 1.35),
          ),
        ),
      ]),
      const SizedBox(height: 16),
      if (editable)
        FilledButton(
          onPressed: complete && !_sending ? _submit : null,
          child: Text(_sending ? 'Enviando…' : complete ? 'Enviar a revisión' : 'Sube los cuatro documentos'),
        ),
      const SizedBox(height: 24),
    ]);
  }
}
