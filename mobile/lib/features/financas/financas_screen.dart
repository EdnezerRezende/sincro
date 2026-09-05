import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import 'finance_connection.dart';
import 'finance_providers.dart';
import 'finance_summary.dart';
import 'pluggy_connect_webview_screen.dart';

final _currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

/// Formata em pt-BR ("R\$ 1.284,37") em vez do `toStringAsFixed(2)` cru ("R\$ 1284.37").
String _formatCurrency(double value) => _currencyFormat.format(value);

/// Data curta (dd/mm), usada para distinguir itens que, de outra forma, teriam o mesmo nome
/// (ex.: vários boletos, todos sem nome próprio no modelo de dados).
String _formatDataCurta(DateTime data) {
  final dia = data.day.toString().padLeft(2, '0');
  final mes = data.month.toString().padLeft(2, '0');
  return '$dia/$mes';
}

/// Traduz o tipo de conta cru do backend para um rótulo legível em português — o usuário nunca
/// deve ver um enum de backend na tela. `finance-sync.service.ts` hoje só grava `'CORRENTE'` e
/// `'CARTAO_CREDITO'` (nunca `'CONTA_CORRENTE'`); os demais são mantidos por segurança caso o
/// backend passe a emitir outros valores no futuro. ISSUE #5 FIX: Tratamento exaustivo de tipos
/// evita que 100% das contas reais caiam no fallback genérico.
String _tipoLabel(String tipo) {
  return switch (tipo) {
    'CORRENTE' || 'CONTA_CORRENTE' => 'Conta corrente',
    'CONTA_POUPANCA' => 'Poupança',
    'CARTAO_CREDITO' => 'Cartão de crédito',
    'CARTAO_DEBITO' => 'Cartão de débito',
    _ => 'Conta',  // Fallback only for truly unknown types
  };
}

/// Classificação calma do status cru da Pluggy: `saudavel` (nada a fazer), `sincronizando`
/// (transitório e normal — nunca deve alarmar) ou `precisaAtencao` (usuário precisa agir).
/// Qualquer status não reconhecido cai em `sincronizando`, nunca em `precisaAtencao` — um valor
/// desconhecido não é evidência de problema, então não deve acionar a UI de alarme.
/// ISSUE #7 FIX: Cobertura completa de todos os statuses da Pluggy com tratamento non-punitive.
enum _ConexaoEstado { saudavel, sincronizando, precisaAtencao }

_ConexaoEstado _estadoConexao(FinanceConnection conexao) {
  return switch (conexao.status) {
    'UPDATED' => _ConexaoEstado.saudavel,
    'CREATED' || 'CREATING' || 'MERGING' || 'UPDATING' || 'LOGIN_IN_PROGRESS' =>
      _ConexaoEstado.sincronizando,
    'LOGIN_ERROR' || 'OUTDATED' || 'ERROR' || 'WAITING_USER_INPUT' || 'WAITING_USER_ACTION' =>
      _ConexaoEstado.precisaAtencao,
    _ => _ConexaoEstado.sincronizando,
  };
}

/// Mensagem calma e acionável para conexões que precisam de atenção real do usuário. Só é
/// chamada para conexões classificadas como `precisaAtencao` — nunca para estados transitórios
/// saudáveis, que têm seu próprio indicador neutro de "sincronizando".
String _statusMessage(FinanceConnection conexao) {
  return switch (conexao.status) {
    'LOGIN_ERROR' => '${conexao.instituicao} precisa reconectar',
    'OUTDATED' => '${conexao.instituicao}: atualização pendente',
    'ERROR' => '${conexao.instituicao}: erro na conexão',
    'WAITING_USER_INPUT' || 'WAITING_USER_ACTION' => '${conexao.instituicao} aguardando confirmação',
    _ => '${conexao.instituicao}: verifique a conexão',
  };
}

