import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../trusted_contacts/trusted_contacts_providers.dart';
import '../email_triage/email_triage_providers.dart';
import '../email_triage/gmail_connection_repository.dart';
import '../biofeedback/biofeedback_cache.dart';
import '../biofeedback/biofeedback_providers.dart';
import '../biofeedback/estado_estresse.dart';
import '../financas/finance_connection.dart';
import '../financas/finance_providers.dart';
import '../financas/pluggy_connect_webview_screen.dart';
import 'emergency_button.dart';
import 'home_layout_mode.dart';
import 'home_design_style.dart';
import 'home_providers.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _registerFcmToken());
  }

  Future<void> _registerFcmToken() async {
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      final token = await messaging.getToken();
      if (token != null) {
        await ref.read(fcmTokenRepositoryProvider).register(token);
      }
    } catch (_) {
      // Registro de notificação é best-effort: o app continua funcionando
      // normalmente mesmo se o dispositivo não conseguir registrar o token
      // (ex: emulador sem Google Play Services, permissão negada).
    }
  }

  @override
  Widget build(BuildContext context) {
    // Sem spinner na tela principal: `resumo` já é o próprio default do provider, então cair
    // nele enquanto a preferência carrega não troca de layout visivelmente depois.
    final modo = ref.watch(homeLayoutModeProvider).maybeWhen(
          data: (m) => m,
          orElse: () => HomeLayoutMode.resumo,
        );

    final design = ref.watch(homeDesignStyleProvider).maybeWhen(
          data: (d) => d,
          orElse: () => HomeDesignStyle.minimalista,
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sincro'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Configurações',
            onPressed: () => Navigator.of(context).pushNamed('/settings'),
          ),
        ],
      ),
      body: switch ((modo, design)) {
        (HomeLayoutMode.resumo, HomeDesignStyle.minimalista) => const _HomeMinimalistaResumoView(),
        (HomeLayoutMode.resumo, HomeDesignStyle.moderno) => const _HomeModernoResumoView(),
        (HomeLayoutMode.resumo, HomeDesignStyle.funcional) => const _HomeFuncionalResumoView(),
        (HomeLayoutMode.abas, HomeDesignStyle.minimalista) => const _HomeMinimalistaAbasView(),
        (HomeLayoutMode.abas, HomeDesignStyle.moderno) => const _HomeModernoAbasView(),
        (HomeLayoutMode.abas, HomeDesignStyle.funcional) => const _HomeFuncionalAbasView(),
      },
    );
  }
}

/// Botão de emergência + aviso de "sem contatos", compartilhado pelos dois layouts. No layout de
/// abas isso fica sempre visível, fora do `TabBarView` — a emergência precisa estar alcançável
/// independente de qual aba a pessoa está olhando.
class _EmergencySection extends ConsumerWidget {
  const _EmergencySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contactsAsync = ref.watch(trustedContactsListProvider);
    return contactsAsync.when(
      data: (contacts) {
        if (contacts.isEmpty) {
          return const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _NoContactsHint(),
              SizedBox(height: 16),
              EmergencyButton(),
            ],
          );
        }
        return const EmergencyButton();
      },
      loading: () => const EmergencyButton(),
      error: (_, __) => const EmergencyButton(),
    );
  }
}

class _HomeMinimalistaResumoView extends ConsumerWidget {
  const _HomeMinimalistaResumoView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gmailStatusAsync = ref.watch(gmailConnectionStatusProvider);
    final financeConnectionsAsync = ref.watch(financeConnectionsProvider);
    final biofeedbackAtivoAsync = ref.watch(biofeedbackAtivoProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Tudo em ordem por hoje.', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _GmailCard(statusAsync: gmailStatusAsync),
          const SizedBox(height: 16),
          _FinancasCard(connectionsAsync: financeConnectionsAsync),
          const SizedBox(height: 16),
          _BiofeedbackCard(ativoAsync: biofeedbackAtivoAsync),
          const SizedBox(height: 16),
          const _ProfessionalsCard(),
          const SizedBox(height: 16),
          const _GroundingCardsCard(),
          const SizedBox(height: 16),
          const _EmergencySection(),
        ],
      ),
    );
  }
}

