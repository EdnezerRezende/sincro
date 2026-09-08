import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/financas/finance_connection.dart';
import 'package:sincro_mobile/features/financas/pluggy_connect_webview_screen.dart';

// PluggyConnectWebviewScreen forks its whole implementation on `kIsWeb`. That constant is
// compile-time false when running under `flutter test` (a Dart VM test), so the widget's actual
// `kIsWeb` branch (no WebViewController, poll `/financas/conexoes` instead) can't be exercised by
// pushing the widget in a normal widget test here — it would only ever hit the native branch,
// which itself needs a real webview platform channel that isn't registered in this environment.
//
// What *can* be verified on the VM, with no platform channel involved at all, is the pure
// decision at the heart of the web success-detection path: "did a connection that wasn't in the
// snapshot taken before opening Pluggy Connect show up in the snapshot taken after?". That's
// `newConnectionIds`, extracted specifically so it doesn't need a browser to test.
void main() {
  FinanceConnection conn(String id) => FinanceConnection(id: id, instituicao: 'Banco Teste', status: 'UPDATED');

  group('newConnectionIds', () {
    test('empty diff when nothing new appeared', () {
      final before = {'conn-1', 'conn-2'};
      final depois = [conn('conn-1'), conn('conn-2')];

      expect(newConnectionIds(before, depois), isEmpty);
    });

    test('detects a brand-new connection id that appeared after opening Pluggy', () {
      final before = {'conn-1'};
      final depois = [conn('conn-1'), conn('conn-2')];

      expect(newConnectionIds(before, depois), {'conn-2'});
    });

    test('first-ever connection: before is empty, after has one', () {
      final before = <String>{};
      final depois = [conn('conn-1')];

      expect(newConnectionIds(before, depois), {'conn-1'});
    });

    test('no connections before or after stays empty (nothing to detect yet)', () {
      expect(newConnectionIds(<String>{}, const []), isEmpty);
    });

    test('a connection disappearing (e.g. disconnected elsewhere) is not treated as "new"', () {
      final before = {'conn-1', 'conn-2'};
      final depois = [conn('conn-1')];

      expect(newConnectionIds(before, depois), isEmpty);
    });
  });
}
