import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'finance_connection.dart';
import 'finance_providers.dart';

/// Ação compartilhada de "desconectar uma conexão de Finanças": diálogo de confirmação, chamada
/// ao repositório, invalidação da lista de conexões e retorno por SnackBar.
///
/// Extraída de `SettingsScreen` para que a tela de Finanças (onde cada instituição já aparece
/// listada) ofereça a mesma ação sem duplicar a lógica — uma segunda implementação divergiria com
/// o tempo.
///
/// [setBusy] é opcional: quando informado, é chamado com `true` antes da chamada de rede e com
/// `false` no fim (sucesso ou erro), mesmo padrão já usado em `SettingsScreen`.
///
/// Devolve `true` se a desconexão foi concluída, `false` se a pessoa cancelou ou se houve erro.
Future<bool> confirmarEDesconectarFinanceConnection(
  BuildContext context,
  WidgetRef ref,
  FinanceConnection connection, {
  void Function(bool busy)? setBusy,
}) async {
  final confirmado = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Desconectar ${connection.instituicao}?'),
      content: const Text('Os dados dessa conexão serão apagados. Você pode reconectar quando quiser.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Desconectar'),
        ),
      ],
    ),
  );
  if (confirmado != true) return false;

  setBusy?.call(true);
  try {
    await ref.read(financeConnectionRepositoryProvider).disconnect(connection.id);
    ref.invalidate(financeConnectionsProvider);
    ref.invalidate(financeSummaryProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${connection.instituicao} desconectado.')),
      );
    }
    return true;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível desconectar. Tente novamente.')),
      );
    }
    return false;
  } finally {
    setBusy?.call(false);
  }
}
