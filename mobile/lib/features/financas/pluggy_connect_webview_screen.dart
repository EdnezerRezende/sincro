import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'finance_connection.dart';
import 'finance_connection_repository.dart';

const _pluggyConnectBaseUrl = 'https://connect.pluggy.ai';

/// Pure diff at the heart of the web success-detection path: which connection ids in [depois]
/// (the list fetched *after* the user visits the Pluggy tab) weren't present in [beforeIds] (the
/// snapshot captured *before* opening it). Extracted as a top-level, side-effect-free function so
/// it can be unit-tested directly — the surrounding widget can't easily be driven in a plain VM
/// test since `kIsWeb` is compile-time false there (see the test file for the full explanation).
@visibleForTesting
Set<String> newConnectionIds(Set<String> beforeIds, List<FinanceConnection> depois) {
  return depois.map((c) => c.id).toSet().difference(beforeIds);
}

/// Aviso mostrado no web ANTES de abrir a aba do Pluggy Connect, só quando não existe nenhuma
/// conexão prévia (`isFirstConnection`). Extraído como função pura pelo mesmo motivo de
/// `newConnectionIds`: `kIsWeb` é falso em tempo de compilação nos testes de VM, então a única
/// forma de testar a distinção primeira-conexão vs. reconexão sem um navegador de verdade é
/// isolar a decisão textual do widget que a usa. Retorna `null` para reconexão — nesse caso o
/// polling tem uma chance real de funcionar (a linha já existe; o webhook só precisa atualizá-la)
/// e não há nada a avisar antes de abrir a aba.
@visibleForTesting
String? firstConnectionWarning({required bool isFirstConnection}) {
  if (!isFirstConnection) return null;
  return 'Você ainda não tem nenhuma conta conectada. Pelo navegador, só conseguimos confirmar '
      'automaticamente a conclusão de contas que já existem — a sua primeira conexão só é '
      'detectada de forma confiável pelo aplicativo, no celular. Você pode tentar por aqui, mas '
      'talvez precise concluir pelo app.';
}

/// Mensagem mostrada assim que a aba do Pluggy Connect é aberta. Varia por primeira-conexão vs.
/// reconexão pelo mesmo motivo de [firstConnectionWarning]: já avisamos antes de abrir, mas
/// reforçar aqui evita que o usuário fique surpreso quando a confirmação automática não vier.
@visibleForTesting
String tabOpenedMessage({required bool isFirstConnection}) {
  return isFirstConnection
      ? 'Complete a conexão na aba que abrimos. Como é sua primeira conexão, talvez não '
          'consigamos confirmar automaticamente por aqui — se isso acontecer, finalize pelo '
          'aplicativo no celular.'
      : 'Complete a conexão na aba que abrimos. Volte aqui quando terminar.';
}

/// Mensagem mostrada quando o polling não encontra uma conexão nova. Este é o ponto central do
/// defeito relatado: para uma PRIMEIRA conexão, pedir para "tentar de novo" é enganoso, porque
/// o backend só cria a linha de conexão via `finalizeConnection(itemId)` (caminho nativo) — o
/// webhook (caminho web) só atualiza uma linha que já existe. Repetir o polling nunca vai
/// funcionar nesse caso, então a mensagem precisa dizer a verdade em vez de insistir. Para
/// reconexão, o "tente de novo" genérico continua correto: a linha já existe e o webhook pode
/// legitimamente estar apenas atrasado.
@visibleForTesting
String pollNotFoundMessage({required bool isFirstConnection}) {
  return isFirstConnection
      ? 'Não conseguimos confirmar sua primeira conexão por aqui — o navegador não recebe a '
          'confirmação de bancos novos automaticamente. Abra o aplicativo Sincro no celular para '
          'concluir; lá a confirmação acontece sozinha.'
      : 'Ainda não detectamos a atualização da sua conexão. Se você já concluiu, aguarde alguns '
          'segundos e toque em "Concluí a conexão" novamente.';
}