/// Layout alternativo para quem prefere mais informação organizada por contexto em vez de um
/// único scroll longo. Reusa exatamente os mesmos widgets de card do layout `resumo` — só muda o
/// agrupamento ao redor.
class _HomeMinimalistaAbasView extends ConsumerWidget {
  const _HomeMinimalistaAbasView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gmailStatusAsync = ref.watch(gmailConnectionStatusProvider);
    final financeConnectionsAsync = ref.watch(financeConnectionsProvider);
    final biofeedbackAtivoAsync = ref.watch(biofeedbackAtivoProvider);

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Hoje'),
              Tab(text: 'Finanças'),
              Tab(text: 'Apoio'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _GmailCard(statusAsync: gmailStatusAsync),
                    const SizedBox(height: 16),
                    _BiofeedbackCard(ativoAsync: biofeedbackAtivoAsync),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _FinancasCard(connectionsAsync: financeConnectionsAsync),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: const [
                    _ProfessionalsCard(),
                    SizedBox(height: 16),
                    _GroundingCardsCard(),
                  ],
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: _EmergencySection(),
          ),
        ],
      ),
    );
  }
}

class _GmailCard extends ConsumerWidget {
  const _GmailCard({required this.statusAsync});

  final AsyncValue<GmailConnectionStatus> statusAsync;

  Future<void> _connect(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(gmailConnectionRepositoryProvider).connect();
      ref.invalidate(gmailConnectionStatusProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível conectar o Gmail. Tente novamente.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return statusAsync.when(
      data: (status) {
        if (!status.connected) {
          return Card(
            child: ListTile(
              leading: const Icon(Icons.mail_outline),
              title: const Text('Caixa de Entrada'),
              subtitle: const Text('Conecte seu Gmail para ver um resumo calmo dos seus e-mails.'),
              trailing: ElevatedButton(
                onPressed: () => _connect(context, ref),
                child: const Text('Conectar Gmail'),
              ),
            ),
          );
        }
        return Card(
          child: ListTile(
            leading: const Icon(Icons.mail_outline),
            title: const Text('Caixa de Entrada'),
            subtitle: Text('Conectado como ${status.gmailEmail}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/inbox'),
          ),
        );
      },
      loading: () => const Card(child: ListTile(title: Text('Caixa de Entrada'), subtitle: Text('Carregando...'))),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _FinancasCard extends ConsumerWidget {
  const _FinancasCard({required this.connectionsAsync});

  final AsyncValue<List<FinanceConnection>> connectionsAsync;

  Future<void> _connect(BuildContext context, WidgetRef ref) async {
    // Capturado antes do finalize: o prompt de dia de recebimento só faz sentido na PRIMEIRA
    // conta conectada, não a cada banco novo que o usuário adicionar depois.
    final isFirstConnection = connectionsAsync.value?.isEmpty ?? true;
    try {
      final connectToken = await ref.read(financeConnectionRepositoryProvider).createConnectToken();
      if (!context.mounted) return;
      final itemId = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => PluggyConnectWebviewScreen(connectToken: connectToken)),
      );
      if (itemId == null) return;
      await ref.read(financeConnectionRepositoryProvider).finalizeConnection(itemId);
      ref.invalidate(financeConnectionsProvider);
      if (isFirstConnection && context.mounted) {
        await _promptDiaRecebimento(context, ref);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível conectar sua conta. Tente novamente.')),
        );
      }
    }
  }

  /// Pergunta o dia de recebimento logo após a primeira conexão, já que ele é o que define o
  /// ciclo do saldo livre. É um nice-to-have: recusar ou digitar algo inválido só segue o
  /// fluxo em silêncio — o usuário pode definir depois em Configurações.
  Future<void> _promptDiaRecebimento(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final dia = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Em que dia do mês você costuma receber?'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Ex: 5 (dia 5 de cada mês)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Agora não')),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, int.tryParse(controller.text.trim())),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (dia == null || dia < 1 || dia > 31) return;

    try {
      await ref.read(diaRecebimentoRepositoryProvider).update(dia);
    } catch (_) {
      // Silencioso de propósito: não transformar um extra em erro logo após conectar.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return connectionsAsync.when(
      data: (connections) {
        if (connections.isEmpty) {
          return Card(
            child: ListTile(
              leading: const Icon(Icons.account_balance_outlined),
              title: const Text('Finanças'),
              subtitle: const Text('Conecte uma conta para ver seu saldo livre.'),
              trailing: ElevatedButton(
                onPressed: () => _connect(context, ref),
                child: const Text('Conectar conta'),
              ),
            ),
          );
        }
        return Card(
          child: ListTile(
            leading: const Icon(Icons.account_balance_outlined),
            title: const Text('Finanças'),
            subtitle: _SaldoLivreSubtitle(connectionCount: connections.length),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/financas'),
          ),
        );
      },
      loading: () => const Card(child: ListTile(title: Text('Finanças'), subtitle: Text('Carregando...'))),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

/// Saldo livre é o número que justifica esse pilar inteiro, então ele vem para o card da Home.
/// Enquanto o resumo carrega — ou se ele falhar — caímos na contagem de contas, que já veio do
/// provider de conexões, para o card nunca parecer quebrado.
class _SaldoLivreSubtitle extends ConsumerWidget {
  const _SaldoLivreSubtitle({required this.connectionCount});

  final int connectionCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(financeSummaryProvider);
    final fallback = Text('$connectionCount conta(s) conectada(s)');
    return summaryAsync.when(
      data: (summary) => Text('Saldo livre: R\$ ${summary.saldoLivre.toStringAsFixed(2)}'),
      loading: () => fallback,
      error: (_, __) => fallback,
    );
  }
}

