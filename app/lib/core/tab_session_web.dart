import 'package:web/web.dart' as web;

const _key = 'netjob_tab_token';

/// sessionStorage es propio de cada pestaña y sobrevive a recargar la página.
String? readTabToken() => web.window.sessionStorage.getItem(_key);

void writeTabToken(String? token) {
  if (token == null) {
    web.window.sessionStorage.removeItem(_key);
  } else {
    web.window.sessionStorage.setItem(_key, token);
  }
}
