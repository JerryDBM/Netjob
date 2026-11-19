import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'router.dart';
import 'state/auth_state.dart';
import 'state/location_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es');
  final auth = AuthState();
  await auth.restore();
  runApp(NetJobApp(auth: auth));
}

class NetJobApp extends StatefulWidget {
  const NetJobApp({super.key, required this.auth});
  final AuthState auth;

  @override
  State<NetJobApp> createState() => _NetJobAppState();
}

class _NetJobAppState extends State<NetJobApp> {
  late final GoRouter _router = buildRouter(widget.auth);
  final _location = LocationState();

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.auth),
        ChangeNotifierProvider.value(value: _location),
      ],
      child: MaterialApp.router(
        title: 'NetJob',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        routerConfig: _router,
        locale: const Locale('es', 'CO'),
        supportedLocales: const [Locale('es', 'CO'), Locale('es')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      ),
    );
  }
}
