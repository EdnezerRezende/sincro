import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'email_triage_providers.dart';
import 'gmail_connection_repository.dart';

/// Ação compartilhada de "desconectar o Gmail": diálogo de confirmação, chamada ao repositório,
/// invalidação do status e retorno por SnackBar.
///
/// Extraída de `SettingsScreen` para que a caixa de entrada (onde a pessoa realmente está quando
/// precisa reconectar por falta do escopo `gmail.modify`) ofereça a mesma ação sem duplicar a
/// lógica — uma segunda implementação divergiria com o tempo.
///
/// [setBusy] é opcional: quando informado, é chamado com `true` antes da chamada de rede e com
/// `false` no fim (sucesso ou erro), para a tela que chamou poder desabilitar outros controles
/// enquanto a operação está em andamento. A confirmação em si não conta como "busy" — só a
/// chamada de rede, mesmo padrão já usado em `SettingsScreen`.
///
/// Devolve `true` se a desconexão foi concluída, `false` se a pessoa cancelou ou se houve erro.
Future<bool> confirmarEDesconectarGmail(
  BuildContext context,
  WidgetRef ref, {
  void Function(bool busy)? setBusy,
}) async {
  final confirmado = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Desconectar Gmail?'),
      content: const Text(
        'O resumo da sua caixa de entrada será apagado. Você pode reconectar quando quiser.',
      ),
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
    await ref.read(gmailConnectionRepositoryProvider).disconnect();
    ref.invalidate(gmailConnectionStatusProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gmail desconectado.')),
      );
    }
    return true;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível desconectar o Gmail. Tente novamente.')),
      );
    }
    return false;
  } finally {
    setBusy?.call(false);
  }
}

/// Ação compartilhada de "reconectar o Gmail" (mesmo fluxo usado para conceder um escopo novo,
/// como `gmail.modify`, a uma conexão já existente). Extraída de `_EmailTile` (inbox_screen.dart)
/// para poder ser reaproveitada em qualquer ponto de entrada de reconexão sem duplicar a chamada
/// ao repositório + invalidação do status.
///
/// O consentimento do Google é granular — a pessoa pode desmarcar um escopo específico na tela de
/// login, e o client OAuth pode nem estar aprovado para `gmail.modify` — então o fato de
/// `connect()` não ter lançado NÃO significa que o escopo pedido foi concedido. Por isso esta
/// função relê o status da conexão no backend (a mesma fonte usada por [gmailConnectionStatusProvider])
/// depois de reconectar, em vez de simplesmente devolver sucesso: quem chama decide o que anunciar
/// olhando os campos do [GmailConnectionStatus] devolvido, nunca assumindo escopo concedido.
///
/// Devolve o status relido do backend após a reconexão, ou `null` se a própria reconexão falhou
/// (feedback já mostrado por SnackBar nesse caso).
Future<GmailConnectionStatus?> reconectarGmail(BuildContext context, WidgetRef ref) async {
  try {
    await ref.read(gmailConnectionRepositoryProvider).connect();
    // `.future` força a releitura do status a partir do zero (não do valor em cache que
    // `gmailConnectionStatusProvider` possa ter guardado de antes da reconexão) e devolve o
    // resultado diretamente, para o chamador decidir a mensagem certa sem precisar de um segundo
    // `ref.watch`/`ref.read` separado.
    return await ref.refresh(gmailConnectionStatusProvider.future);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível reconectar. Tente novamente.')),
      );
    }
    return null;
  }
}

/// Reconecta o Gmail via [reconectarGmail] e decide o que fazer depois, olhando o status RELIDO do
/// backend (nunca assumindo sucesso só porque `connect()` não lançou — ver o comentário de
/// [reconectarGmail]). Compartilhada entre todo ponto de entrada que oferece "Reconectar" — o menu
/// da AppBar da caixa de entrada e o SnackBar de "Reconectar" mostrado depois de um 403 ao
/// arquivar/excluir um e-mail — para os dois terem exatamente o mesmo comportamento sem duplicar
/// a lógica de decisão.
///
/// [avisarSucesso] diferencia dois motivos para reconectar:
/// - `true`: a pessoa já estava conectada e pediu para CONCEDER um escopo que faltava (`gmail.modify`)
///   — o conteúdo da caixa de entrada não muda, então não há por que recarregar a lista, mas a
///   pessoa espera uma confirmação explícita de que a permissão foi (ou não) concedida desta vez.
/// - `false`: reconexão "cheia" a partir de desconectado — a caixa de entrada estava vazia por
///   falta de conexão, então precisa recarregar independentemente do escopo concedido; o
///   recarregamento em si já é feedback suficiente, sem SnackBar de sucesso adicional.
Future<void> reconectarGmailEAvisar(
  BuildContext context,
  WidgetRef ref, {
  required bool avisarSucesso,
}) async {
  final status = await reconectarGmail(context, ref);
  if (status == null) return; // erro já mostrado por reconectarGmail

  if (!avisarSucesso) {
    ref.invalidate(emailSummariesProvider);
    return;
  }
  if (!context.mounted) return;

  // Só anuncia sucesso depois de RELER o status e confirmar o escopo — `connect()` não ter
  // lançado não prova que a pessoa concedeu `gmail.modify`: o consentimento do Google é granular
  // e ela pode ter desmarcado esse escopo específico na tela de login.
  if (status.temEscopoModificacao) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Gmail reconectado. Agora você pode arquivar e excluir e-mails por aqui.'),
      ),
    );
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'A conexão foi feita, mas a permissão para arquivar e excluir e-mails não foi '
          'concedida. Você pode tentar de novo e, na tela do Google, deixar essa permissão '
          'marcada.',
        ),
      ),
    );
  }
}
