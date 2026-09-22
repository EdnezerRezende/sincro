import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'finance_providers.dart';
import 'lancamento_financeiro.dart';
import '../calendar/calendar_providers.dart';

class NovoLancamentoScreen extends ConsumerStatefulWidget {
  const NovoLancamentoScreen({super.key, this.existente});

  /// Quando não-nulo, a tela edita este lançamento em vez de criar um novo,
  /// e ganha um botão de excluir.
  final LancamentoFinanceiro? existente;

  @override
  ConsumerState<NovoLancamentoScreen> createState() =>
      _NovoLancamentoScreenState();
}

class _NovoLancamentoScreenState extends ConsumerState<NovoLancamentoScreen> {
  late final TextEditingController _descricaoController;
  late final TextEditingController _valorController;
  late TipoLancamento _tipo;
  late DateTime _dataVencimento;
  String? _contaOuCartaoId;
  late bool _isPago;
  bool _isSaving = false;
  String? _valorErro;

  // Snapshot dos valores iniciais, usado por `_temAlteracoes` para saber se o
  // usuário mexeu em algo e, se sim, confirmar antes de descartar ao voltar.
  late final String _descricaoInicial;
  late final String _valorInicial;
  late final TipoLancamento _tipoInicial;
  late final DateTime _dataVencimentoInicial;
  late final String? _contaOuCartaoIdInicial;
  late final bool _isPagoInicial;

  bool get _editando => widget.existente != null;

  /// Lançamentos vindos do parser de e-mail chegam com status PENDENTE_REVISAO.
  /// Quando o usuário chega aqui a partir da sheet de confirmação (ver
  /// `confirmar_lancamento_sheet.dart`), esta tela é quem realmente confirma
  /// (PATCH .../confirmar) ao salvar — a sheet em si não fala mais com a API.
  bool get _pendenteRevisao =>
      widget.existente?.status == StatusLancamento.pendenteRevisao;

  bool get _temAlteracoes =>
      _descricaoController.text != _descricaoInicial ||
      _valorController.text != _valorInicial ||
      _tipo != _tipoInicial ||
      !_mesmoDia(_dataVencimento, _dataVencimentoInicial) ||
      _contaOuCartaoId != _contaOuCartaoIdInicial ||
      _isPago != _isPagoInicial;

  /// Compara apenas a data de calendário (ano/mês/dia), ignorando hora e o "tipo" do
  /// `DateTime` (UTC vs local): `showDatePicker` sempre devolve uma instância local à meia-
  /// noite, enquanto um lançamento vindo do servidor chega em UTC — sem isto, escolher de
  /// volta o MESMO dia no picker marcava a tela como alterada, porque os dois `DateTime`
  /// representam instantes diferentes mesmo descrevendo o mesmo dia.
  bool _mesmoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  void initState() {
    super.initState();
    final existente = widget.existente;
    _descricaoController = TextEditingController(
      text: existente?.descricao ?? '',
    );
    _valorController = TextEditingController(
      text: _formatarValorParaCampo(existente?.valor),
    );
    _tipo = existente?.tipo ?? TipoLancamento.despesa;
    _dataVencimento = existente?.dataVencimento ?? DateTime.now();
    _contaOuCartaoId = existente?.contaId;
    _isPago = existente?.isPago ?? false;

    _descricaoInicial = _descricaoController.text;
    _valorInicial = _valorController.text;
    _tipoInicial = _tipo;
    _dataVencimentoInicial = _dataVencimento;
    _contaOuCartaoIdInicial = _contaOuCartaoId;
    _isPagoInicial = _isPago;

    // `canPop` do PopScope é lido no `build`, e digitar num TextField NÃO rebuilda a tela —
    // sem isto, o guard de descarte ficaria congelado no estado "sem alterações" e o back
    // sairia sem perguntar mesmo com texto editado. Os outros campos já passam por setState.
    _descricaoController.addListener(_sincronizarGuardDeDescarte);
    _valorController.addListener(_sincronizarGuardDeDescarte);
  }

  bool _guardAtivo = false;

  void _sincronizarGuardDeDescarte() {
    final agora = _temAlteracoes;
    if (agora != _guardAtivo) setState(() => _guardAtivo = agora);
  }