class _BiofeedbackCard extends ConsumerWidget {
  const _BiofeedbackCard({required this.ativoAsync});

  final AsyncValue<bool> ativoAsync;

  Future<void> _ativar(BuildContext context, WidgetRef ref) async {
    try {
      final autorizado = await ref.read(biofeedbackHealthServiceProvider).solicitarPermissao();
      if (!autorizado) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Permissão não concedida. Você pode tentar novamente quando quiser.'),
            ),
          );
        }
        return;
      }
      // Persistimos a ativação e agendamos o background ANTES da primeira sincronização: se a
      // primeira leitura falhar (Health Connect ainda inicializando, nenhuma fonte de dados
      // pareada, chamada instável), a permissão já foi concedida e não faz sentido obrigar o
      // usuário a refazer tudo. O agendamento em background cuida das próximas tentativas.
      await ref.read(biofeedbackCacheProvider).setAtivo(true);
      // A ativação já pediu TODAS as permissões da versão atual (`_tipos` inclui passos e
      // treinos), então registramos a versão aqui para que a checagem de upgrade dentro de
      // `sincronizar()` seja um no-op para quem está ativando agora — em vez de pedir de novo,
      // sem motivo, logo na primeira sincronização.
      await ref
          .read(biofeedbackCacheProvider)
          .setPermissoesVersao(BiofeedbackCache.versaoPermissoesAtual);
      final frequenciaMinutos = await ref.read(biofeedbackCacheProvider).getFrequenciaMinutos();
      await ref.read(biofeedbackBackgroundTaskProvider).registrar(Duration(minutes: frequenciaMinutos));
      try {
        await ref.read(biofeedbackSyncServiceProvider).sincronizar();
      } catch (_) {
        // Primeira sincronização é best-effort — mesma postura do callback do background.
      }
      ref.invalidate(biofeedbackAtivoProvider);
      ref.invalidate(biofeedbackResumoProvider);
      // A sincronização acima também grava o histórico de repouso, que alimenta o contador
      // "(N de 7 dias)" da tela de detalhe.
      ref.invalidate(biofeedbackDiasNoHistoricoProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível ativar o Biofeedback. Tente novamente.')),
        );
      }
    }
  }

  Widget _cardInativo(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.favorite_border),
        title: const Text('Biofeedback'),
        subtitle: const Text('Acompanhe seu bem-estar com seu smartwatch.'),
        trailing: ElevatedButton(
          onPressed: () => _ativar(context, ref),
          child: const Text('Ativar Biofeedback'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ativoAsync.when(
      data: (ativo) {
        if (!ativo) return _cardInativo(context, ref);
        return Card(
          child: ListTile(
            leading: const Icon(Icons.favorite_border),
            title: const Text('Biofeedback'),
            subtitle: const _UltimaFcSubtitle(),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/biofeedback'),
          ),
        );
      },
      loading: () => const Card(child: ListTile(title: Text('Biofeedback'), subtitle: Text('Carregando...'))),
      // O card do Biofeedback nunca some da Home (restrição global do pilar): se não deu para
      // ler o estado de ativação, mostramos o card inativo, que continua sendo um ponto de
      // entrada válido — ativar de novo é idempotente.
      error: (_, __) => _cardInativo(context, ref),
    );
  }
}

