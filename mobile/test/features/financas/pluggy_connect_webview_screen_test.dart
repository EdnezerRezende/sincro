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

  // These three functions carry the actual fix: the web polling path can never make a genuinely
  // new `financeConnection` row appear (only `finalizeConnection(itemId)`, the native-only path,
  // creates one — the webhook only updates an existing row), so a first connection attempted from
  // the browser can poll forever without ever succeeding. The messaging must say so instead of
  // repeating a generic "try again" that will never come true. Reconnect (at least one connection
  // already existed before the flow started) keeps the original "try again" wording, since that
  // path has a real chance of succeeding once the webhook catches up.
  group('firstConnectionWarning', () {
    test('is null for a reconnect (a connection already existed before opening Pluggy)', () {
      expect(firstConnectionWarning(isFirstConnection: false), isNull);
    });

    test('warns about the app requirement for a first connection, before opening Pluggy', () {
      final aviso = firstConnectionWarning(isFirstConnection: true);
      expect(aviso, isNotNull);
      expect(aviso, contains('aplicativo'));
      expect(aviso, isNot(contains('navegador não recebe')));
    });
  });

  group('tabOpenedMessage', () {
    test('reconnect keeps the plain "come back when done" message', () {
      expect(
        tabOpenedMessage(isFirstConnection: false),
        'Complete a conexão na aba que abrimos. Volte aqui quando terminar.',
      );
    });

    test('first connection also warns it may not confirm automatically', () {
      final mensagem = tabOpenedMessage(isFirstConnection: true);
      expect(mensagem, contains('primeira conexão'));
      expect(mensagem, contains('aplicativo'));
    });
  });

  group('pollNotFoundMessage', () {
    test('reconnect gets the generic "try again in a few seconds" message', () {
      final mensagem = pollNotFoundMessage(isFirstConnection: false);
      expect(mensagem, contains('Concluí a conexão'));
      expect(mensagem, isNot(contains('aplicativo Sincro no celular')));
    });

    test('first connection tells the truth instead of promising a retry will work', () {
      final mensagem = pollNotFoundMessage(isFirstConnection: true);
      expect(mensagem, contains('aplicativo Sincro no celular'));
      // Must NOT be the misleading generic retry copy that started this whole fix.
      expect(mensagem, isNot(contains('Ainda não detectamos uma nova conexão')));
    });

    test('first-connection and reconnect messages are never the same string', () {
      expect(
        pollNotFoundMessage(isFirstConnection: true),
        isNot(pollNotFoundMessage(isFirstConnection: false)),
      );
    });
  });
}
