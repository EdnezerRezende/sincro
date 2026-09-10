import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/dio_error_message.dart';
import '../../core/theme.dart';
import 'compromisso_sugerido.dart';
import 'email_summary.dart';
import 'email_triage_providers.dart';
import 'rascunhos_email.dart';

/// State for reading the e-mail body itself (`GET /:id/conteudo`) — never depends on any LLM
/// call, so it can never be blocked by the AI draft suggestion below being broken or slow.
enum _EstadoCorpo { carregando, carregado, falha }

/// State for the on-demand "Sugerir resposta" action — entirely separate from [_EstadoCorpo].
/// Starts `ociosa` (not requested): unlike the old behavior, generating a draft is never
/// triggered automatically, so a failing AI provider can no longer prevent reading the e-mail.
enum _EstadoSugestao { ociosa, carregando, falha, carregada }

enum _EstadoEnvio { editando, enviando, enviado }

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
  _EstadoCorpo _estadoCorpo = _EstadoCorpo.carregando;
  String? _corpoEmail;
  // Só `true` quando o backend não conseguiu montar um texto legível (nem `text/plain`, nem
  // `text/html`) e caiu de volta para o snippet do Gmail (~200 caracteres) — a tela precisa
  // avisar que aquilo é uma prévia, não a mensagem inteira, em vez de mostrar o trecho cortado
  // como se fosse o corpo completo.
  bool _corpoEhPreview = false;
  String? _erroCorpo;

  _EstadoSugestao _estadoSugestao = _EstadoSugestao.ociosa;
  RascunhosEmail? _rascunhos;
  String? _erroSugestao;

  _EstadoEnvio _estadoEnvio = _EstadoEnvio.editando;
  String? _erroEnvio;
  final _textoController = TextEditingController();
  CompromissoSugerido? _compromissoSugerido;
  bool _compromissoConfirmado = false;

  @override
  void initState() {
    super.initState();
    // O botão "Enviar" só fica habilitado quando há texto, e um TextEditingController não
    // reconstrói o widget sozinho: sem este listener, digitar em um campo vazio nunca
    // reabilitaria o botão, e apagar o texto o deixaria habilitado.
    _textoController.addListener(_aoMudarTexto);
    // Ler o e-mail nunca depende de IA nem de escopo de envio: carrega sempre, imediatamente.
    _carregarCorpo();
  }

  @override
  void dispose() {
    _textoController.removeListener(_aoMudarTexto);
    _textoController.dispose();
    super.dispose();
  }

  void _aoMudarTexto() {
    if (!mounted) return;
    setState(() => _erroEnvio = null);
  }

  Future<void> _carregarCorpo() async {
    setState(() {
      _estadoCorpo = _EstadoCorpo.carregando;
      _erroCorpo = null;
    });
    try {
      final corpo = await ref.read(emailSummaryRepositoryProvider).conteudo(widget.summary.id);
      if (!mounted) return;
      setState(() {
        _corpoEmail = corpo.corpo;
        _corpoEhPreview = corpo.ehPreview;
        _estadoCorpo = _EstadoCorpo.carregado;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erroCorpo = e is DioException ? extractServerErrorMessage(e) : 'Não foi possível carregar o e-mail agora.';
        _estadoCorpo = _EstadoCorpo.falha;
      });
    }
  }

  Future<void> _carregarSugestao() async {
    setState(() {
      _estadoSugestao = _EstadoSugestao.carregando;
      _erroSugestao = null;
    });
    try {
      final rascunhos = await ref.read(emailReplyRepositoryProvider).gerarRascunhos(widget.summary.id);
      if (!mounted) return;
      setState(() {
        _rascunhos = rascunhos;
        _estadoSugestao = _EstadoSugestao.carregada;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erroSugestao = e is DioException ? extractServerErrorMessage(e) : 'Não foi possível gerar sugestões agora.';
        _estadoSugestao = _EstadoSugestao.falha;
      });
    }
  }

  Future<void> _enviar() async {
    setState(() {
      _estadoEnvio = _EstadoEnvio.enviando;
      _erroEnvio = null;
    });
    try {
      final resultado =
          await ref.read(emailReplyRepositoryProvider).enviar(widget.summary.id, _textoController.text);
      if (!mounted) return;
      setState(() {
        _compromissoSugerido = resultado.compromissoSugerido;
        _estadoEnvio = _EstadoEnvio.enviado;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erroEnvio = e is DioException ? extractServerErrorMessage(e) : 'Não foi possível enviar. Tente novamente.';
        _estadoEnvio = _EstadoEnvio.editando;
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
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _cabecalho(context),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 16),
                    _corpoSecao(context),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            connectionStatus.when(
              data: (status) => status.temEscopoEnvio
                  ? _respostaSecao(context, temEscopoAgenda: status.temEscopoAgenda)
                  // Sem o escopo de envio o backend responde 403: mostra o painel de reconexão em
                  // vez de uma caixa de texto que nunca conseguiria enviar.
                  : _semEscopoEnvioSecao(context),
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              // Falha ao carregar o status de conexão não deve travar a resposta: mostra a seção
              // de resposta normalmente (mesma escolha que o app já fazia antes desta tela).
              error: (_, __) => _respostaSecao(context, temEscopoAgenda: false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cabecalho(BuildContext context) {
    final theme = Theme.of(context);
    final dataFormatada = _formatarDataHora(widget.summary.recebidoEm);
    return Semantics(
      header: true,
      label:
          '${widget.summary.assunto}, de ${widget.summary.remetente}, recebido em $dataFormatada',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.summary.assunto,
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'De: ${widget.summary.remetente}',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            dataFormatada,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _corpoSecao(BuildContext context) {
    final theme = Theme.of(context);
    switch (_estadoCorpo) {
      case _EstadoCorpo.carregando:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(child: CircularProgressIndicator()),
        );
      case _EstadoCorpo.falha:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _erroCorpo ?? 'Não foi possível carregar o e-mail agora.',
              style: TextStyle(color: theme.colorScheme.error),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 48,
              child: OutlinedButton(onPressed: _carregarCorpo, child: const Text('Tentar novamente')),
            ),
          ],
        );
      case _EstadoCorpo.carregado:
        final corpo = _corpoEmail ?? '';
        if (corpo.trim().isEmpty) {
          return Text(
            'Este e-mail não tem conteúdo de texto.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_corpoEhPreview) ...[
              // Não foi possível montar um texto legível a partir deste e-mail (nem texto puro,
              // nem HTML) — o que resta é o snippet curto que o próprio Gmail calcula. Avisa em
              // vez de deixar a pessoa achar que já leu a mensagem inteira.
              Semantics(
                liveRegion: true,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.sincroColors.caution.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: context.sincroColors.caution.withValues(alpha: 0.6)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 20, color: context.sincroColors.caution),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Não foi possível carregar o texto completo deste e-mail. O trecho abaixo '
                          'é só uma prévia curta — abra a mensagem no Gmail para ler tudo.',
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            SelectableText(
              corpo,
              style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurface),
            ),
          ],
        );
    }
  }

  Widget _semEscopoEnvioSecao(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Reconecte o Gmail para responder por aqui.'),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: ElevatedButton(onPressed: _reconectar, child: const Text('Reconectar Gmail')),
          ),
        ],
      ),
    );
  }

  Widget _respostaSecao(BuildContext context, {required bool temEscopoAgenda}) {
    if (_estadoEnvio == _EstadoEnvio.enviado) {
      return _enviadoCard(context, temEscopoAgenda: temEscopoAgenda);
    }
    final enviando = _estadoEnvio == _EstadoEnvio.enviando;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _sugestaoSecao(context),
          const SizedBox(height: 12),
          Semantics(
            textField: true,
            label: 'Texto da resposta',
            child: TextField(
              controller: _textoController,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Escreva sua resposta…',
              ),
            ),
          ),
          if (_erroEnvio != null) ...[
            const SizedBox(height: 8),
            Text(_erroEnvio!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: enviando || _textoController.text.trim().isEmpty ? null : _enviar,
              child: enviando
                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Enviar'),
            ),
          ),
        ],
      ),
    );
  }

  /// The AI draft suggestion is a separate, on-demand action: its own loading/error states never
  /// disable the text field or the "Enviar" button above/below it, and its failure never replaces
  /// the rest of the screen — the user can always ignore it and type a reply from scratch.
  Widget _sugestaoSecao(BuildContext context) {
    switch (_estadoSugestao) {
      case _EstadoSugestao.ociosa:
        return Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _carregarSugestao,
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('Sugerir resposta'),
            ),
          ),
        );
      case _EstadoSugestao.carregando:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 12),
              Text('Gerando sugestões…'),
            ],
          ),
        );
      case _EstadoSugestao.falha:
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _erroSugestao ?? 'Não foi possível gerar sugestões agora.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 48,
                child: OutlinedButton(onPressed: _carregarSugestao, child: const Text('Tentar novamente')),
              ),
            ],
          ),
        );
      case _EstadoSugestao.carregada:
        final rascunhos = _rascunhos;
        if (rascunhos == null) return const SizedBox.shrink();
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(
              label: const Text('Direto'),
              onPressed: () => setState(() => _textoController.text = rascunhos.direto),
            ),
            ActionChip(
              label: const Text('Formal'),
              onPressed: () => setState(() => _textoController.text = rascunhos.formal),
            ),
            ActionChip(
              label: const Text('Padrão'),
              onPressed: () => setState(() => _textoController.text = rascunhos.padrao),
            ),
          ],
        );
    }
  }

  Widget _enviadoCard(BuildContext context, {required bool temEscopoAgenda}) {
    final compromissoSugerido = _compromissoSugerido;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Enviado!'),
          if (compromissoSugerido != null) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(compromissoSugerido.tituloCompromisso, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(_formatarDataHora(compromissoSugerido.dataHoraLimite)),
                    const SizedBox(height: 16),
                    if (_compromissoConfirmado)
                      const Text('Agendado ✓')
                    else if (temEscopoAgenda)
                      Row(
                        children: [
                          SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              onPressed: _confirmarCompromisso,
                              child: const Text('Confirmar no Calendário'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            height: 48,
                            child: TextButton(
                              onPressed: () => setState(() => _compromissoSugerido = null),
                              child: const Text('Não agendar'),
                            ),
                          ),
                        ],
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Reconecte para agendar automaticamente.'),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 48,
                            child: OutlinedButton(onPressed: _reconectar, child: const Text('Reconectar Gmail')),
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