/// Mostrada só quando o Biofeedback já está ativo (ver `_BiofeedbackCard.build`), então "nenhum
/// dado disponível ainda" aqui significa "ativado mas sem smartwatch pareado", não "não ativado".
class _UltimaFcSubtitle extends ConsumerWidget {
  const _UltimaFcSubtitle();

  static String _rotuloEstado(EstadoEstresse estado) {
    switch (estado) {
      case EstadoEstresse.calmo:
        return 'Calmo';
      case EstadoEstresse.elevado:
        return 'Elevado';
      case EstadoEstresse.coletandoDados:
        // Não menciona "coletando dados" na Home — a tela de detalhe é o lugar para isso, para
        // a Home (primeiro contato do app) não parecer ter uma pendência.
        return '';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resumoAsync = ref.watch(biofeedbackResumoProvider);
    return resumoAsync.when(
      data: (resumo) {
        if (resumo?.ultimaFc == null) return const Text('Nenhum dado disponível ainda');
        // Sem "agora": a última leitura pode ter horas, já que a sincronização é periódica.
        final rotuloEstado = _rotuloEstado(resumo!.estadoEstresse);
        final texto = rotuloEstado.isEmpty
            ? '${resumo.ultimaFc!.round()} bpm'
            : '${resumo.ultimaFc!.round()} bpm · $rotuloEstado';
        return Text(texto);
      },
      loading: () => const Text('Carregando...'),
      error: (_, __) => const Text('Nenhum dado disponível ainda'),
    );
  }
}

class _NoContactsHint extends StatelessWidget {
  const _NoContactsHint();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 18, color: colors.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Adicione um contato de confiança para estar preparado em emergências.',
                style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfessionalsCard extends StatelessWidget {
  const _ProfessionalsCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.medical_services_outlined),
        title: const Text('Encontrar profissional'),
        subtitle: const Text('Busque profissionais neuroafirmativos perto de você.'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).pushNamed('/professionals'),
      ),
    );
  }
}

class _GroundingCardsCard extends StatelessWidget {
  const _GroundingCardsCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.self_improvement_outlined),
        title: const Text('Alívio sensorial'),
        subtitle: const Text('Técnicas de aterramento e alívio para o dia a dia.'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).pushNamed('/grounding-cards'),
      ),
    );
  }
}

/// Moderno Suave: Design contemporâneo com ícones e gradientes sutis
class _HomeModernoResumoView extends ConsumerWidget {
  const _HomeModernoResumoView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gmailStatusAsync = ref.watch(gmailConnectionStatusProvider);
    final financeConnectionsAsync = ref.watch(financeConnectionsProvider);
    final biofeedbackAtivoAsync = ref.watch(biofeedbackAtivoProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Você está em dia', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text('Tudo sob controle', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 20),
          _ModernoGmailCard(statusAsync: gmailStatusAsync),
          const SizedBox(height: 11),
          _ModernoFinancasCard(connectionsAsync: financeConnectionsAsync),
          const SizedBox(height: 11),
          _ModernoBiofeedbackCard(ativoAsync: biofeedbackAtivoAsync),
          const SizedBox(height: 11),
          _ModernoProfessionalsCard(),
          const SizedBox(height: 11),
          _ModernoGroundingCardsCard(),
          const SizedBox(height: 20),
          const _EmergencySection(),
        ],
      ),
    );
  }
}

class _HomeModernoAbasView extends ConsumerWidget {
  const _HomeModernoAbasView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gmailStatusAsync = ref.watch(gmailConnectionStatusProvider);
    final financeConnectionsAsync = ref.watch(financeConnectionsProvider);
    final biofeedbackAtivoAsync = ref.watch(biofeedbackAtivoProvider);

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Hoje'),
              Tab(text: 'Finanças'),
              Tab(text: 'Apoio'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    _ModernoGmailCard(statusAsync: gmailStatusAsync),
                    const SizedBox(height: 11),
                    _ModernoBiofeedbackCard(ativoAsync: biofeedbackAtivoAsync),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    _ModernoFinancasCard(connectionsAsync: financeConnectionsAsync),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    _ModernoProfessionalsCard(),
                    const SizedBox(height: 11),
                    _ModernoGroundingCardsCard(),
                  ],
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(14),
            child: _EmergencySection(),
          ),
        ],
      ),
    );
  }
}

