import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

const _pluggyConnectBaseUrl = 'https://connect.pluggy.ai';

/// Hosts the Pluggy Connect widget in-app so the user never visually leaves Sincro.
///
/// The widget never navigates away and never postMessages a parent (both would require an
/// iframe host, which we don't have — this loads connect.pluggy.ai directly as the top-level
/// page). Instead, once the user finishes connecting a bank, it calls `history.replaceState` to
/// stamp the result (`item_id`, `execution_status`, `events`, ...) onto its OWN url as query
/// params. So completion is detected via `onUrlChange`, which webview_flutter fires for History
/// API changes too, not just real navigations.
class PluggyConnectWebviewScreen extends StatefulWidget {
  const PluggyConnectWebviewScreen({super.key, required this.connectToken});

  final String connectToken;

  @override
  State<PluggyConnectWebviewScreen> createState() => _PluggyConnectWebviewScreenState();
}

class _PluggyConnectWebviewScreenState extends State<PluggyConnectWebviewScreen> {
  late final WebViewController _controller;
  bool _authBlocked = false;
  // onUrlChange can fire more than once with a successful item_id (e.g. the widget updates the
  // url again when the user taps "Fechar"), so this guards against popping the route twice.
  bool _popped = false;

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
      body: _authBlocked
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
          : WebViewWidget(controller: _controller),
    );
  }
}
