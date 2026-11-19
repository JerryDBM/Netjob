import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../state/auth_state.dart';
import '../../widgets/common.dart';

// ============================ Beneficios: referidos y cliente frecuente ============================

class BenefitsScreen extends StatelessWidget {
  const BenefitsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isPro = context.watch<AuthState>().isPro;
    return Scaffold(
      appBar: AppBar(title: const Text('Beneficios e invitados')),
      body: AsyncView<Map>(
        load: () async => await Api.instance.get('/me/benefits') as Map,
        builder: (context, b, reload) {
          final loyalty = b['loyalty'] as Map;
          final code = b['referralCode'] as String;
          final credits = (b['credits'] as num).toInt();
          final every = (loyalty['every'] as num).toInt();
          final remaining = (loyalty['remaining'] as num).toInt();
          final reduced = pct(b['reducedRate']);
          final standard = pct(b['standardRate']);
          final invite = isPro
              ? 'Trabajo con NetJob y consigo clientes cerca de mí. Regístrate como profesional con mi código $code.'
              : 'Uso NetJob para contratar servicios para el hogar. Regístrate con mi código $code y tu primer servicio paga solo $reduced de tarifa.';
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              if (!isPro) ...[
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(gradient: NetJobColors.heroGradient, borderRadius: BorderRadius.circular(24)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(credits > 0 ? 'Tienes $credits ${credits == 1 ? 'servicio' : 'servicios'} con tarifa reducida' : 'Tarifa reducida para clientes frecuentes',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(
                      credits > 0
                          ? 'En tu próximo servicio la tarifa NetJob baja del $standard al $reduced. Se aplica sola al pagar.'
                          : 'Cada $every servicios finalizados, si tu calificación como cliente es mayor a ${loyalty['minRating']}, un servicio paga $reduced en lugar de $standard.',
                      style: const TextStyle(color: NetJobColors.textSoft, height: 1.35),
                    ),
                  ]),
                ),
                const SizedBox(height: 14),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Tu avance', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(value: (every - remaining) / every, minHeight: 8, borderRadius: BorderRadius.circular(6)),
                      const SizedBox(height: 8),
                      Text(
                        remaining == every && (loyalty['completed'] as num) > 0
                            ? 'Acabas de completar un ciclo. Te faltan $every servicios para el siguiente beneficio.'
                            : 'Te ${remaining == 1 ? 'falta 1 servicio' : 'faltan $remaining servicios'} para tu próxima tarifa reducida.',
                        style: const TextStyle(color: NetJobColors.subtle),
                      ),
                      const Divider(height: 24),
                      Row(children: [
                        Icon(loyalty['ratingOk'] == true ? Icons.check_circle : Icons.info_outline, size: 18, color: loyalty['ratingOk'] == true ? NetJobColors.mint : NetJobColors.warning),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            (loyalty['ratingCount'] as num) == 0
                                ? 'Aún no tienes calificaciones como cliente. Los profesionales te califican al terminar cada servicio.'
                                : 'Tu calificación como cliente: ${loyalty['ratingAvg']} (${loyalty['ratingCount']} reseñas). Necesitas más de ${loyalty['minRating']}.',
                            style: const TextStyle(fontSize: 13.5),
                          ),
                        ),
                      ]),
                    ]),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(isPro ? 'Invita a otros profesionales' : 'Invita a tus conocidos', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 6),
                    Text(
                      isPro
                          ? 'Cuando un colega se registre con tu código y active su plan, ganas ${b['referralBoostDays']} días de potenciador de recomendación: subes en los resultados de búsqueda.'
                          : 'Tu invitado paga $reduced en su primer servicio. Cuando lo termine, tú ganas un servicio con tarifa reducida.',
                      style: const TextStyle(color: NetJobColors.subtle, height: 1.35),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(color: NetJobColors.cardHigh, borderRadius: BorderRadius.circular(16), border: Border.all(color: NetJobColors.border)),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Text('Tu código', style: TextStyle(color: NetJobColors.muted, fontSize: 12)),
                            SelectableText(code, style: TextStyle(fontFamily: NetJobFonts.display, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 2)),
                          ]),
                        ),
                        IconButton.filledTonal(
                          tooltip: 'Copiar',
                          icon: const Icon(Icons.copy_rounded),
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: code));
                            if (context.mounted) toast(context, 'Código copiado', error: false);
                          },
                        ),
                      ]),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => launchUrl(Uri.https('wa.me', '/', {'text': invite}), mode: LaunchMode.externalApplication),
                        icon: const Icon(Icons.share_rounded),
                        label: const Text('Compartir por WhatsApp'),
                      ),
                    ),
                    const Divider(height: 28),
                    Row(children: [
                      _count('${b['invited']}', 'invitados'),
                      _count('${b['rewarded']}', 'ya te dieron premio'),
                    ]),
                  ]),
                ),
              ),
              if (isPro) ...[
                const SizedBox(height: 14),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.trending_up_rounded, color: NetJobColors.mint),
                    title: const Text('Premios por buen desempeño'),
                    subtitle: const Text('Descuento en tu suscripción y potenciador de recomendación'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/pro/subscription'),
                  ),
                ),
              ],
            ]),
          );
        },
      ),
    );
  }

  Widget _count(String value, String label) => Expanded(
        child: Column(children: [
          Text(value, style: TextStyle(fontFamily: NetJobFonts.display, fontSize: 24, fontWeight: FontWeight.w800)),
          Text(label, style: const TextStyle(color: NetJobColors.subtle, fontSize: 12.5)),
        ]),
      );
}

