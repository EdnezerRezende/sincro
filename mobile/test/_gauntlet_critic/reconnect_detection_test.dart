import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/financas/finance_connection.dart';
import 'package:sincro_mobile/features/financas/pluggy_connect_webview_screen.dart';

// Hostile-reviewer edge case for the web Pluggy Connect flow: a RECONNECT of an
// already-existing broken connection (e.g. status LOGIN_ERROR -> UPDATED after the
// user redoes login on connect.pluggy.ai). The connection's `id` never changes across
// a reconnect -- only its `status` field does. This actually EXERCISES
// newConnectionIds() (the real production function, not a reimplementation) with a
// same-id/different-status before/after pair, the exact shape a reconnect produces.
void main() {
  test('EDGE CASE: reconnect (same id, status only changes) is INVISIBLE to newConnectionIds', () {
    final before = {'conn-broken-1'};
    final after = [
      const FinanceConnection(id: 'conn-broken-1', instituicao: 'Banco Teste', status: 'UPDATED'),
    ];

    final detected = newConnectionIds(before, after);

    // This is what the widget's own poll loop checks to decide "success". For a
    // reconnect, it is always empty -- structurally, by definition of the diff -- no
    // matter what status the connection ends up in on the backend.
    expect(detected, isEmpty,
        reason: 'newConnectionIds only diffs by id; a same-id status change can never '
            'appear here, so _checkForNewConnection() can never fire "success" for a '
            'reconnect on web, regardless of backend state.');
  });

  test('control: a genuinely new id next to an unchanged existing one IS detected', () {
    final before = {'conn-broken-1'};
    final after = [
      const FinanceConnection(id: 'conn-broken-1', instituicao: 'Banco Teste', status: 'LOGIN_ERROR'),
      const FinanceConnection(id: 'conn-new-2', instituicao: 'Banco Teste 2', status: 'UPDATED'),
    ];

    expect(newConnectionIds(before, after), {'conn-new-2'});
  });
}
