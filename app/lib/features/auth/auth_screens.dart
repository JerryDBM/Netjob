import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../state/auth_state.dart';
import '../../widgets/auth_design.dart';
import '../../widgets/common.dart';
import '../../widgets/place_picker.dart';

/// Estructura común: fondo con burbujas, logo, título grande y lema espaciado.
class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({required this.title, required this.subtitle, required this.children, this.logoSize = 150, this.showBack = false});
  final String title;
  final String subtitle;
  final List<Widget> children;
  final double logoSize;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuthBackground(
        child: SafeArea(
          child: Stack(children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(26, 24, 26, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: StaggeredColumn(children: [
                    Center(child: Hero(tag: 'netjob-logo', child: NetJobLogo(size: logoSize))),
                    SizedBox(height: logoSize * 0.28),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: NetJobFonts.display, fontSize: 36, fontWeight: FontWeight.w800, color: NetJobColors.ink, letterSpacing: -0.6),
                    ),
                    const SizedBox(height: 8),
                    SpacedText(subtitle),
                    const SizedBox(height: 32),
                    ...children,
                  ]),
                ),
              ),
            ),
            if (showBack)
              Positioned(
                left: 8,
                top: 8,
                child: IconButton(
                  style: IconButton.styleFrom(backgroundColor: const Color(0xD9FCFBF6), side: const BorderSide(color: NetJobColors.border)),
                  icon: const Icon(Icons.arrow_back_rounded, color: NetJobColors.ink),
                  onPressed: () => context.canPop() ? context.pop() : context.go('/login'),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// "¿No tienes cuenta? Regístrate" y similares.
class _SwitchLink extends StatelessWidget {
  const _SwitchLink(this.question, this.action, this.onTap);
  final String question;
  final String action;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(question, style: const TextStyle(color: NetJobColors.muted, fontSize: 15)),
        TextButton(
          onPressed: onTap,
          child: Text(action, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: NetJobColors.primary)),
        ),
      ]);
}

const _footer = Padding(
  padding: EdgeInsets.only(top: 22),
  child: SpacedText('CONECTA  •  CONTRATA  •  CRECE', size: 12.5, spacing: 3),
);

// ============================ Iniciar sesión ============================

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  bool _remember = true;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await context.read<AuthState>().login(_email.text.trim(), _password.text, remember: _remember);
    } catch (e) {
      if (mounted) toast(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Bienvenido de nuevo',
      subtitle: 'Inicia sesión para continuar',
      children: [
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(children: [
              GlassField(
                child: TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(hintText: 'Correo electrónico', prefixIcon: Icon(Icons.person_outline_rounded)),
                  validator: (v) => v != null && v.contains('@') ? null : 'Ingresa un correo válido',
                ),
              ),
              const SizedBox(height: 16),
              GlassField(
                child: TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  autofillHints: const [AutofillHints.password],
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    hintText: 'Contraseña',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      icon: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, key: ValueKey(_obscure)),
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) => v != null && v.isNotEmpty ? null : 'Ingresa tu contraseña',
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 14),
        Row(children: [
          GestureDetector(
            onTap: () => setState(() => _remember = !_remember),
            child: Row(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: _remember ? NetJobColors.gradient : null,
                  color: _remember ? null : const Color(0xD9FCFBF6),
                  border: Border.all(color: _remember ? Colors.transparent : const Color(0x591B4332), width: 1.5),
                ),
                child: _remember ? const Icon(Icons.check_rounded, color: NetJobColors.onPrimary, size: 18) : null,
              ),
              const SizedBox(width: 10),
              const Text('Recordarme', style: TextStyle(fontSize: 15, color: NetJobColors.ink)),
            ]),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => context.push('/forgot'),
            child: const Text('¿Olvidaste tu contraseña?', style: TextStyle(fontWeight: FontWeight.w700, color: NetJobColors.primary)),
          ),
        ]),
        const SizedBox(height: 18),
        GradientButton(label: 'Iniciar sesión', loading: _loading, onPressed: _submit),
        const SizedBox(height: 18),
        _SwitchLink('¿No tienes cuenta?', 'Regístrate', () => context.push('/register')),
        _footer,
      ],
    );
  }
}