class _ModernoGmailCard extends ConsumerWidget {
  const _ModernoGmailCard({required this.statusAsync});

  final AsyncValue<GmailConnectionStatus> statusAsync;

  Future<void> _connect(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(gmailConnectionRepositoryProvider).connect();
      ref.invalidate(gmailConnectionStatusProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível conectar o Gmail. Tente novamente.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return statusAsync.when(
      data: (status) {
        if (!status.connected) {
          return Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.blue.withAlpha(25), Colors.cyan.withAlpha(15)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListTile(
                leading: Icon(Icons.mail_outline, color: Colors.blue[600]),
                title: const Text('Caixa de Entrada'),
                subtitle: const Text('Conecte seu Gmail para ver um resumo calmo dos seus e-mails.'),
                trailing: ElevatedButton(
                  onPressed: () => _connect(context, ref),
                  child: const Text('Conectar Gmail'),
                ),
              ),
            ),
          );
        }
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: ListTile(
            leading: Icon(Icons.mail_outline, color: Colors.blue[600]),
            title: const Text('Caixa de Entrada'),
            subtitle: Text('Conectado como ${status.gmailEmail}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/inbox'),
          ),
        );
      },
      loading: () => Card(
        elevation: 0,
        child: ListTile(
          title: const Text('Caixa de Entrada'),
          subtitle: const Text('Carregando...'),
          leading: Icon(Icons.mail_outline, color: Colors.blue[600]),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _ModernoFinancasCard extends ConsumerWidget {
  const _ModernoFinancasCard({required this.connectionsAsync});

  final AsyncValue<List<FinanceConnection>> connectionsAsync;

  Future<void> _connect(BuildContext context, WidgetRef ref) async {
    final isFirstConnection = connectionsAsync.value?.isEmpty ?? true;
    try {
      final connectToken = await ref.read(financeConnectionRepositoryProvider).createConnectToken();
      if (!context.mounted) return;
      final itemId = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => PluggyConnectWebviewScreen(connectToken: connectToken)),
      );
      if (itemId == null) return;
      await ref.read(financeConnectionRepositoryProvider).finalizeConnection(itemId);
      ref.invalidate(financeConnectionsProvider);
      if (isFirstConnection && context.mounted) {
        await _promptDiaRecebimento(context, ref);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível conectar sua conta. Tente novamente.')),
        );
      }
    }
  }