/// Hosts the Pluggy Connect flow. The two platform families need genuinely different
/// implementations, so this widget forks hard on `kIsWeb` in `initState`/`build` and the two
/// paths never share state:
///
/// NATIVE (Android/iOS): the widget is hosted in-app via `webview_flutter`, so the user never
/// visually leaves Sincro. The widget never navigates away and never postMessages a parent (both
/// would require an iframe host, which we don't have — this loads connect.pluggy.ai directly as
/// the top-level page of the WebView). Once the user finishes connecting a bank, Pluggy calls
/// `history.replaceState` to stamp the result (`item_id`, `execution_status`, ...) onto that same
/// page's url as query params. Completion is detected via `onUrlChange`, which webview_flutter
/// fires for History API changes too, not just real navigations. The route pops the raw
/// `String itemId` — the caller still has to exchange it with the backend
/// (`FinanceConnectionRepository.finalizeConnection`) to actually persist the connection.
///
/// WEB: `webview_flutter` has NO web implementation (only `webview_flutter_android` and
/// `webview_flutter_wkwebview` ship a platform interface registration). Instantiating
/// `WebViewController()` on web makes `WebViewPlatform.instance!` throw — and the `assert` that
/// would normally catch that misuse at dev time is stripped in `flutter build web --release`, so
/// it surfaces as an uncaught runtime exception inside this route's `initState`, which the
/// `Navigator.push` future being awaited by the caller never sees. Nobody calls `pop`, and the
/// caller is stuck awaiting forever — the "processando" hang this fix exists for. So on
/// `kIsWeb`, `WebViewController` is never constructed. Instead we open connect.pluggy.ai in a
/// brand new browser TAB via `url_launcher` and, once the user comes back, ask the backend
/// (`GET /financas/conexoes`) whether a new connection now exists — the `item_id` that Pluggy
/// stamps onto its own URL lives on connect.pluggy.ai's tab (a different origin, a different
/// browsing context), which our page can never read, so there is no way to recover an itemId on
/// this path. Success is instead inferred by diffing the connections list captured right before
/// opening the tab against the list captured after the user says (or the tab regaining focus
/// implies) they're done. This route then pops `true` (never a String) — the caller must NOT
/// call `finalizeConnection` in that branch, since the connection is already visible in
/// `/financas/conexoes` by the time we detect it (see `_FinancasScreenState`'s `_connectFinance`
/// for how both branches are reconciled).
///
/// CAVEAT (documented, not silently hidden): the backend only creates a `FinanceConnection` row
/// when `finalizeConnection(itemId)` is called (see `finance-connections.service.ts`); Pluggy's
/// webhook only *updates* a connection that already exists by matching `pluggyItemId`. That means
/// this web polling path reliably detects a RECONNECT (the item already existed, and its status
/// changes) but cannot make a genuinely brand-new first connection appear in
/// `/financas/conexoes` on its own, since nothing on this path ever supplies the backend an
/// itemId. Rather than fake a success, the UI here just keeps offering "Concluí a conexão" /
/// "Cancelar" — never an unlabelled infinite spinner — so the user always has an exit and can
/// finish the very first connection from the native (mobile) app if the web tab alone doesn't
/// get picked up.
///
/// Because that limitation is structural (not a bug that a retry will fix), the widget captures
/// whether ANY connection already existed before the flow started (`_beforeIds`, taken in
/// `_captureBaseline`, before the Pluggy tab is even opened) and uses that to tell a first
/// connection apart from a reconnect (`_isFirstConnection`). For a first connection it warns the
/// user *before* they open the tab that the automatic web confirmation likely won't work and the
/// native app is the reliable path (`firstConnectionWarning`), and if the poll comes back empty
/// it tells the truth instead of a generic "try again" (`pollNotFoundMessage`) — see those
/// top-level functions for the exact copy and the reasoning per case.
///
/// `connectionRepository` is optional on the constructor (not `required`) so that pre-existing
/// call sites that don't pass it (see e.g. `home_screen.dart`) keep compiling untouched; on
/// `kIsWeb` without a repository this widget shows an honest "not supported from here" state
/// rather than crash (the original bug) or poll against nothing.
class PluggyConnectWebviewScreen extends StatefulWidget {
  const PluggyConnectWebviewScreen({
    super.key,
    required this.connectToken,
    this.connectionRepository,
  });

  final String connectToken;

  /// Used only by the `kIsWeb` path to poll `GET /financas/conexoes` before/after the user visits
  /// the Pluggy tab. The native path never touches it. Optional (not `required`) on purpose: some
  /// existing call sites in the codebase construct this widget without it, and this widget cannot
  /// force every caller to be updated in lockstep. When `kIsWeb` and no repository was supplied,
  /// the widget shows an honest "not supported from here on web" state instead of either crashing
  /// (the original bug) or silently pretending to poll with nothing to poll with.
  final FinanceConnectionRepository? connectionRepository;

