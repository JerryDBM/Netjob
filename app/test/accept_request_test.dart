import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:netjob/core/api.dart';
import 'package:netjob/core/theme.dart';
import 'package:netjob/features/requests/request_screens.dart';
import 'package:netjob/state/auth_state.dart';
import 'package:netjob/state/location_state.dart';
import 'package:provider/provider.dart';

/// El profesional abre una solicitud pendiente y la acepta.
void main() {
  testWidgets('el profesional puede aceptar una solicitud pendiente', (tester) async {
    await initializeDateFormatting('es');
    final fixture = jsonDecode(File('test/fixtures_pending_request.json').readAsStringSync()) as Map;
    final detail = fixture['detail'] as Map;
    final calls = <String>[];

    final client = MockClient((req) async {
      calls.add('${req.method} ${req.url.path}');
      if (req.method == 'POST' && req.url.path.endsWith('/accept')) {
        return http.Response(jsonEncode({...detail, 'status': 'ACCEPTED', 'stage': 'PAY_DIAGNOSTIC'}), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response(jsonEncode(detail), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    });

    await http.runWithClient(() async {
      final auth = AuthState()..user = {'id': fixture['userId'], 'role': 'PROFESSIONAL', 'name': 'Pro'};
      Api.instance.token = 't';
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => RequestDetailScreen(id: detail['id'])),
      ]);
      await tester.binding.setSurfaceSize(const Size(430, 900));
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: auth),
          ChangeNotifierProvider(create: (_) => LocationState()),
        ],
        child: MaterialApp.router(theme: buildTheme(), routerConfig: router),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Aceptar'), findsOneWidget, reason: 'debe verse el botón Aceptar');
      await tester.tap(find.text('Aceptar'));
      await tester.pumpAndSettle();
      expect(find.text('Aceptar solicitud'), findsOneWidget, reason: 'debe abrirse la confirmación');
      await tester.tap(find.widgetWithText(FilledButton, 'Aceptar').last);
      await tester.pumpAndSettle();
    }, () => client);

    expect(calls, contains('POST /requests/${detail['id']}/accept'));
  });
}