  Future<void> _promptDiaRecebimento(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final dia = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Em que dia do mês você costuma receber?'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Ex: 5 (dia 5 de cada mês)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Agora não')),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, int.tryParse(controller.text.trim())),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (dia == null || dia < 1 || dia > 31) return;

    try {
      await ref.read(diaRecebimentoRepositoryProvider).update(dia);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return connectionsAsync.when(
      data: (connections) {
        if (connections.isEmpty) {
          return Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.green.withAlpha(25), Colors.teal.withAlpha(15)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListTile(
                leading: Icon(Icons.account_balance_outlined, color: Colors.green[600]),
                title: const Text('Finanças'),
                subtitle: const Text('Conecte uma conta para ver seu saldo livre.'),
                trailing: ElevatedButton(
                  onPressed: () => _connect(context, ref),
                  child: const Text('Conectar conta'),
                ),
              ),
            ),
          );
        }
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: ListTile(
            leading: Icon(Icons.account_balance_outlined, color: Colors.green[600]),
            title: const Text('Finanças'),
            subtitle: _SaldoLivreSubtitle(connectionCount: connections.length),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/financas'),
          ),
        );
      },
      loading: () => Card(
        elevation: 0,
        child: ListTile(
          title: const Text('Finanças'),
          subtitle: const Text('Carregando...'),
          leading: Icon(Icons.account_balance_outlined, color: Colors.green[600]),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _ModernoBiofeedbackCard extends ConsumerWidget {
  const _ModernoBiofeedbackCard({required this.ativoAsync});

  final AsyncValue<bool> ativoAsync;

  Future<void> _ativar(BuildContext context, WidgetRef ref) async {
    try {
      final autorizado = await ref.read(biofeedbackHealthServiceProvider).solicitarPermissao();
      if (!autorizado) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Permissão não concedida. Você pode tentar novamente quando quiser.'),
            ),
          );
        }
        return;
      }
      await ref.read(biofeedbackCacheProvider).setAtivo(true);
      await ref
          .read(biofeedbackCacheProvider)
          .setPermissoesVersao(BiofeedbackCache.versaoPermissoesAtual);
      final frequenciaMinutos = await ref.read(biofeedbackCacheProvider).getFrequenciaMinutos();
      await ref.read(biofeedbackBackgroundTaskProvider).registrar(Duration(minutes: frequenciaMinutos));
      try {
        await ref.read(biofeedbackSyncServiceProvider).sincronizar();
      } catch (_) {}
      ref.invalidate(biofeedbackAtivoProvider);
      ref.invalidate(biofeedbackResumoProvider);
      ref.invalidate(biofeedbackDiasNoHistoricoProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível ativar o Biofeedback. Tente novamente.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ativoAsync.when(
      data: (ativo) {
        if (!ativo) {
          return Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.red.withAlpha(25), Colors.pink.withAlpha(15)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListTile(
                leading: Icon(Icons.favorite_border, color: Colors.red[600]),
                title: const Text('Biofeedback'),
                subtitle: const Text('Acompanhe seu bem-estar com seu smartwatch.'),
                trailing: ElevatedButton(
                  onPressed: () => _ativar(context, ref),
                  child: const Text('Ativar Biofeedback'),
                ),
              ),
            ),
          );
        }
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: ListTile(
            leading: Icon(Icons.favorite_border, color: Colors.red[600]),
            title: const Text('Biofeedback'),
            subtitle: const _UltimaFcSubtitle(),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/biofeedback'),
          ),
        );
      },
      loading: () => Card(
        elevation: 0,
        child: ListTile(
          title: const Text('Biofeedback'),
          subtitle: const Text('Carregando...'),
          leading: Icon(Icons.favorite_border, color: Colors.red[600]),
        ),
      ),
      error: (_, __) => Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.red.withAlpha(25), Colors.pink.withAlpha(15)],
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListTile(
            leading: Icon(Icons.favorite_border, color: Colors.red[600]),
            title: const Text('Biofeedback'),
            subtitle: const Text('Acompanhe seu bem-estar com seu smartwatch.'),
            trailing: ElevatedButton(
              onPressed: () => _ativar(context, ref),
              child: const Text('Ativar Biofeedback'),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModernoProfessionalsCard extends StatelessWidget {
  const _ModernoProfessionalsCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.purple.withAlpha(25), Colors.blue.withAlpha(15)],
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ListTile(
          leading: Icon(Icons.medical_services_outlined, color: Colors.purple[600]),
          title: const Text('Encontrar profissional'),
          subtitle: const Text('Busque profissionais neuroafirmativos perto de você.'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).pushNamed('/professionals'),
        ),
      ),
    );
  }
}

class _ModernoGroundingCardsCard extends StatelessWidget {
  const _ModernoGroundingCardsCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.orange.withAlpha(25), Colors.amber.withAlpha(15)],
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ListTile(
          leading: Icon(Icons.self_improvement_outlined, color: Colors.orange[600]),
          title: const Text('Alívio sensorial'),
          subtitle: const Text('Técnicas de aterramento e alívio para o dia a dia.'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).pushNamed('/grounding-cards'),
        ),
      ),
    );
  }
}

