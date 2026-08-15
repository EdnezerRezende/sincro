import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/dio_error_message.dart';
import 'compromisso_sugerido.dart';
import 'email_summary.dart';
import 'email_triage_providers.dart';
import 'rascunhos_email.dart';

enum _EstadoDetalheEmail { carregandoRascunhos, editando, falhaRascunhos, enviando, enviado }

String _formatarDataHora(DateTime dt) {
  final dia = dt.day.toString().padLeft(2, '0');
  final mes = dt.month.toString().padLeft(2, '0');
  final hora = dt.hour.toString().padLeft(2, '0');
  final minuto = dt.minute.toString().padLeft(2, '0');
  return '$dia/$mes às $hora:$minuto';
}

class EmailDetailScreen extends ConsumerStatefulWidget {
  const EmailDetailScreen({super.key, required this.summary});

  final EmailSummary summary;

  @override
  ConsumerState<EmailDetailScreen> createState() => _EmailDetailScreenState();
}

class _EmailDetailScreenState extends ConsumerState<EmailDetailScreen> {
  _EstadoDetalheEmail _estado = _EstadoDetalheEmail.carregandoRascunhos;
  RascunhosEmail? _rascunhos;
  final _textoController = TextEditingController();
  String? _erro;
  CompromissoSugerido? _compromissoSugerido;
  bool _compromissoConfirmado = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _carregarRascunhos());
  }

  @override
  void dispose() {
    _textoController.dispose();
    super.dispose();
  }

  Future<void> _carregarRascunhos() async {
    setState(() => _estado = _EstadoDetalheEmail.carregandoRascunhos);
    try {
      final rascunhos = await ref.read(emailReplyRepositoryProvider).gerarRascunhos(widget.summary.id);
      if (!mounted) return;
      setState(() {
        _rascunhos = rascunhos;
        _textoController.text = rascunhos.padrao;
        _estado = _EstadoDetalheEmail.editando;
        _erro = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e is DioException ? extractServerErrorMessage(e) : 'Não foi possível gerar sugestões agora.';
        _estado = _EstadoDetalheEmail.falhaRascunhos;
      });
    }
  }

  Future<void> _enviar() async {
    setState(() {
      _estado = _EstadoDetalheEmail.enviando;
      _erro = null;
    });
    try {
      final resultado =
          await ref.read(emailReplyRepositoryProvider).enviar(widget.summary.id, _textoController.text);
      if (!mounted) return;
      setState(() {
        _compromissoSugerido = resultado.compromissoSugerido;
        _estado = _EstadoDetalheEmail.enviado;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e is DioException ? extractServerErrorMessage(e) : 'Não foi possível enviar. Tente novamente.';
        _estado = _EstadoDetalheEmail.editando;
      });
    }
  }

  Future<void> _confirmarCompromisso() async {
    final compromisso = _compromissoSugerido;
    if (compromisso == null) return;
    try {
      await ref.read(emailReplyRepositoryProvider).confirmarCompromisso(compromisso);
      if (!mounted) return;
      setState(() => _compromissoConfirmado = true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível agendar agora. Tente novamente.')),
      );
    }
  }

  Future<void> _reconectar() async {
    try {
      await ref.read(gmailConnectionRepositoryProvider).connect();
      if (!mounted) return;
      ref.invalidate(gmailConnectionStatusProvider);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível reconectar. Tente novamente.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final connectionStatus = ref.watch(gmailConnectionStatusProvider);

    return Scaffold(
      appBar: AppBar(title: Text(widget.summary.assunto)),
      body: connectionStatus.when(
        data: (status) => status.temEscopoEnvio
            ? _corpo(context, temEscopoAgenda: status.temEscopoAgenda)
            : _semEscopoEnvio(context),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _corpo(context, temEscopoAgenda: false),
      ),
    );
  }

  Widget _semEscopoEnvio(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('De: ${widget.summary.remetente}'),
          const SizedBox(height: 8),
          Text(widget.summary.resumoCurto),
          const SizedBox(height: 24),
          const Text('Reconecte o Gmail para responder por aqui.'),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _reconectar, child: const Text('Reconectar Gmail')),
        ],
      ),
    );
  }

  Widget _corpo(BuildContext context, {required bool temEscopoAgenda}) {
    switch (_estado) {
      case _EstadoDetalheEmail.carregandoRascunhos:
        return const Center(child: CircularProgressIndicator());
      case _EstadoDetalheEmail.falhaRascunhos:
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_erro ?? 'Não foi possível gerar sugestões agora.'),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _carregarRascunhos, child: const Text('Tentar novamente')),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => setState(() {
                  _estado = _EstadoDetalheEmail.editando;
                  _erro = null;
                }),
                child: const Text('Escrever do zero'),
              ),
            ],
          ),
        );
      case _EstadoDetalheEmail.editando:
      case _EstadoDetalheEmail.enviando:
        final enviando = _estado == _EstadoDetalheEmail.enviando;
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_rascunhos != null) ...[
                Wrap(
                  spacing: 8,
                  children: [
                    ActionChip(
                      label: const Text('Direto'),
                      onPressed: () => setState(() => _textoController.text = _rascunhos!.direto),
                    ),
                    ActionChip(
                      label: const Text('Formal'),
                      onPressed: () => setState(() => _textoController.text = _rascunhos!.formal),
                    ),
                    ActionChip(
                      label: const Text('Padrão'),
                      onPressed: () => setState(() => _textoController.text = _rascunhos!.padrao),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _textoController,
                maxLines: 8,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                onChanged: (_) {
                  if (_erro != null) setState(() => _erro = null);
                },
              ),
              if (_erro != null) ...[
                const SizedBox(height: 8),
                Text(_erro!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: enviando || _textoController.text.trim().isEmpty ? null : _enviar,
                child: enviando
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Enviar'),
              ),
            ],
          ),
        );
      case _EstadoDetalheEmail.enviado:
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Enviado!'),
              if (_compromissoSugerido != null) ...[
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_compromissoSugerido!.tituloCompromisso, style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(_formatarDataHora(_compromissoSugerido!.dataHoraLimite)),
                        const SizedBox(height: 16),
                        if (_compromissoConfirmado)
                          const Text('Agendado ✓')
                        else if (temEscopoAgenda)
                          Row(
                            children: [
                              ElevatedButton(
                                onPressed: _confirmarCompromisso,
                                child: const Text('Confirmar no Calendário'),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: () => setState(() => _compromissoSugerido = null),
                                child: const Text('Não agendar'),
                              ),
                            ],
                          )
                        else
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Reconecte para agendar automaticamente.'),
                              const SizedBox(height: 8),
                              OutlinedButton(
                                onPressed: _reconectar,
                                child: const Text('Reconectar Gmail'),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
    }
  }
}