// ============================ Registro ============================

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _referral = TextEditingController();
  String? _department;
  String? _city;
  String _role = 'CLIENT';
  bool _loading = false;
  bool _obscure = true;
  bool _tried = false;

  Future<void> _submit() async {
    setState(() => _tried = true);
    final ok = _form.currentState!.validate();
    if (!ok || _department == null || _city == null) return;
    setState(() => _loading = true);
    try {
      await context.read<AuthState>().register({
        'name': _name.text.trim(),
        'email': _email.text.trim(),
        'password': _password.text,
        'role': _role,
        'phone': _phone.text.replaceAll(RegExp(r'\D'), ''),
        'department': _department,
        'city': _city,
        if (_referral.text.trim().isNotEmpty) 'referralCode': _referral.text.trim().toUpperCase(),
      });
    } catch (e) {
      if (mounted) toast(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _roleCard(String value, IconData icon, String title, String desc) {
    final selected = _role == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _role = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: selected ? NetJobColors.gradient : null,
            color: selected ? null : const Color(0xD9FCFBF6),
            border: Border.all(color: selected ? Colors.transparent : NetJobColors.border, width: 1.2),
            boxShadow: [
              BoxShadow(color: selected ? const Color(0x331B4332) : const Color(0x14000000), blurRadius: selected ? 24 : 16, offset: const Offset(0, 8)),
            ],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: selected ? NetJobColors.onPrimary : NetJobColors.primary, size: 28),
            const SizedBox(height: 10),
            Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: selected ? NetJobColors.onPrimary : NetJobColors.ink)),
            const SizedBox(height: 3),
            Text(desc, style: TextStyle(fontSize: 12.5, color: selected ? const Color(0xB3F8F6EE) : NetJobColors.subtle)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Crea tu cuenta',
      subtitle: '¿Cómo quieres usar NetJob?',
      logoSize: 104,
      showBack: true,
      children: [
        Row(children: [
          _roleCard('CLIENT', Icons.person_search_rounded, 'Necesito un servicio', 'Busca y contrata profesionales'),
          const SizedBox(width: 14),
          _roleCard('PROFESSIONAL', Icons.engineering_rounded, 'Ofrezco servicios', 'Consigue clientes y gestiona tu trabajo'),
        ]),
        const SizedBox(height: 22),
        Form(
          key: _form,
          child: Column(children: [
            GlassField(
              child: TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(hintText: 'Nombre completo', prefixIcon: Icon(Icons.person_outline_rounded)),
                validator: (v) => (v ?? '').trim().length >= 2 ? null : 'Ingresa tu nombre',
              ),
            ),
            const SizedBox(height: 14),
            GlassField(
              child: TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(hintText: 'Correo electrónico', prefixIcon: Icon(Icons.mail_outline_rounded)),
                validator: (v) => (v ?? '').contains('@') ? null : 'Ingresa un correo válido',
              ),
            ),
            const SizedBox(height: 14),
            GlassField(
              child: TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                decoration: const InputDecoration(
                  hintText: 'Celular',
                  prefixIcon: Icon(Icons.phone_iphone_rounded),
                  prefixText: '+57  ',
                  prefixStyle: TextStyle(color: NetJobColors.ink, fontWeight: FontWeight.w700, fontSize: 16),
                ),
                validator: (v) => RegExp(r'^3\d{9}$').hasMatch(v ?? '') ? null : 'Ingresa tu celular: 10 dígitos que empiezan por 3',
              ),
            ),
            const SizedBox(height: 14),
            DepartmentCityPicker(
              department: _department,
              city: _city,
              showErrors: _tried,
              decorate: (w) => GlassField(child: w),
              onChanged: (d, c) => setState(() {
                _department = d;
                _city = c;
              }),
            ),
            const SizedBox(height: 14),
            GlassField(
              child: TextFormField(
                controller: _password,
                obscureText: _obscure,
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: 'Contraseña (mínimo 8 caracteres)',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (v) => (v ?? '').length >= 8 ? null : 'Mínimo 8 caracteres',
              ),
            ),
            const SizedBox(height: 14),
            GlassField(
              child: TextFormField(
                controller: _referral,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: 'Código de invitación (opcional)',
                  prefixIcon: const Icon(Icons.card_giftcard_rounded),
                  helperText: _role == 'CLIENT' ? 'Si te invitaron, tu primer servicio paga solo 1 % de tarifa' : null,
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 24),
        GradientButton(label: 'Crear cuenta', loading: _loading, onPressed: _submit),
        const SizedBox(height: 14),
        const Text(
          'Al registrarte aceptas los Términos y la Política de tratamiento de datos de NetJob.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: NetJobColors.muted),
        ),
        _SwitchLink('¿Ya tienes cuenta?', 'Inicia sesión', () => context.canPop() ? context.pop() : context.go('/login')),
        _footer,
      ],
    );
  }
}

// ============================ Recuperar contraseña ============================

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _sent = false;
  bool _loading = false;

  Future<void> _run(Future<void> Function() fn) async {
    setState(() => _loading = true);
    try {
      await fn();
    } catch (e) {
      if (mounted) toast(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Recupera tu acceso',
      subtitle: _sent ? 'Ingresa el código y tu nueva clave' : 'Te enviaremos un código',
      logoSize: 110,
      showBack: true,
      children: [
        GlassField(
          child: TextField(
            controller: _email,
            enabled: !_sent,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(hintText: 'Correo electrónico', prefixIcon: Icon(Icons.mail_outline_rounded)),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          child: !_sent
              ? const SizedBox(width: double.infinity)
              : Column(children: [
                  const SizedBox(height: 14),
                  GlassField(
                    child: TextField(
                      controller: _code,
                      decoration: const InputDecoration(hintText: 'Código de recuperación', prefixIcon: Icon(Icons.pin_outlined)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  GlassField(
                    child: TextField(
                      controller: _password,
                      obscureText: true,
                      decoration: const InputDecoration(hintText: 'Nueva contraseña (mín. 8)', prefixIcon: Icon(Icons.lock_outline_rounded)),
                    ),
                  ),
                ]),
        ),
        const SizedBox(height: 24),
        GradientButton(
          label: _sent ? 'Cambiar contraseña' : 'Enviar código',
          loading: _loading,
          onPressed: () => _run(() async {
            if (!_sent) {
              final r = await Api.instance.post('/auth/forgot-password', {'email': _email.text.trim()});
              // En desarrollo el backend devuelve el código para poder probar sin correo real
              if (r['devToken'] != null) _code.text = r['devToken'];
              setState(() => _sent = true);
            } else {
              await Api.instance.post('/auth/reset-password', {'token': _code.text.trim(), 'password': _password.text});
              if (!context.mounted) return;
              toast(context, 'Contraseña actualizada. Ya puedes iniciar sesión.', error: false);
              context.canPop() ? context.pop() : context.go('/login');
            }
          }),
        ),
        _footer,
      ],
    );
  }
}