/// Funcional Direto: Máxima clareza visual, layout tipo lista compacto
class _HomeFuncionalResumoView extends ConsumerWidget {
  const _HomeFuncionalResumoView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gmailStatusAsync = ref.watch(gmailConnectionStatusProvider);
    final financeConnectionsAsync = ref.watch(financeConnectionsProvider);
    final biofeedbackAtivoAsync = ref.watch(biofeedbackAtivoProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Monitorando seu ritmo', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          _FuncionalStatusSummary(),
          const SizedBox(height: 16),
          Text('CONEXÕES', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 8),
          _FuncionalGmailCard(statusAsync: gmailStatusAsync),
          const SizedBox(height: 8),
          _FuncionalFinancasCard(connectionsAsync: financeConnectionsAsync),
          const SizedBox(height: 8),
          _FuncionalBiofeedbackCard(ativoAsync: biofeedbackAtivoAsync),
          const SizedBox(height: 16),
          Text('RECURSOS', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 8),
          _FuncionalProfessionalsCard(),
          const SizedBox(height: 8),
          _FuncionalGroundingCardsCard(),
          const SizedBox(height: 16),
          const _EmergencySection(),
        ],
      ),
    );
  }
}

class _HomeFuncionalAbasView extends ConsumerWidget {
  const _HomeFuncionalAbasView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gmailStatusAsync = ref.watch(gmailConnectionStatusProvider);
    final financeConnectionsAsync = ref.watch(financeConnectionsProvider);
    final biofeedbackAtivoAsync = ref.watch(biofeedbackAtivoProvider);

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Hoje'),
              Tab(text: 'Finanças'),
              Tab(text: 'Apoio'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    _FuncionalStatusSummary(),
                    const SizedBox(height: 12),
                    _FuncionalGmailCard(statusAsync: gmailStatusAsync),
                    const SizedBox(height: 8),
                    _FuncionalBiofeedbackCard(ativoAsync: biofeedbackAtivoAsync),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    _FuncionalFinancasCard(connectionsAsync: financeConnectionsAsync),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    _FuncionalProfessionalsCard(),
                    const SizedBox(height: 8),
                    _FuncionalGroundingCardsCard(),
                  ],
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(12),
            child: _EmergencySection(),
          ),
        ],
      ),
    );
  }
}

class _FuncionalStatusSummary extends StatelessWidget {
  const _FuncionalStatusSummary();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Status do dia', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.check_circle, size: 18, color: Colors.green[600]),
              const SizedBox(width: 8),
              const Expanded(child: Text('Sem triagem necessária', maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
        ],
      ),
    );
  }
}

class _FuncionalGmailCard extends ConsumerWidget {
  const _FuncionalGmailCard({required this.statusAsync});

  final AsyncValue<GmailConnectionStatus> statusAsync;

