import 'package:flutter_test/flutter_test.dart';
import 'package:netjob/core/format.dart';

void main() {
  test('formato de pesos colombianos', () {
    expect(cop(103000), r'$103.000');
    expect(cop(3000), r'$3.000');
    expect(cop(null), '—');
  });

  test('etiquetas de estado de solicitud', () {
    expect(statusLabel['IN_PROGRESS'], 'En proceso');
    expect(statusLabel.length, 6);
  });
}