  @override
  void dispose() {
    _descricaoController.removeListener(_sincronizarGuardDeDescarte);
    _valorController.removeListener(_sincronizarGuardDeDescarte);
    _descricaoController.dispose();
    _valorController.dispose();
    super.dispose();
  }

  /// Precisa produzir o mesmo formato que `_normalizarValor` espera ler de volta (vírgula como
  /// separador decimal, sem separador de milhar) — `valor.toString()` usava ponto (ex.: "100.0"),
  /// que a leitura tratava como separador de milhar e descartava, inflando 100,00 para 1000,00
  /// ao editar e salvar um lançamento sem sequer tocar no campo de valor.
  String _formatarValorParaCampo(double? valor) {
    if (valor == null) return '';
    return valor.toStringAsFixed(2).replaceAll('.', ',');
  }

  /// Normaliza um texto de valor (podendo trazer prefixo "R$", espaços, separador de milhar
  /// em ponto ou vírgula) para o formato que `double.tryParse` entende.
  ///
  /// Regra: se a última pontuação for vírgula, ela é o separador decimal (pontos antes dela são
  /// milhar: "1.234,56" -> 1234.56). Sem vírgula, um único ponto seguido de 1 ou 2 dígitos é
  /// decimal ("10.5" -> 10.5, "1234.56" -> 1234.56) — grupo de milhar tem SEMPRE 3 dígitos, então
  /// um ponto seguido de exatamente 3 dígitos é separador de milhar ("1.234" -> 1234), e mais de
  /// um ponto sem vírgula significa que todos são milhar ("1.234.567" -> 1234567).
  double? _normalizarValor(String bruto) {
    final limpo = bruto.replaceAll(RegExp(r'[^0-9,.]'), '');
    if (limpo.isEmpty) return null;
    final ultimaVirgula = limpo.lastIndexOf(',');
    final ultimoPonto = limpo.lastIndexOf('.');
    String normalizado;
    if (ultimaVirgula > ultimoPonto) {
      normalizado = limpo.replaceAll('.', '').replaceFirst(',', '.');
    } else if (ultimoPonto != -1) {
      final totalPontos = '.'.allMatches(limpo).length;
      final digitosApos = limpo.length - ultimoPonto - 1;
      final ehDecimal =
          totalPontos == 1 && (digitosApos == 1 || digitosApos == 2);
      normalizado = ehDecimal ? limpo : limpo.replaceAll('.', '');
    } else {
      normalizado = limpo;
    }
    return double.tryParse(normalizado);
  }

  /// Valida o campo de valor antes de salvar. Um texto que não parseia para um número (ex.:
  /// digitação inválida) é erro em qualquer lançamento; um campo vazio é erro quando o
  /// lançamento está pendente de revisão (confirmar sem valor não faz sentido) ou quando já
  /// está CONFIRMADO (apagar o valor de algo confirmado e salvar não pode fechar a tela como
  /// se tivesse dado certo) — já um lançamento novo/manual pode ser criado sem valor definido
  /// ainda. Quando parseia, o valor é arredondado para 2 casas decimais (o campo não aceita
  /// mais de 2 dígitos de centavos); se o lançamento está sendo confirmado, um valor zero ou
  /// negativo também é erro.
  ({double? valor, String? erro}) _validarValor() {
    final exigeValor =
        _pendenteRevisao ||
        (_editando && widget.existente!.status == StatusLancamento.confirmado);
    final texto = _valorController.text.trim();
    if (texto.isEmpty) {
      if (exigeValor) {
        return (valor: null, erro: 'Informe o valor do lançamento.');
      }
      return (valor: null, erro: null);
    }
    final normalizado = _normalizarValor(texto);
    if (normalizado == null) {
      return (
        valor: null,
        erro: 'Valor inválido. Digite um número, ex.: 150,00.',
      );
    }
    final arredondado = double.parse(normalizado.toStringAsFixed(2));
    if (_pendenteRevisao && arredondado <= 0) {
      return (valor: null, erro: 'Informe um valor maior que zero.');
    }
    return (valor: arredondado, erro: null);
  }

