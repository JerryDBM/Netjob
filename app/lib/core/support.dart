import 'package:url_launcher/url_launcher.dart';

/// WhatsApp Business de soporte de NetJob (formato internacional, sin "+").
const supportWhatsApp = '573027402932';

/// Abre el chat de soporte en WhatsApp con un mensaje inicial. Los profesionales con
/// soporte prioritario (plan Premium) se identifican en el mensaje para atenderlos primero.
Future<void> openSupport({String? message, bool priority = false, String? name}) {
  final text = [
    if (priority) '[Soporte prioritario · Premium]',
    message ?? 'Hola NetJob, necesito ayuda.',
    if (name != null && name.isNotEmpty) '— $name',
  ].join(' ');
  final uri = Uri.https('wa.me', '/$supportWhatsApp', {'text': text});
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
