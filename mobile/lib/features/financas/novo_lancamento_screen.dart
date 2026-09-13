import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'finance_providers.dart';
import 'lancamento_financeiro.dart';

class NovoLancamentoScreen extends ConsumerStatefulWidget {
  const NovoLancamentoScreen({super.key});

  @override
  ConsumerState<NovoLancamentoScreen> createState() => _NovoLancamentoScreenState();
}

class _NovoLancamentoScreenState extends ConsumerState<NovoLancamentoScreen> {
  final _descricaoController = TextEditingController();
  final _valorController = TextEditingController();
  TipoLancamento _tipo = TipoLancamento.despesa;
  DateTime _dataVencimento = DateTime.now();
  String? _contaOuCartaoId;
  bool _isPago = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _descricaoController.dispose();
    _valorController.dispose();
    super.dispose();
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

  Future<void> _salvar() async {
    final descricao = _descricaoController.text.trim();
    if (descricao.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dê uma descrição para o lançamento.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref.read(lancamentosRepositoryProvider).create(
            tipo: _tipo,
            descricao: descricao,
            dataVencimento: _dataVencimento,
            valor: _parseValor(),
            contaId: _tipo == TipoLancamento.despesa ? null : _contaOuCartaoId,
            cartaoId: null,
            isPago: _isPago,
          );
      ref.invalidate(lancamentosDoMesProvider);
      ref.invalidate(financeSummaryProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível salvar agora. Tente novamente.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    final contasAsync = ref.watch(contasProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Novo lançamento')),
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
