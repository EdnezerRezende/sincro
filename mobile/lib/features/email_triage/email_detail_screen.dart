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
    // O botão "Enviar" só fica habilitado quando há texto, e um TextEditingController não
    // reconstrói o widget sozinho: sem este listener, digitar em um campo vazio ("Escrever do
    // zero") nunca reabilitaria o botão, e apagar um rascunho carregado o deixaria habilitado.
    _textoController.addListener(_aoMudarTexto);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Sem o escopo de envio o backend responde 403 na hora: a tela já mostra o painel de
      // reconexão, então não vale disparar a requisição condenada.
      final status = ref.read(gmailConnectionStatusProvider).asData?.value;
      if (status != null && !status.temEscopoEnvio) return;
      _carregarRascunhos();
    });
  }

  @override
  void dispose() {
    _textoController.removeListener(_aoMudarTexto);
    _textoController.dispose();
    super.dispose();
  }

  /// Reconstrói a tela a cada mudança de texto (mantendo o estado do botão "Enviar" correto) e,
  /// de quebra, limpa o erro anterior — o que antes era feito pelo `onChanged` do TextField.
  void _aoMudarTexto() {
    if (!mounted) return;
    setState(() => _erro = null);
  }

  Future<void> _carregarRascunhos() async {
    setState(() => _estado = _EstadoDetalheEmail.carregandoRascunhos);
    try {
      final rascunhos = await ref.read(emailReplyRepositoryProvider).gerarRascunhos(widget.summary.id);
      if (!mounted) return;
      // Fora do setState: a atribuição já notifica o listener do controller, que reconstrói a tela.
      _textoController.text = rascunhos.padrao;
      setState(() {
        _rascunhos = rascunhos;
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
      // Sem isto a tela continuaria exibindo o erro "reconecte o Gmail" gerado ANTES da reconexão,
      // sem nenhum gesto disponível para o usuário recarregar os rascunhos. Só recarrega enquanto
      // não há nada a perder: com texto já editado ou e-mail já enviado (o botão de reconexão da
      // agenda vive nessa tela), recarregar apagaria o trabalho do usuário.
      if (_estado == _EstadoDetalheEmail.carregandoRascunhos ||
          _estado == _EstadoDetalheEmail.falhaRascunhos) {
        await _carregarRascunhos();
      }
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
                      onPressed: () => _textoController.text = _rascunhos!.direto,
                    ),
                    ActionChip(
                      label: const Text('Formal'),
                      onPressed: () => _textoController.text = _rascunhos!.formal,
                    ),
                    ActionChip(
                      label: const Text('Padrão'),
                      onPressed: () => _textoController.text = _rascunhos!.padrao,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _textoController,
                maxLines: 8,
                decoration: const InputDecoration(border: OutlineInputBorder()),
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