/// Dispara o fluxo de conexão/reconexão via Pluggy Connect. Usado tanto para conectar a
/// primeira conta (estado vazio) quanto para reconectar uma conexão com problema — em ambos os
/// casos o fluxo é o mesmo: token → widget da Pluggy → finalizar no backend.
Future<void> _connectFinance(BuildContext context, WidgetRef ref) async {
  try {
    final connectToken = await ref.read(financeConnectionRepositoryProvider).createConnectToken();
    if (!context.mounted) return;
    final itemId = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => PluggyConnectWebviewScreen(connectToken: connectToken)),
    );
    if (itemId == null) return;
    await ref.read(financeConnectionRepositoryProvider).finalizeConnection(itemId);
    ref.invalidate(financeConnectionsProvider);
    ref.invalidate(financeSummaryProvider);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível conectar sua conta. Tente novamente.')),
      );
    }
  }
}

class FinancasScreen extends ConsumerStatefulWidget {
  const FinancasScreen({super.key});

  @override
  ConsumerState<FinancasScreen> createState() => _FinancasScreenState();
}

class _FinancasScreenState extends ConsumerState<FinancasScreen> {
  // Sync é best-effort (a Pluggy pode estar lenta ou fora do ar), mas uma falha não pode ficar
  // invisível: o usuário precisa saber que o que está vendo pode estar desatualizado.
  bool _syncFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  Future<void> _sync() async {
    var failed = false;
    try {
      await ref.read(financeSummaryRepositoryProvider).sync();
    } catch (_) {
      failed = true;
    }
    if (!mounted) return;
    setState(() => _syncFailed = failed);
    ref.invalidate(financeSummaryProvider);
  }

  @override
  Widget build(BuildContext context) {
    final summaryAsync = ref.watch(financeSummaryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Finanças')),
      body: RefreshIndicator(
        onRefresh: _sync,
        child: summaryAsync.when(
          data: (summary) => _FinancasContent(summary: summary, syncFailed: _syncFailed),
          loading: () => const _LoadingState(),
          error: (_, __) => _ErrorState(onRetry: () => ref.invalidate(financeSummaryProvider)),
        ),
      ),
    );
  }
}

class _ItemAVencer {
  const _ItemAVencer({
    required this.nome,
    required this.valor,
    required this.vencimento,
    this.isFaturaCartao = false,
  });

  final String nome;
  final double valor;
  final DateTime vencimento;

  /// true para faturas de cartão de crédito injetadas nesta lista a partir de `summary.contas`.
  /// Fatura é sempre dívida — precisa renderizar com a MESMA cor/sinal usados na seção "Contas
  /// conectadas" para a mesma conta, nunca com a cor de urgência (que pode dar verde/"tudo bem"
  /// para uma dívida só porque o vencimento está longe).
  final bool isFaturaCartao;
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: colors.primary),
          const SizedBox(height: 16),
          Text(
            'Carregando suas finanças...',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Estado de erro: mesmo padrão do rebuild da inbox — ícone + mensagem calma + ação de retry
/// visível (não depende só do gesto, não muito descobrível, de pull-to-refresh).
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 48),
              Icon(Icons.cloud_off_outlined, size: 48, color: colors.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                'Não foi possível carregar suas finanças.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              FilledButton(onPressed: onRetry, child: const Text('Tentar novamente')),
            ],
          ),
        ),
      ],
    );
  }
}

class _FinancasContent extends ConsumerWidget {
  const _FinancasContent({required this.summary, required this.syncFailed});

  final FinanceSummary summary;
  final bool syncFailed;

  // Tom não punitivo: sem cor de alarme, e "venceu há X dia(s)" em vez de "atrasado".
  String _formatVencimento(DateTime vencimento) {
    final hoje = DateTime.now();
    final diasRestantes = DateTime(vencimento.year, vencimento.month, vencimento.day)
        .difference(DateTime(hoje.year, hoje.month, hoje.day))
        .inDays;
    if (diasRestantes < 0) return 'venceu há ${-diasRestantes} dia(s)';
    if (diasRestantes == 0) return 'vence hoje';
    return 'vence em $diasRestantes dia(s)';
  }