  Future<void> _connect(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(gmailConnectionRepositoryProvider).connect();
      ref.invalidate(gmailConnectionStatusProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível conectar o Gmail. Tente novamente.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return statusAsync.when(
      data: (status) {
        if (!status.connected) {
          return Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.outline, width: 1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.mail_outline, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Email', style: TextStyle(fontWeight: FontWeight.w500)),
                      const Text('Conectar', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: () => _connect(context, ref),
                  child: const Text('Conectar'),
                ),
              ],
            ),
          );
        }
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outline, width: 1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.mail_outline, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Email', style: TextStyle(fontWeight: FontWeight.w500)),
                    Text(status.gmailEmail ?? 'Email não disponível', style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Icon(Icons.check_circle, size: 20, color: Colors.green[600]),
            ],
          ),
        );
      },
      loading: () => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline, width: 1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          children: [
            Icon(Icons.mail_outline, size: 20),
            SizedBox(width: 10),
            Expanded(child: Text('Email')),
          ],
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _FuncionalFinancasCard extends ConsumerWidget {
  const _FuncionalFinancasCard({required this.connectionsAsync});

  final AsyncValue<List<FinanceConnection>> connectionsAsync;

  Future<void> _connect(BuildContext context, WidgetRef ref) async {
    final isFirstConnection = connectionsAsync.value?.isEmpty ?? true;
    try {
      final connectToken = await ref.read(financeConnectionRepositoryProvider).createConnectToken();
      if (!context.mounted) return;
      final itemId = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => PluggyConnectWebviewScreen(connectToken: connectToken)),
      );
      if (itemId == null) return;
      await ref.read(financeConnectionRepositoryProvider).finalizeConnection(itemId);
      ref.invalidate(financeConnectionsProvider);
      if (isFirstConnection && context.mounted) {
        await _promptDiaRecebimento(context, ref);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível conectar sua conta. Tente novamente.')),
        );
      }
    }
  }

  Future<void> _promptDiaRecebimento(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final dia = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Em que dia do mês você costuma receber?'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Ex: 5'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Agora não')),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, int.tryParse(controller.text.trim())),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (dia == null || dia < 1 || dia > 31) return;

    try {
      await ref.read(diaRecebimentoRepositoryProvider).update(dia);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return connectionsAsync.when(
      data: (connections) {
        if (connections.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.outline, width: 1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_balance_outlined, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Finanças', style: TextStyle(fontWeight: FontWeight.w500)),
                      const Text('Conectar', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: () => _connect(context, ref),
                  child: const Text('Conectar'),
                ),
              ],
            ),
          );
        }
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outline, width: 1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.account_balance_outlined, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Finanças', style: TextStyle(fontWeight: FontWeight.w500)),
                    Text('${connections.length} conta(s)', style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              Icon(Icons.check_circle, size: 20, color: Colors.green[600]),
            ],
          ),
        );
      },
      loading: () => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline, width: 1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          children: [
            Icon(Icons.account_balance_outlined, size: 20),
            SizedBox(width: 10),
            Expanded(child: Text('Finanças')),
          ],
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _FuncionalBiofeedbackCard extends ConsumerWidget {
  const _FuncionalBiofeedbackCard({required this.ativoAsync});

  final AsyncValue<bool> ativoAsync;

  Future<void> _ativar(BuildContext context, WidgetRef ref) async {
    try {
      final autorizado = await ref.read(biofeedbackHealthServiceProvider).solicitarPermissao();
      if (!autorizado) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Permissão não concedida. Você pode tentar novamente quando quiser.'),
            ),
          );
        }
        return;
      }
      await ref.read(biofeedbackCacheProvider).setAtivo(true);
      await ref
          .read(biofeedbackCacheProvider)
          .setPermissoesVersao(BiofeedbackCache.versaoPermissoesAtual);
      final frequenciaMinutos = await ref.read(biofeedbackCacheProvider).getFrequenciaMinutos();
      await ref.read(biofeedbackBackgroundTaskProvider).registrar(Duration(minutes: frequenciaMinutos));
      try {
        await ref.read(biofeedbackSyncServiceProvider).sincronizar();
      } catch (_) {}
      ref.invalidate(biofeedbackAtivoProvider);
      ref.invalidate(biofeedbackResumoProvider);
      ref.invalidate(biofeedbackDiasNoHistoricoProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível ativar o Biofeedback. Tente novamente.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ativoAsync.when(
      data: (ativo) {
        if (!ativo) {
          return Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.outline, width: 1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.favorite_border, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Biofeedback', style: TextStyle(fontWeight: FontWeight.w500)),
                      const Text('Ativar', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: () => _ativar(context, ref),
                  child: const Text('Ativar'),
                ),
              ],
            ),
          );
        }
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outline, width: 1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.favorite_border, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Biofeedback', style: TextStyle(fontWeight: FontWeight.w500)),
                    const Text('Ativo', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              Icon(Icons.check_circle, size: 20, color: Colors.green[600]),
            ],
          ),
        );
      },
      loading: () => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline, width: 1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          children: [
            Icon(Icons.favorite_border, size: 20),
            SizedBox(width: 10),
            Expanded(child: Text('Biofeedback')),
          ],
        ),
      ),
      error: (_, __) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline, width: 1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.favorite_border, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Biofeedback', style: TextStyle(fontWeight: FontWeight.w500)),
                  const Text('Ativar', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: () => _ativar(context, ref),
              child: const Text('Ativar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FuncionalProfessionalsCard extends StatelessWidget {
  const _FuncionalProfessionalsCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.medical_services_outlined, size: 20),
          const SizedBox(width: 10),
          const Expanded(child: Text('Profissionais')),
          Icon(Icons.chevron_right, size: 20, color: Colors.grey[600]),
        ],
      ),
    );
  }
}

class _FuncionalGroundingCardsCard extends StatelessWidget {
  const _FuncionalGroundingCardsCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.self_improvement_outlined, size: 20),
          const SizedBox(width: 10),
          const Expanded(child: Text('Alívio sensorial')),
          Icon(Icons.chevron_right, size: 20, color: Colors.grey[600]),
        ],
      ),
    );
  }
}
