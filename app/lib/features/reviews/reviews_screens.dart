import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/design.dart';

/// Resumen oscuro de calificaciones: anillo de 0 a 5, total de reseñas,
/// porcentaje que recomienda y barras por número de estrellas.
class ReviewsSummaryCard extends StatelessWidget {
  const ReviewsSummaryCard({super.key, required this.avg, required this.count, required this.reviews, this.onTap});
  final double avg;
  final int count;
  final List reviews;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dist = {for (var s = 1; s <= 5; s++) s: reviews.where((r) => r['rating'] == s).length};
    final recommend = reviews.isEmpty ? 0 : (reviews.where((r) => (r['rating'] as int) >= 4).length * 100 / reviews.length).round();
    return Material(
      color: NetJobColors.nightCard,
      borderRadius: BorderRadius.circular(26),
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(26), border: Border.all(color: const Color(0xFF33244D))),
          child: Column(children: [
            Row(children: [
              Expanded(child: _stat('$count', count == 1 ? 'Reseña' : 'Reseñas')),
              RatingRing(
                value: avg,
                size: 150,
                center: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(count == 0 ? '—' : avg.toStringAsFixed(1),
                      style: TextStyle(fontFamily: NetJobFonts.display, color: Colors.white, fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: -1)),
                  const Text('de 5', style: TextStyle(color: Color(0xFFB9AECD), fontSize: 15)),
                ]),
              ),
              Expanded(child: _stat(reviews.isEmpty ? '—' : '$recommend%', 'Recomiendan')),
            ]),
            const SizedBox(height: 18),
            Row(children: [
              for (var s = 5; s >= 1; s--) ...[
                Expanded(child: LabeledBar(label: '$s', star: true, value: dist[s]!, total: reviews.length)),
                if (s > 1) const SizedBox(width: 10),
              ],
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _stat(String value, String label) => Column(children: [
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Color(0xFFB9AECD), fontSize: 14)),
      ]);
}

/// Una reseña: anillo pequeño con la foto del autor, nombre, nota y comentario.
class ReviewTile extends StatelessWidget {
  const ReviewTile({super.key, required this.r, this.last = false});
  final Map r;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final author = r['author'] as Map;
    final rating = (r['rating'] as num).toDouble();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: Color(0xFF33244D)))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        RatingRing(
          value: rating,
          size: 64,
          stroke: 5,
          center: UserAvatar(url: author['avatarUrl'], name: author['name'] ?? '', radius: 21),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(author['name'] ?? 'Cliente', overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
            ]),
            const SizedBox(height: 3),
            Text('${rating.toStringAsFixed(0)} de 5 · ${timeAgo(r['createdAt'])}',
                style: const TextStyle(color: Color(0xFFB9AECD), fontSize: 14)),
            if (r['comment'] != null && (r['comment'] as String).isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  margin: const EdgeInsets.only(right: 8, top: 1),
                  decoration: BoxDecoration(color: const Color(0xFF3B2560), borderRadius: BorderRadius.circular(8)),
                  child: const Text('Opinión', style: TextStyle(color: Color(0xFFE3C4FF), fontWeight: FontWeight.w800, fontSize: 11)),
                ),
                Expanded(
                  child: Text(r['comment'], style: const TextStyle(color: Colors.white, fontSize: 14.5, height: 1.35)),
                ),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }
}

/// Lista de reseñas en tarjeta oscura (debajo del resumen, como "Nutrition").
class ReviewsList extends StatelessWidget {
  const ReviewsList({super.key, required this.reviews, this.limit, this.emptyText});
  final List reviews;
  final int? limit;
  final String? emptyText;

  @override
  Widget build(BuildContext context) {
    final shown = limit == null ? reviews : reviews.take(limit!).toList();
    if (shown.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(color: NetJobColors.nightCard, borderRadius: BorderRadius.circular(24)),
        child: Text(emptyText ?? 'Aún no hay reseñas. Aparecerán cuando los clientes califiquen sus servicios.',
            style: const TextStyle(color: Color(0xFFB9AECD))),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: NetJobColors.nightCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF33244D)),
      ),
      child: Column(children: [
        for (var i = 0; i < shown.length; i++) ReviewTile(r: shown[i], last: i == shown.length - 1),
      ]),
    );
  }
}

