/**
 * Envío de correos. En desarrollo solo se registra en consola.
 * Para producción conectar un proveedor (SES, SendGrid, Resend…) implementando sendMail.
 */
export async function sendMail(to: string, subject: string, text: string): Promise<void> {
  console.log(`[mail] para=${to} asunto="${subject}"\n${text}`);
}