  @override
  State<PluggyConnectWebviewScreen> createState() => _PluggyConnectWebviewScreenState();
}

enum _WebState { loadingBaseline, baselineFailed, readyToOpen, waitingForUser, checking, unavailable }

class _PluggyConnectWebviewScreenState extends State<PluggyConnectWebviewScreen> with WidgetsBindingObserver {
  // Shared by both paths: guards against popping the route more than once (onUrlChange can fire
  // more than once with a successful item_id on native; the poll timer and the lifecycle
  // observer can both race to detect success on web).
  bool _popped = false;

  // ---- Native only (Android/iOS) ----
  WebViewController? _controller;
  bool _authBlocked = false;

  // ---- Web only ----
  _WebState _webState = _WebState.loadingBaseline;
  String? _webMessage;
  Set<String> _beforeIds = <String>{};
  Timer? _pollTimer;

  // Só é significativo depois que a baseline termina de carregar (_WebState.readyToOpen em
  // diante) — antes disso `_beforeIds` está vazio só porque ainda não veio a resposta, não porque
  // não existam conexões. Os pontos que usam este getter só rodam nos estados corretos.
  bool get _isFirstConnection => _beforeIds.isEmpty;

  // Montada via Uri(...) para que connectToken seja percent-encoded corretamente. O nome do
  // parâmetro é `connect_token` (snake_case) — é o que o bundle do widget lê via
  // `new URLSearchParams(window.location.search).get("connect_token")`; `connectToken`
  // (camelCase) é silenciosamente ignorado e produz "esqueceu de incluir o connect token".
  Uri get _connectUrl => Uri.parse(_pluggyConnectBaseUrl).replace(
        path: '/',
        queryParameters: {'connect_token': widget.connectToken},
      );

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      // Never instantiate WebViewController here — see class doc. Instead, capture which
      // connections already exist before the user ever opens the Pluggy tab, so a later diff
      // can tell "pre-existing" apart from "just created".
      WidgetsBinding.instance.addObserver(this);
      if (widget.connectionRepository == null) {
        // No repository to poll with — degrade honestly instead of crashing or hanging. Direct
        // assignment (not setState): this runs before the first frame, in initState.
        _webState = _WebState.unavailable;
        return;
      }
      _captureBaseline();
      return;
    }
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onUrlChange: (change) => _handleUrlChange(change.url),
          onWebResourceError: (error) {
            // `isForMainFrame` is platform-dependent (reliable on Android; often null on iOS).
            // Only trip the fallback for an explicit main-frame failure — a failed subresource
            // (image, font, tracking script) or an unreported (null) frame must NOT kick the
            // user out of the in-app WebView, since in-app hosting is the primary path.
            if (error.isForMainFrame == true) {
              setState(() => _authBlocked = true);
            }
          },
        ),
      )
      ..loadRequest(_connectUrl);
  }

  @override
  void dispose() {
    if (kIsWeb) {
      WidgetsBinding.instance.removeObserver(this);
      _pollTimer?.cancel();
    }
    super.dispose();
  }

  // Redundant with the manual "Concluí a conexão" button and the periodic poll timer: whichever
  // fires first wins. Some browsers reliably map tab-visibility changes to `resumed`; where they
  // don't, the timer and the button both still give the user a way to complete the flow.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!kIsWeb) return;
    if (state == AppLifecycleState.resumed && _webState == _WebState.waitingForUser && !_popped) {
      _checkForNewConnection();
    }
  }

  Future<void> _captureBaseline() async {
    final repository = widget.connectionRepository;
    if (repository == null) {
      setState(() => _webState = _WebState.unavailable);
      return;
    }
    setState(() => _webState = _WebState.loadingBaseline);
    try {
      final before = await repository.listConnections();
      if (!mounted) return;
      setState(() {
        _beforeIds = before.map((c) => c.id).toSet();
        _webState = _WebState.readyToOpen;
      });
    } catch (_) {
      // If we can't read the "before" snapshot, we can't safely tell a pre-existing connection
      // apart from a freshly created one — proceeding anyway risks a false positive ("success")
      // the very first time the user opens this screen. Fails honestly instead, with a retry.
      if (!mounted) return;
      setState(() => _webState = _WebState.baselineFailed);
    }
  }

  Future<void> _openPluggyInNewTab() async {
    bool opened;
    try {
      opened = await launchUrl(_connectUrl, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!mounted) return;
    setState(() {
      _webState = opened ? _WebState.waitingForUser : _WebState.readyToOpen;
      _webMessage = opened
          ? tabOpenedMessage(isFirstConnection: _isFirstConnection)
          : 'Não foi possível abrir o Pluggy Connect. Tente novamente.';
    });
    if (opened) {
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _checkForNewConnection());
    }
  }

  Future<void> _checkForNewConnection() async {
    final repository = widget.connectionRepository;
    if (repository == null || _popped || _webState == _WebState.checking) return;
    setState(() => _webState = _WebState.checking);
    try {
      final depois = await repository.listConnections();
      final novas = newConnectionIds(_beforeIds, depois);
      if (novas.isNotEmpty) {
        _popped = true;
        _pollTimer?.cancel();
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      if (!mounted) return;
      setState(() {
        _webState = _WebState.waitingForUser;
        _webMessage = pollNotFoundMessage(isFirstConnection: _isFirstConnection);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _webState = _WebState.waitingForUser;
        _webMessage = 'Não foi possível verificar suas conexões agora. Toque em "Concluí a conexão" '
            'para tentar de novo.';
      });
    }
  }

  void _handleUrlChange(String? url) {
    if (_popped || url == null) return;
    final params = Uri.parse(url).queryParameters;
    final itemId = params['item_id'];
    final executionStatus = params['execution_status'];
    if (itemId == null || executionStatus == null) return;
    if (executionStatus != 'SUCCESS' && executionStatus != 'PARTIAL_SUCCESS') return;

    _popped = true;
    Navigator.of(context).pop(itemId);
  }

  Future<void> _openInExternalBrowser() async {
    if (await canLaunchUrl(_connectUrl)) {
      await launchUrl(_connectUrl, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Conectar conta'),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
      ),
      body: kIsWeb ? _buildWebBody(context) : _buildNativeBody(),
    );
  }

  Widget _buildNativeBody() {
    return _authBlocked
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Este banco não permite login dentro do app. Você pode continuar num navegador.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(onPressed: _openInExternalBrowser, child: const Text('Abrir no navegador')),
                ],
              ),
            ),
          )
        : WebViewWidget(controller: _controller!);
  }

  Widget _buildWebBody(BuildContext context) {
    final theme = Theme.of(context);

    if (_webState == _WebState.unavailable) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.info_outline, size: 48, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              const Text(
                'Conectar por aqui ainda não é compatível com o navegador. Abra a tela Finanças '
                'para conectar, ou use o app pelo celular.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
            ],
          ),
        ),
      );
    }

    if (_webState == _WebState.loadingBaseline) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_webState == _WebState.baselineFailed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off_outlined, size: 48, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              const Text(
                'Não foi possível verificar suas conexões atuais. Tente novamente para continuar.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(onPressed: _captureBaseline, child: const Text('Tentar novamente')),
              const SizedBox(height: 8),
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
            ],
          ),
        ),
      );
    }

    if (_webState == _WebState.readyToOpen) {
      final aviso = firstConnectionWarning(isFirstConnection: _isFirstConnection);
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                aviso != null ? Icons.info_outline : Icons.open_in_new,
                size: 48,
                color: aviso != null ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              if (aviso != null) ...[
                Text(aviso, textAlign: TextAlign.center),
                const SizedBox(height: 12),
              ],
              const Text(
                'Vamos abrir o Pluggy Connect em outra aba do navegador. Complete a conexão do seu '
                'banco lá e depois volte para cá.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _openPluggyInNewTab,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Abrir Pluggy Connect'),
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
              if (_webMessage != null) ...[
                const SizedBox(height: 16),
                Text(_webMessage!, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
      );
    }

    // waitingForUser or checking.
    final checking = _webState == _WebState.checking;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.tab_outlined, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              _webMessage ?? 'Complete a conexão na aba que abrimos. Volte aqui quando terminar.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: checking ? null : _checkForNewConnection,
              child: checking
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Concluí a conexão'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: checking ? null : _openPluggyInNewTab,
              child: const Text('Abrir de novo'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }
}