/// Pantalla completa de reseñas de un profesional (la ven clientes y el mismo profesional).
class ReviewsScreen extends StatelessWidget {
  const ReviewsScreen({super.key, required this.professionalId});
  final String professionalId;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(scaffoldBackgroundColor: NetJobColors.night),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: NetJobColors.night,
          foregroundColor: Colors.white,
          titleTextStyle: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
        ),
        body: AsyncView<List>(
          load: () => Future.wait([
            Api.instance.get('/professionals/$professionalId'),
            Api.instance.get('/reviews/professional/$professionalId'),
          ]),
          builder: (context, data, reload) {
            final p = data[0] as Map;
            final reviews = data[1] as List;
            return RefreshIndicator(
              onRefresh: reload,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
                Text('Reseñas', style: TextStyle(fontFamily: NetJobFonts.display, color: Colors.white, fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: -1.2)),
                const SizedBox(height: 2),
                Text(p['user']['name'], style: const TextStyle(color: Color(0xFF2A1E3D), fontSize: 19)),
                const SizedBox(height: 22),
                Text('Resumen', style: TextStyle(fontFamily: NetJobFonts.display, color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                ReviewsSummaryCard(avg: (p['ratingAvg'] as num).toDouble(), count: p['ratingCount'], reviews: reviews),
                const SizedBox(height: 26),
                Text('Opiniones', style: TextStyle(fontFamily: NetJobFonts.display, color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                ReviewsList(reviews: reviews),
              ]),
            );
          },
        ),
      ),
    );
  }
}

/// Bloque compacto para el perfil del profesional: resumen + 3 reseñas + "Ver todas".
class ReviewsPreview extends StatelessWidget {
  const ReviewsPreview({super.key, required this.profile});
  final Map profile;

  @override
  Widget build(BuildContext context) {
    final reviews = profile['reviews'] as List;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: NetJobColors.night, borderRadius: BorderRadius.circular(28)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 12),
          child: Text('Reseñas', style: TextStyle(fontFamily: NetJobFonts.display, color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
        ),
        ReviewsSummaryCard(
          avg: (profile['ratingAvg'] as num).toDouble(),
          count: profile['ratingCount'],
          reviews: reviews,
          onTap: () => context.push('/pro/${profile['id']}/reviews'),
        ),
        const SizedBox(height: 12),
        ReviewsList(reviews: reviews, limit: 3),
        if (reviews.length > 3)
          TextButton(
            onPressed: () => context.push('/pro/${profile['id']}/reviews'),
            child: Text('Ver las ${reviews.length} reseñas', style: const TextStyle(color: NetJobColors.mint, fontWeight: FontWeight.w800)),
          ),
      ]),
    );
  }
}

/// Reseñas que los profesionales dejaron sobre un cliente. Las ve el mismo cliente
/// y los profesionales (para decidir si aceptan una solicitud).
class ClientReviewsScreen extends StatelessWidget {
  const ClientReviewsScreen({super.key, required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(scaffoldBackgroundColor: NetJobColors.night),
      child: Scaffold(
        appBar: AppBar(backgroundColor: NetJobColors.night, foregroundColor: Colors.white),
        body: AsyncView<Map>(
          load: () async => await Api.instance.get('/reviews/client/$userId') as Map,
          builder: (context, data, reload) {
            final c = data['client'] as Map;
            final reviews = data['reviews'] as List;
            return RefreshIndicator(
              onRefresh: reload,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
                Text('Reseñas', style: TextStyle(fontFamily: NetJobFonts.display, color: Colors.white, fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: -1.2)),
                const SizedBox(height: 2),
                Text('${c['name']} · como cliente', style: const TextStyle(color: Color(0xFF2A1E3D), fontSize: 19)),
                const SizedBox(height: 22),
                Text('Resumen', style: TextStyle(fontFamily: NetJobFonts.display, color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                ReviewsSummaryCard(avg: (c['clientRatingAvg'] as num).toDouble(), count: c['clientRatingCount'], reviews: reviews),
                const SizedBox(height: 26),
                Text('Lo que dicen los profesionales', style: TextStyle(fontFamily: NetJobFonts.display, color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                ReviewsList(reviews: reviews, emptyText: 'Aún no hay reseñas. Aparecerán cuando los profesionales califiquen sus servicios.'),
              ]),
            );
          },
        ),
      ),
    );
  }
}