// ============================ Comprobante de pago ============================

class ReceiptScreen extends StatelessWidget {
  const ReceiptScreen({super.key, required this.paymentId});
  final String paymentId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Comprobante de pago')),
      body: AsyncView<Map>(
        load: () async => await Api.instance.get('/payments/$paymentId/receipt') as Map,
        builder: (context, r, _) {
          final lines = r['lines'] as List;
          Widget row(String label, String? value) => value == null || value.isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 120, child: Text(label, style: const TextStyle(color: NetJobColors.muted, fontSize: 13))),
                    Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
                  ]),
                );
          return ListView(padding: const EdgeInsets.all(16), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.check_circle_rounded, color: NetJobColors.mint, size: 30),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Pago aprobado', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                        Text(fmtDateTime(r['issuedAt']), style: const TextStyle(color: NetJobColors.muted, fontSize: 12.5)),
                      ]),
                    ),
                    Text('NetJob', style: TextStyle(fontFamily: NetJobFonts.display, fontWeight: FontWeight.w800, fontSize: 18, color: NetJobColors.primary)),
                  ]),
                  const Divider(height: 28),
                  Text(r['concept'], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  if (r['detail'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('${r['detail']}', style: const TextStyle(color: NetJobColors.subtle, fontStyle: FontStyle.italic)),
                    ),
                  const SizedBox(height: 12),
                  for (final l in lines) AmountRow(l['label'], '${(l['amount'] as num) < 0 ? '− ' : ''}${cop((l['amount'] as num).abs())}'),
                  const Divider(),
                  AmountRow('Total', cop(r['total']), bold: true),
                  if (r['note'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(children: [
                        const Icon(Icons.local_offer_rounded, size: 15, color: NetJobColors.mint),
                        const SizedBox(width: 6),
                        Expanded(child: Text('${r['note']}', style: const TextStyle(color: NetJobColors.mint, fontSize: 13))),
                      ]),
                    ),
                  const Divider(height: 28),
                  row('Comprobante', r['number']),
                  row('Pagó', r['payer']),
                  row('Profesional', r['professional']),
                  row('Categoría', r['category']),
                  row('Dirección', r['address']),
                  row('Medio de pago', r['paymentMethod'] == 'MOCK' ? 'Pago de prueba' : r['paymentMethod']),
                  row('Transacción', r['transactionId']),
                  row('Estado del dinero', r['payout']),
                  if (r['warrantyDays'] != null)
                    row('Garantía', r['warrantyUntil'] != null ? 'Mano de obra cubierta hasta el ${fmtDate(r['warrantyUntil'])}' : '${r['warrantyDays']} días sobre la mano de obra, desde que el servicio se finaliza'),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Este comprobante es el soporte de tu transacción en NetJob. No reemplaza una factura electrónica.',
              textAlign: TextAlign.center,
              style: TextStyle(color: NetJobColors.muted, fontSize: 12.5),
            ),
            if (r['requestId'] != null) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () => context.push('/requests/${r['requestId']}'),
                icon: const Icon(Icons.assignment_outlined),
                label: const Text('Ver la solicitud'),
              ),
            ],
          ]);
        },
      ),
    );
  }
}