  Future<void> _escolherData() async {
    final escolhida = await showDatePicker(
      context: context,
      initialDate: _dataVencimento,
      firstDate: DateTime(_dataVencimento.year - 2),
      lastDate: DateTime(_dataVencimento.year + 5),
    );
    if (escolhida == null || !mounted) return;
    // `showDatePicker` sempre devolve uma instância LOCAL à meia-noite; um lançamento vindo do
    // servidor tem `dataVencimento` em UTC. Preserva o mesmo "tipo" de `DateTime` que já estava
    // em uso, só trocando o dia — sem isto, escolher qualquer data (mesmo a mesma de hoje)
    // trocava silenciosamente a instância de UTC para local, mudando o que é enviado no payload.
    final normalizada = _dataVencimento.isUtc
        ? DateTime.utc(escolhida.year, escolhida.month, escolhida.day)
        : DateTime(escolhida.year, escolhida.month, escolhida.day);
    setState(() => _dataVencimento = normalizada);
  }

  void _mostrarErro(String mensagem) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensagem)));
  }

  Future<void> _salvar() async {
    final descricao = _descricaoController.text.trim();
    if (descricao.isEmpty) {
      _mostrarErro('Dê uma descrição para o lançamento.');
      return;
    }

    final resultadoValor = _validarValor();
    if (resultadoValor.erro != null) {
      setState(() => _valorErro = resultadoValor.erro);
      return;
    }
    final valor = resultadoValor.valor;
    // Mostra o valor já arredondado a 2 casas decimais de volta no campo (ex.: "1,234" vira
    // "1,23") — silenciosamente truncar sem refletir na tela deixaria o que foi salvo
    // diferente do que o usuário vê digitado.
    if (valor != null) {
      final formatado = _formatarValorParaCampo(valor);
      if (_valorController.text != formatado) {
        _valorController.text = formatado;
      }
    }

    setState(() {
      _valorErro = null;
      _isSaving = true;
    });

    // Capturados ANTES do primeiro `await`: se o usuário navegar para fora desta tela enquanto
    // a requisição está em voo, este State é desmontado e `ref`/`context` não podem mais ser
    // lidos com segurança (`ref` pertence ao elemento desmontado; ler `context` de novo dispara
    // "This widget has been unmounted"). O `ProviderContainer` e o `ScaffoldMessenger`
    // capturados aqui continuam válidos mesmo depois — eles pertencem à árvore acima desta
    // tela, não a ela — então invalidações e mensagens de erro acontecem de qualquer forma.
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    void mostrarErroSempre(String mensagem) {
      messenger.showSnackBar(SnackBar(content: Text(mensagem)));
    }

    try {
      final existente = widget.existente;
      final repository = container.read(lancamentosRepositoryProvider);
      // O domínio permite conta em qualquer tipo de lançamento (inclusive DESPESA — ex.: "paguei
      // do cartão X" mesmo o lançamento não sendo uma fatura de cartão em si; ver
      // `CreateLancamentoDto`/`UpdateLancamentoDto` no backend, sem restrição por tipo) — antes
      // disto, escolher uma conta com "Despesa" selecionada era descartado ao salvar e ainda
      // contava como "alteração" no guard de descarte, um no-op enganoso.
      final contaId = _contaOuCartaoId;
      if (existente != null) {
        await repository.update(
          existente.id,
          tipo: _tipo,
          descricao: descricao,
          dataVencimento: _dataVencimento,
          valor: valor,
          contaId: contaId,
          isPago: _isPago,
        );
        // Lançamento veio do parser de e-mail e ainda não tinha sido revisado: salvar
        // aqui é o momento em que o usuário efetivamente confirma os dados (já
        // corrigidos, se precisou) — só então o status muda para CONFIRMADO no
        // servidor. Se isso falhar, a edição em si já foi salva, mas não fechamos a
        // tela: o usuário precisa tentar confirmar de novo, senão o lançamento fica
        // parado em PENDENTE_REVISAO mesmo depois de revisado.
        if (_pendenteRevisao) {
          try {
            await repository.confirmar(
              existente.id,
              valor: valor,
              dataVencimento: _dataVencimento,
              contaId: contaId,
              cartaoId: existente.cartaoId,
            );
          } catch (_) {
            // O update() já foi para o servidor com sucesso (só a confirmação falhou) —
            // invalida a lista de pendentes para refletir a descrição/valor já revisados,
            // mesmo que o status continue PENDENTE_REVISAO.
            container.invalidate(lancamentosPendentesProvider);
            if (mounted) {
              setState(() => _isSaving = false);
              _mostrarErro(
                'Lançamento salvo, mas não foi possível confirmar agora. Tente novamente.',
              );
            } else {
              mostrarErroSempre(
                'Lançamento salvo, mas não foi possível confirmar agora. Tente novamente.',
              );
            }
            return;
          }
        }
      } else {
        await repository.create(
          tipo: _tipo,
          descricao: descricao,
          dataVencimento: _dataVencimento,
          valor: valor,
          contaId: contaId,
          cartaoId: null,
          isPago: _isPago,
        );
      }
      container.invalidate(lancamentosDoMesProvider);
      container.invalidate(lancamentosPendentesProvider);
      container.invalidate(financeSummaryProvider);
      // Salvar aqui pode ter criado, atualizado ou removido um evento na Agenda (despesa/
      // fatura confirmada, ou isPago mudando) — invalida para que a aba de Agenda, se já
      // montada, reflita sem precisar de refresh manual.
      container.invalidate(upcomingEventsProvider);
      container.invalidate(monthEventsProvider);
      if (mounted) navigator.pop();
    } catch (_) {
      if (mounted) {
        _mostrarErro('Não foi possível salvar agora. Tente novamente.');
      } else {
        mostrarErroSempre('Não foi possível salvar agora. Tente novamente.');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _excluir() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir lançamento'),
        content: const Text('Tem certeza? Essa ação não pode ser desfeita.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    // Ver o comentário equivalente em `_salvar`: capturados antes do `await` que segue porque
    // este State pode ser desmontado enquanto a exclusão está em voo.
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() => _isSaving = true);
    try {
      await container
          .read(lancamentosRepositoryProvider)
          .remove(widget.existente!.id);
      container.invalidate(lancamentosDoMesProvider);
      container.invalidate(lancamentosPendentesProvider);
      container.invalidate(financeSummaryProvider);
      // Excluir pode ter removido um evento real na Agenda (ver LancamentosService.remove no
      // backend) — invalida para que a aba de Agenda, se já montada, pare de mostrar o card.
      container.invalidate(upcomingEventsProvider);
      container.invalidate(monthEventsProvider);
      if (mounted) navigator.pop();
    } catch (_) {
      if (mounted) {
        _mostrarErro('Não foi possível excluir agora. Tente novamente.');
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Não foi possível excluir agora. Tente novamente.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _confirmarDescarte() async {
    final descartar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Descartar alterações?'),
        content: const Text(
          'Você tem alterações não salvas neste lançamento. Se sair agora, elas serão perdidas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Continuar editando'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    if (descartar == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    final contasAsync = ref.watch(contasProvider);

    return PopScope(
      // `canPop: false` só passa a valer quando algo foi de fato alterado — um back sem
      // edições sai direto, sem perguntar nada. `Navigator.pop()` chamado diretamente (ao
      // salvar ou excluir com sucesso, e ao confirmar o descarte abaixo) não passa por este
      // guard: ele só intercepta `Navigator.maybePop()`, usado pelo botão de voltar da AppBar
      // e pelo gesto/botão de voltar do sistema.
      canPop: !_temAlteracoes,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _confirmarDescarte();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _pendenteRevisao
                ? 'Revisar lançamento'
                : (_editando ? 'Editar lançamento' : 'Novo lançamento'),
          ),
          actions: [
            if (_editando)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Excluir',
                onPressed: _isSaving ? null : _excluir,
              ),
          ],
        ),
        // Em telas largas (desktop/tablet paisagem), um formulário esticado de ponta a ponta
        // fica difícil de escanear — o conteúdo é centralizado com uma largura máxima, como o
        // resto do app já faz em outras telas de formulário.
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_pendenteRevisao) ...[
                  _LancamentoPendenteBanner(lancamento: widget.existente!),
                  const SizedBox(height: 20),
                ],
                _tipo == TipoLancamento.faturaCartao
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: Chip(
                          avatar: const Icon(Icons.credit_card, size: 18),
                          label: const Text('Fatura de cartão'),
                        ),
                      )
                    : SegmentedButton<TipoLancamento>(
                        segments: const [
                          ButtonSegment(
                            value: TipoLancamento.despesa,
                            label: Text('Despesa'),
                          ),
                          ButtonSegment(
                            value: TipoLancamento.receita,
                            label: Text('Receita'),
                          ),
                        ],
                        selected: {_tipo},
                        onSelectionChanged: (selecionados) =>
                            setState(() => _tipo = selecionados.first),
                      ),
                const SizedBox(height: 20),
                TextField(
                  controller: _descricaoController,
                  decoration: const InputDecoration(labelText: 'Descrição'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _valorController,
                  decoration: InputDecoration(
                    labelText: 'Valor',
                    prefixText: 'R\$ ',
                    errorText: _valorErro,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
                  ],
                  onChanged: (_) {
                    if (_valorErro != null) setState(() => _valorErro = null);
                  },
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Vencimento'),
                  subtitle: Text(dateFormat.format(_dataVencimento)),
                  trailing: const Icon(Icons.calendar_today_outlined),
                  onTap: _escolherData,
                ),
                const SizedBox(height: 8),
                contasAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (error, stackTrace) => const SizedBox.shrink(),
                  data: (contas) {
                    if (contas.isEmpty) return const SizedBox.shrink();
                    return DropdownButtonFormField<String?>(
                      initialValue: _contaOuCartaoId,
                      decoration: const InputDecoration(
                        labelText: 'Conta (opcional)',
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Nenhuma'),
                        ),
                        for (final conta in contas)
                          DropdownMenuItem<String?>(
                            value: conta.id,
                            child: Text(conta.nome),
                          ),
                      ],
                      onChanged: (valor) =>
                          setState(() => _contaOuCartaoId = valor),
                    );
                  },
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Já está pago/recebido'),
                  value: _isPago,
                  onChanged: (valor) => setState(() => _isPago = valor),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isSaving ? null : _salvar,
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _pendenteRevisao ? 'Confirmar e salvar' : 'Salvar',
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Contexto de onde o lançamento pendente veio, exibido no topo da tela de revisão para
/// ajudar o usuário a decidir se os dados detectados pelo parser de e-mail batem com o que
/// ele lembra, antes de confirmar.
class _LancamentoPendenteBanner extends StatelessWidget {
  const _LancamentoPendenteBanner({required this.lancamento});

  final LancamentoFinanceiro lancamento;

  @override
  Widget build(BuildContext context) {
    final instituicao = lancamento.instituicao;
    final valor = lancamento.valor;
    final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final dateFormat = DateFormat('dd/MM/yyyy');
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // `secondaryContainer` não é definido explicitamente no `ColorScheme` do app (ver
    // `lib/core/theme.dart`) e caía no `secondary` cheio (#00539E) com texto herdando
    // `onSurface` por cima — 2,26:1 no light e 1,94:1 no dark, bem abaixo do mínimo WCAG AA de
    // 4,5:1. `surfaceContainerHighest`/`onSurfaceVariant`/`onSurface` SÃO definidos
    // explicitamente nos dois temas e garantem contraste alto nos dois.
    final backgroundColor = colorScheme.surfaceContainerHighest;
    final labelStyle = theme.textTheme.labelLarge?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );
    final bodyStyle = theme.textTheme.bodySmall?.copyWith(
      color: colorScheme.onSurface,
    );
    return Card(
      color: backgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              instituicao != null
                  ? 'Detectado no e-mail do $instituicao'
                  : 'Detectado de um e-mail',
              style: labelStyle,
            ),
            const SizedBox(height: 4),
            Text(
              'Valor lido: ${valor == null ? 'não identificado' : currency.format(valor)}',
              style: bodyStyle,
            ),
            Text(
              'Vencimento lido: ${dateFormat.format(lancamento.dataVencimento)}',
              style: bodyStyle,
            ),
          ],
        ),
      ),
    );
  }
}