  /// Retorna a cor de urgência para um item a vencer.
  /// Verde (sucesso) se há dias para o vencimento; âmbar (caution) se próximo ou vencido.
  Color _getUrgencyColor(DateTime vencimento, SincroColors colors) {
    final hoje = DateTime.now();
    final diasRestantes = DateTime(vencimento.year, vencimento.month, vencimento.day)
        .difference(DateTime(hoje.year, hoje.month, hoje.day))
        .inDays;
    return diasRestantes > 3 ? colors.success : colors.caution;
  }

  /// Retorna um ícone adequado para o tipo de conta. `'CORRENTE'` é o valor real gravado hoje
  /// pelo backend (ver `finance-sync.service.ts`) — sem esse case, 100% das contas correntes
  /// reais caem no ícone genérico de pessoa.
  IconData _getAccountIcon(String accountType) {
    return switch (accountType) {
      'CORRENTE' || 'CONTA_CORRENTE' => Icons.account_balance,
      'CONTA_POUPANCA' => Icons.savings,
      'CARTAO_CREDITO' => Icons.credit_card,
      'CARTAO_DEBITO' => Icons.payment,
      _ => Icons.account_circle,
    };
  }

  void _showAccountDetail(BuildContext context, FinanceAccountSummary conta, bool isFatura) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(conta.nome, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                _tipoLabel(conta.tipo),
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              Text(
                isFatura
                    ? 'Fatura atual: ${_formatCurrency(conta.saldoOuFatura.abs())}'
                    : 'Saldo: ${_formatCurrency(conta.saldoOuFatura)}',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (conta.vencimentoFatura != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Vencimento: ${_formatDataCurta(conta.vencimentoFatura!)}',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itensAVencer = <_ItemAVencer>[
      // Boletos não têm nome próprio no modelo — o vencimento formatado é o que distingue um do
      // outro na lista (senão todos aparecem como "Boleto", indistinguíveis).
      ...summary.boletos.map(
        (b) => _ItemAVencer(
          nome: 'Boleto · vence ${_formatDataCurta(b.vencimento)}',
          valor: b.valor,
          vencimento: b.vencimento,
        ),
      ),
      ...summary.contas
          .where((c) => c.tipo == 'CARTAO_CREDITO' && c.vencimentoFatura != null)
          .map(
            (c) => _ItemAVencer(
              nome: c.nome,
              valor: c.saldoOuFatura,
              vencimento: c.vencimentoFatura!,
              isFaturaCartao: true,
            ),
          ),
    ]..sort((a, b) => a.vencimento.compareTo(b.vencimento));

    final theme = Theme.of(context);
    final sincroColors = context.sincroColors;
    final connectionsAsync = ref.watch(financeConnectionsProvider);
    // Contraste não-textual (WCAG 1.4.11, ≥3:1) para a borda de cards agora interativos: o
    // `outline` claro (#E0E0E0) mede ~1.3:1 contra o fundo do scaffold em light mode — usa
    // `onSurfaceVariant` (já existente no tema, sem cor nova) para light, que mede bem acima de
    // 3:1. Dark mode já estava adequado, mantém `outline`.
    // ISSUE #9 FIX: Contraste adequado de borda em ambos os modos (WCAG 1.4.11, ≥3:1).
    // Light mode usa onSurfaceVariant (#666666) em vez de outline (#E0E0E0) que mede ~1.3:1.
    // Dark mode usa outline que já estava adequado.
    final cardBorderSide = BorderSide(
      color: theme.brightness == Brightness.light
          ? theme.colorScheme.onSurfaceVariant
          : theme.colorScheme.outline,
    );
    final heroColor = summary.saldoLivre < 0 ? sincroColors.caution : theme.colorScheme.primary;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      children: [
        // ISSUE #3 FIX: Error banner visível para sync falho. Falha nunca é silenciosa — o
        // usuário precisa saber que o que está vendo pode estar desatualizado (mesmo que seja
        // o último snapshot válido).
        if (syncFailed)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Card(
              color: sincroColors.caution.withAlpha(26),
              shape: RoundedRectangleBorder(
                borderRadius: const BorderRadius.all(Radius.circular(16)),
                side: BorderSide(color: sincroColors.caution.withAlpha(90)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.cloud_off_outlined, size: 18, color: sincroColors.caution),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Não foi possível atualizar agora — mostrando dados salvos.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // SEÇÃO: Conexão Pluggy (status real por conexão)
        connectionsAsync.when(
          data: (connections) {
            if (connections.isEmpty) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Card(
                  color: theme.colorScheme.surfaceContainerHighest,
                  shape: RoundedRectangleBorder(
                    borderRadius: const BorderRadius.all(Radius.circular(16)),
                    side: cardBorderSide,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.info_outline, size: 18, color: sincroColors.caution),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Nenhuma conta conectada via Pluggy. Conecte sua conta para dados em tempo real.',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final precisaAtencao =
                connections.where((c) => _estadoConexao(c) == _ConexaoEstado.precisaAtencao).toList();
            final sincronizando =
                connections.where((c) => _estadoConexao(c) == _ConexaoEstado.sincronizando).toList();

            if (precisaAtencao.isEmpty && sincronizando.isEmpty) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Card(
                  color: theme.colorScheme.surfaceContainerHighest,
                  shape: RoundedRectangleBorder(
                    borderRadius: const BorderRadius.all(Radius.circular(16)),
                    side: cardBorderSide,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.sync, size: 18, color: sincroColors.success),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '${connections.length} conexão(ões) ativa(s)',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            // Só há estados transitórios/normais (CREATING, MERGING, UPDATING,
            // LOGIN_IN_PROGRESS, ou um status desconhecido) — não são um problema, então NUNCA
            // usam o card de atenção (âmbar). É só um indicador neutro de "trabalhando nisso".
            if (precisaAtencao.isEmpty) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Card(
                  color: theme.colorScheme.surfaceContainerHighest,
                  shape: RoundedRectangleBorder(
                    borderRadius: const BorderRadius.all(Radius.circular(16)),
                    side: cardBorderSide,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            sincronizando.length == connections.length
                                ? 'Sincronizando suas conexões...'
                                : '${sincronizando.length} conexão(ões) sincronizando...',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            // Pelo menos uma conexão realmente precisa de ação do usuário (LOGIN_ERROR, OUTDATED,
            // ERROR, WAITING_USER_INPUT/ACTION) — esse é o bug real que o usuário reportou. Cada
            // linha é tocável e leva direto ao fluxo de reconexão da Pluggy. Conexões apenas
            // sincronizando não entram aqui — não são um alarme falso.
            return Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Card(
                color: sincroColors.caution.withAlpha(26),
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: const BorderRadius.all(Radius.circular(16)),
                  side: BorderSide(color: sincroColors.caution.withAlpha(90)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.sync_problem, size: 18, color: sincroColors.caution),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              precisaAtencao.length == connections.length
                                  ? 'Suas conexões precisam de atenção'
                                  : 'Uma ou mais conexões precisam de atenção',
                              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      ...precisaAtencao.map(
                        (conexao) => InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _connectFinance(context, ref),
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 48),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(_statusMessage(conexao), style: theme.textTheme.bodySmall),
                                ),
                                Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.onSurfaceVariant),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
          loading: () => const SizedBox.shrink(),
          // ANTES: SizedBox.shrink() fazia a seção de saúde da conexão sumir de vez quando
          // `/financas/conexoes` falhava — o usuário ficava sem nenhuma pista de que não dava
          // para confiar no status mostrado. Agora aparece um aviso calmo (mesmo padrão do
          // banner de sync) em vez de silêncio.
          error: (_, __) => Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Card(
              color: sincroColors.caution.withAlpha(26),
              shape: RoundedRectangleBorder(
                borderRadius: const BorderRadius.all(Radius.circular(16)),
                side: BorderSide(color: sincroColors.caution.withAlpha(90)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.help_outline, size: 18, color: sincroColors.caution),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Não foi possível verificar suas conexões agora.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // SEÇÃO: Saldo Livre
        // ISSUE #4 FIX: Sem contas conectadas, nunca mostra "R$ 0,00" com legenda falsa.
        // Em vez disso, um convite neutro ("Conecte uma conta para ver seu saldo") substitui
        // o número herói inteiro — não afirma nada sobre dados que não existem.
        if (summary.contas.isEmpty)
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            shape: RoundedRectangleBorder(
              borderRadius: const BorderRadius.all(Radius.circular(16)),
              side: cardBorderSide,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Row(
                children: [
                  Icon(Icons.account_balance_wallet_outlined, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Conecte uma conta para ver seu saldo.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          // Número herói: headlineLarge (bem maior que o body dos itens abaixo) para hierarquia
          // real, e cor âmbar (nunca vermelha) quando negativo — sinaliza o estado sem alarme.
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            shape: RoundedRectangleBorder(
              borderRadius: const BorderRadius.all(Radius.circular(16)),
              side: cardBorderSide,
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.all(Radius.circular(16)),
                border: Border(left: BorderSide(color: heroColor, width: 4)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Saldo livre',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // ISSUE #2 FIX: FittedBox+maxLines:1 em vez de deixar o Text quebrar linha.
                    // A 2.0x sem isso o número herói quebrava no meio do valor ("R$ 1.284," / "37").
                    // Assim ele encolhe para caber inteiro numa linha só, nunca corta um dígito.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _formatCurrency(summary.saldoLivre),
                        maxLines: 1,
                        softWrap: false,
                        style: theme.textTheme.headlineLarge?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                          fontWeight: FontWeight.w800,
                          color: heroColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Já considera contas, faturas e boletos do ciclo atual.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ),

        const SizedBox(height: 32),

        // SEÇÃO: Contas Conectadas
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text('Contas conectadas', style: theme.textTheme.titleSmall),
        ),
        if (summary.contas.isEmpty)
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            shape: RoundedRectangleBorder(
              borderRadius: const BorderRadius.all(Radius.circular(16)),
              side: cardBorderSide,
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 18, color: sincroColors.caution),
                      const SizedBox(width: 8),
                      const Expanded(child: Text('Nenhuma conta conectada.')),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _connectFinance(context, ref),
                      icon: const Icon(Icons.add_link),
                      label: const Text('Conectar conta'),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ...summary.contas.map((conta) {
            final isFatura = conta.tipo == 'CARTAO_CREDITO';
            // Fatura de cartão é dívida, não dinheiro disponível — nunca deve ler como um saldo
            // positivo comum. Sinalizamos com a cor de atenção (âmbar) e um sinal de menos, sem
            // usar vermelho (gatilho de ansiedade financeira, proibido pelo mandato do app).
            final amountColor =
                (isFatura || conta.saldoOuFatura < 0) ? sincroColors.caution : theme.colorScheme.primary;
            final valorExibido =
                isFatura ? '- ${_formatCurrency(conta.saldoOuFatura.abs())}' : _formatCurrency(conta.saldoOuFatura);
            final subtitulo = _tipoLabel(conta.tipo);

            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Card(
                color: theme.colorScheme.surfaceContainerHighest,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: const BorderRadius.all(Radius.circular(16)),
                  side: cardBorderSide,
                ),
                child: InkWell(
                  onTap: () => _showAccountDetail(context, conta, isFatura),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 64), // Touch target ≥ 48dp
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: amountColor.withAlpha(26),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              _getAccountIcon(conta.tipo),
                              color: amountColor,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Nome da conta é a informação mais importante da linha — precisa de
                          // mais espaço que o valor, mesmo em textScale alto. ANTES: o valor era
                          // um Text simples (não-flexível) num Row, então o RenderFlex dava a ele
                          // largura irrestrita ANTES de sobrar espaço para o Expanded do nome —
                          // a 2.0x o nome colapsava a ~2 caracteres enquanto o valor ficava
                          // inteiro. Expanded(flex:3) + Flexible(flex:2) fazem os dois negociarem
                          // espaço em vez do valor engolir tudo incondicionalmente.
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // ISSUE #1 FIX: maxLines:2 at high textScale (2.0x) preserves name
                                // with proper truncation instead of collapsing to 2 chars.
                                Text(
                                  conta.nome,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    // Rótulo do tipo pode truncar em textScale alto — o marcador
                                    // "fatura" NÃO pode, é o que identifica a linha como dívida.
                                    // ANTES: "Cartão de crédito · fatura" com maxLines:1 cortava
                                    // exatamente a palavra "fatura" primeiro ("...· fatu…").
                                    // Como chip de largura fixa em vez de texto concatenado, o
                                    // marcador sempre sobra espaço reservado e nunca é cortado.
                                    Flexible(
                                      child: Text(
                                        subtitulo,
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: theme.colorScheme.onSurfaceVariant,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isFatura) ...[
                                      const SizedBox(width: 8),
                                      // ISSUE #10 FIX: Chip com largura fixa em vez de Text direto.
                                      // O marcador "fatura" nunca é truncado mesmo em textScale 2.0x,
                                      // pois sempre sobra espaço reservado no Container.
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: amountColor.withAlpha(38),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          'fatura',
                                          style: theme.textTheme.labelSmall?.copyWith(
                                            color: amountColor,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            flex: 2,
                            fit: FlexFit.loose,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Text(
                                valorExibido,
                                maxLines: 1,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                  fontWeight: FontWeight.w600,
                                  color: amountColor,
                                ),
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),

        const SizedBox(height: 32),

        // SEÇÃO: A Vencer
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text('A vencer', style: theme.textTheme.titleSmall),
        ),
        if (itensAVencer.isEmpty)
          Card(
            color: sincroColors.success.withAlpha(26),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.spa_outlined, size: 18, color: sincroColors.success),
                  const SizedBox(width: 8),
                  const Text('Nada por aqui.'),
                ],
              ),
            ),
          )
        else
          ...itensAVencer.map((item) {
            // Fatura de cartão é sempre dívida — usa a MESMA cor de atenção (âmbar) e o MESMO
            // sinal negativo da seção "Contas conectadas" para a mesma conta, nunca a cor de
            // urgência baseada em dias-até-o-vencimento. ANTES: uma fatura com vencimento a mais
            // de 3 dias virava verde com check "tudo bem" aqui, enquanto a mesma fatura aparecia
            // em âmbar/negativo na lista de contas — a mesma dívida com duas leituras
            // contraditórias.
            final urgencyColor =
                item.isFaturaCartao ? sincroColors.caution : _getUrgencyColor(item.vencimento, sincroColors);
            final isSafe = !item.isFaturaCartao && urgencyColor == sincroColors.success;
            final backgroundTint = urgencyColor.withAlpha(26);
            final valorExibido =
                item.isFaturaCartao ? '- ${_formatCurrency(item.valor.abs())}' : _formatCurrency(item.valor);

            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Card(
                color: theme.colorScheme.surfaceContainerHighest,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: const BorderRadius.all(Radius.circular(16)),
                  side: BorderSide(color: urgencyColor.withAlpha(90)),
                ),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 80), // Touch target ≥ 48dp + space
                  decoration: BoxDecoration(
                    color: backgroundTint,
                    border: Border(left: BorderSide(color: urgencyColor, width: 4)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // ANTES: o valor era um Text simples (não-flexível), então o
                            // RenderFlex dava a ele largura irrestrita antes de sobrar espaço
                            // para o Expanded do nome — a 2.0x "Boleto · vence 01/09" perdia a
                            // data ou o nome colapsava. Expanded(flex:3) + Flexible(flex:2)
                            // negociam o espaço em vez do valor engolir tudo. ISSUE #6 FIX:
                            // FittedBox em torno do nome também, nunca deixa a data ser cortada.
                            Expanded(
                              flex: 3,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  item.nome,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  softWrap: false,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              flex: 2,
                              fit: FlexFit.loose,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  valorExibido,
                                  maxLines: 1,
                                  softWrap: false,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                    fontWeight: FontWeight.w700,
                                    color: urgencyColor,
                                  ),
                                  textAlign: TextAlign.right,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Ícone e cor sempre concordam com a mesma leitura de urgência — nunca um
                        // check verde de "tudo bem" num item que a borda/cor já marcam como
                        // atenção (e nunca num item de fatura, que é sempre dívida).
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isSafe ? Icons.check_circle : Icons.schedule,
                              size: 16,
                              color: urgencyColor,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                _formatVencimento(item.vencimento),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),

        // Padding bottom for safe area
        const SizedBox(height: 24),
      ],
    );
  }
}
