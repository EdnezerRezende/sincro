import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/dio_error_message.dart';
import 'admin_grounding_card_form_validation.dart';
import 'grounding_card.dart';
import 'grounding_cards_providers.dart';

class AdminGroundingCardFormScreen extends ConsumerStatefulWidget {
  const AdminGroundingCardFormScreen({super.key, this.card});

  final GroundingCard? card;

  @override
  ConsumerState<AdminGroundingCardFormScreen> createState() => _AdminGroundingCardFormScreenState();
}

class _AdminGroundingCardFormScreenState extends ConsumerState<AdminGroundingCardFormScreen> {
  late final TextEditingController _tituloController;
  late final TextEditingController _conteudoController;
  late String _categoria;
  bool _salvando = false;
  String? _erro;

  bool get _editando => widget.card != null;

  @override
  void initState() {
    super.initState();
    final c = widget.card;
    _tituloController = TextEditingController(text: c?.titulo ?? '');
    _conteudoController = TextEditingController(text: c?.conteudo ?? '');
    _categoria = c?.categoria ?? categoriasCartao.first;
  }

  @override
  void dispose() {
    _tituloController.dispose();
    _conteudoController.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    setState(() => _erro = null);
    try {
      validateTitulo(_tituloController.text);
      validateConteudo(_conteudoController.text);
    } on GroundingCardFormValidationException catch (e) {
      setState(() => _erro = e.message);
      return;
    }

    setState(() => _salvando = true);
    try {
      if (_editando) {
        await ref.read(adminGroundingCardsRepositoryProvider).update(
              widget.card!.id,
              titulo: _tituloController.text.trim(),
              categoria: _categoria,
              conteudo: _conteudoController.text.trim(),
            );
      } else {
        await ref.read(adminGroundingCardsRepositoryProvider).create(
              titulo: _tituloController.text.trim(),
              categoria: _categoria,
              conteudo: _conteudoController.text.trim(),
            );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on DioException catch (e) {
      if (mounted) setState(() => _erro = extractServerErrorMessage(e));
    } catch (_) {
      if (mounted) setState(() => _erro = 'Não foi possível salvar. Tente novamente.');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_editando ? 'Editar cartão' : 'Novo cartão')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(controller: _tituloController, decoration: const InputDecoration(labelText: 'Título')),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _categoria,
            items: categoriasCartao
                .map((categoria) => DropdownMenuItem(value: categoria, child: Text(rotuloCategoria(categoria))))
                .toList(),
            onChanged: (value) => setState(() => _categoria = value!),
            decoration: const InputDecoration(labelText: 'Categoria'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _conteudoController,
            decoration: const InputDecoration(labelText: 'Conteúdo (passo a passo)'),
            maxLines: 6,
          ),
          if (_erro != null) ...[
            const SizedBox(height: 12),
            Text(_erro!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 24),
          ElevatedButton(onPressed: _salvando ? null : _salvar, child: const Text('Salvar')),
        ],
      ),
    );
  }
}
