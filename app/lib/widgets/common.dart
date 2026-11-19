import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/theme.dart';

/// Muestra un mensaje de error/éxito en la parte inferior.
void toast(BuildContext context, Object message, {bool error = true}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message.toString()),
      backgroundColor: error ? const Color(0xFFC8452F) : const Color(0xFF2E8B57),
      behavior: SnackBarBehavior.floating,
    ));
}

/// Carga un futuro con estados de carga, error (con reintento) y datos.
class AsyncView<T> extends StatefulWidget {
  const AsyncView({super.key, required this.load, required this.builder});
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;

  @override
  State<AsyncView<T>> createState() => _AsyncViewState<T>();
}

class _AsyncViewState<T> extends State<AsyncView<T>> {
  late Future<T> _future = widget.load();

  Future<void> _reload() async {
    final f = widget.load();
    setState(() => _future = f);
    try {
      await f;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return EmptyState(
            icon: Icons.cloud_off,
            title: 'Algo salió mal',
            message: snap.error.toString(),
            action: FilledButton(onPressed: _reload, child: const Text('Reintentar')),
          );
        }
        return widget.builder(context, snap.data as T, _reload);
      },
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: NetJobColors.muted),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!, textAlign: TextAlign.center, style: TextStyle(color: NetJobColors.muted)),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = statusColor[status] ?? NetJobColors.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(statusLabel[status] ?? status,
          style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}

class RatingStars extends StatelessWidget {
  const RatingStars({super.key, required this.rating, this.count, this.size = 16});
  final num rating;
  final int? count;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.star_rounded, color: NetJobColors.star, size: size + 2),
      const SizedBox(width: 2),
      Text(count == 0 ? 'Nuevo' : rating.toStringAsFixed(1),
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: size - 2)),
      if (count != null && count! > 0)
        Text(' ($count)', style: TextStyle(color: NetJobColors.muted, fontSize: size - 3)),
    ]);
  }
}

class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, this.url, required this.name, this.radius = 24});
  final String? url;
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0]).join().toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: NetJobColors.primary.withValues(alpha: 0.12),
      foregroundImage: url != null ? NetworkImage(resolveUrl(url!)) : null,
      child: Text(initials, style: TextStyle(color: NetJobColors.primary, fontWeight: FontWeight.bold, fontSize: radius * 0.7)),
    );
  }
}

class NetImage extends StatelessWidget {
  const NetImage(this.url, {super.key, this.width, this.height, this.radius = 10});
  final String url;
  final double? width;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        resolveUrl(url),
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          width: width,
          height: height,
          color: NetJobColors.cardHigh,
          child: const Icon(Icons.broken_image_outlined, color: NetJobColors.muted),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Row(children: [
        Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
        ?trailing,
      ]),
    );
  }
}

/// Fila "etiqueta …… valor" para resúmenes de precios.
class AmountRow extends StatelessWidget {
  const AmountRow(this.label, this.value, {super.key, this.bold = false, this.hint});
  final String label;
  final String value;
  final bool bold;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.normal, fontSize: bold ? 16 : 14);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: style),
            if (hint != null) Text(hint!, style: TextStyle(fontSize: 11, color: NetJobColors.muted)),
          ]),
        ),
        Text(value, style: style),
      ]),
    );
  }
}

/// Diálogo de confirmación genérico.
Future<bool> confirm(BuildContext context, String title, String message, {String ok = 'Confirmar'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Volver')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}

/// Pide un texto en un diálogo (motivo de cancelación, nota, etc.).
Future<String?> promptText(BuildContext context, String title,
    {String hint = '', String ok = 'Enviar', int minLength = 0, String? initial, TextInputType? keyboard}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: keyboard,
          maxLines: keyboard == TextInputType.number ? 1 : 3,
          decoration: InputDecoration(hintText: hint),
          onChanged: (_) => setState(() {}),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Volver')),
          FilledButton(
            onPressed: ctrl.text.trim().length >= minLength ? () => Navigator.pop(c, ctrl.text.trim()) : null,
            child: Text(ok),
          ),
        ],
      ),
    ),
  );
}
