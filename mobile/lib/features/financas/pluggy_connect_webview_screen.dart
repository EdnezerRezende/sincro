import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

const _pluggyConnectBaseUrl = 'https://connect.pluggy.ai';
const _pluggyRedirectPrefix = 'https://sincro.app/pluggy-callback';

/// Hosts the Pluggy Connect widget in-app so the user never visually leaves Sincro. Completion is
/// detected via navigation to our own redirect URL (carrying `itemId` as a query param) rather
/// than a JS postMessage bridge, since intercepting navigation is a stable webview_flutter
/// feature regardless of exactly how Pluggy's widget JS communicates completion.
class PluggyConnectWebviewScreen extends StatefulWidget {
  const PluggyConnectWebviewScreen({super.key, required this.connectToken});

  final String connectToken;

  @override
  State<PluggyConnectWebviewScreen> createState() => _PluggyConnectWebviewScreenState();
}

class _PluggyConnectWebviewScreenState extends State<PluggyConnectWebviewScreen> {
  late final WebViewController _controller;
  bool _authBlocked = false;

  Uri get _connectUrl => Uri.parse(
        '$_pluggyConnectBaseUrl/?connectToken=${widget.connectToken}&redirectUrl=$_pluggyRedirectPrefix',
      );

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (request.url.startsWith(_pluggyRedirectPrefix)) {
              final itemId = Uri.parse(request.url).queryParameters['itemId'];
              if (itemId != null) {
                Navigator.of(context).pop(itemId);
              } else {
                setState(() => _authBlocked = true);
              }
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onWebResourceError: (_) => setState(() => _authBlocked = true),
        ),
      )
      ..loadRequest(_connectUrl);
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
