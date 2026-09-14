import 'package:flutter/material.dart';
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
  ConsumerState<NovoLancamentoScreen> createState() => _NovoLancamentoScreenState();
}

class _NovoLancamentoScreenState extends ConsumerState<NovoLancamentoScreen> {
  late final TextEditingController _descricaoController;
  late final TextEditingController _valorController;
  late TipoLancamento _tipo;
  late DateTime _dataVencimento;
  String? _contaOuCartaoId;
  late bool _isPago;
  bool _isSaving = false;

  bool get _editando => widget.existente != null;

  @override
  void initState() {
    super.initState();
    final existente = widget.existente;
    _descricaoController = TextEditingController(text: existente?.descricao ?? '');
    _valorController = TextEditingController(text: _formatarValorParaCampo(existente?.valor));
    _tipo = existente?.tipo ?? TipoLancamento.despesa;
    _dataVencimento = existente?.dataVencimento ?? DateTime.now();
    _contaOuCartaoId = existente?.contaId;
    _isPago = existente?.isPago ?? false;
  }

  @override
  void dispose() {
    _descricaoController.dispose();
    _valorController.dispose();
    super.dispose();
  }

  /// Precisa produzir o mesmo formato que `_parseValor` espera ler de volta (vírgula como
  /// separador decimal, sem separador de milhar) — `valor.toString()` usava ponto (ex.: "100.0"),
  /// que `_parseValor` tratava como separador de milhar e descartava, inflando 100,00 para 1000,00
  /// ao editar e salvar um lançamento sem sequer tocar no campo de valor.
  String _formatarValorParaCampo(double? valor) {
    if (valor == null) return '';
    return valor.toStringAsFixed(2).replaceAll('.', ',');
  }

  double? _parseValor() {
    final texto = _valorController.text.trim();
    if (texto.isEmpty) return null;
    return double.tryParse(texto.replaceAll('.', '').replaceAll(',', '.'));
  }

  Future<void> _escolherData() async {
    final escolhida = await showDatePicker(
      context: context,
      initialDate: _dataVencimento,
      firstDate: DateTime(_dataVencimento.year - 2),
      lastDate: DateTime(_dataVencimento.year + 5),
    );
    if (escolhida == null || !mounted) return;
    setState(() => _dataVencimento = escolhida);
  }

  void _mostrarErro(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensagem)));
  }

  Future<void> _salvar() async {
    final descricao = _descricaoController.text.trim();
    if (descricao.isEmpty) {
      _mostrarErro('Dê uma descrição para o lançamento.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final existente = widget.existente;
      if (existente != null) {
        await ref.read(lancamentosRepositoryProvider).update(
              existente.id,
              tipo: _tipo,
              descricao: descricao,
              dataVencimento: _dataVencimento,
              valor: _parseValor(),
              contaId: _tipo == TipoLancamento.despesa ? null : _contaOuCartaoId,
              isPago: _isPago,
            );
      } else {
        await ref.read(lancamentosRepositoryProvider).create(
              tipo: _tipo,
              descricao: descricao,
              dataVencimento: _dataVencimento,
              valor: _parseValor(),
              contaId: _tipo == TipoLancamento.despesa ? null : _contaOuCartaoId,
              cartaoId: null,
              isPago: _isPago,
            );
      }
      ref.invalidate(lancamentosDoMesProvider);
      ref.invalidate(lancamentosPendentesProvider);
      ref.invalidate(financeSummaryProvider);
      // Salvar aqui pode ter criado, atualizado ou removido um evento na Agenda (despesa/
      // fatura confirmada, ou isPago mudando) — invalida para que a aba de Agenda, se já
      // montada, reflita sem precisar de refresh manual.
      ref.invalidate(upcomingEventsProvider);
      ref.invalidate(monthEventsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      _mostrarErro('Não foi possível salvar agora. Tente novamente.');
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

    setState(() => _isSaving = true);
    try {
      await ref.read(lancamentosRepositoryProvider).remove(widget.existente!.id);
      ref.invalidate(lancamentosDoMesProvider);
      ref.invalidate(lancamentosPendentesProvider);
      ref.invalidate(financeSummaryProvider);
      // Excluir pode ter removido um evento real na Agenda (ver LancamentosService.remove no
      // backend) — invalida para que a aba de Agenda, se já montada, pare de mostrar o card.
      ref.invalidate(upcomingEventsProvider);
      ref.invalidate(monthEventsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      _mostrarErro('Não foi possível excluir agora. Tente novamente.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    final contasAsync = ref.watch(contasProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_editando ? 'Editar lançamento' : 'Novo lançamento'),
        actions: [
          if (_editando)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Excluir',
              onPressed: _isSaving ? null : _excluir,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<TipoLancamento>(
            segments: const [
              ButtonSegment(value: TipoLancamento.despesa, label: Text('Despesa')),
              ButtonSegment(value: TipoLancamento.receita, label: Text('Receita')),
            ],
            selected: {_tipo},
            onSelectionChanged: (selecionados) => setState(() => _tipo = selecionados.first),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _descricaoController,
            decoration: const InputDecoration(labelText: 'Descrição'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _valorController,
            decoration: const InputDecoration(labelText: 'Valor', prefixText: 'R\$ '),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                decoration: const InputDecoration(labelText: 'Conta (opcional)'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Nenhuma')),
                  for (final conta in contas)
                    DropdownMenuItem<String?>(value: conta.id, child: Text(conta.nome)),
                ],
                onChanged: (valor) => setState(() => _contaOuCartaoId = valor),
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
                : const Text('Salvar'),
          ),
        ],
      ),
    );
  }
}
