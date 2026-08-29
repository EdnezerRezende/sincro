import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_providers.dart';
import '../biofeedback/biofeedback_frequencia.dart';
import '../biofeedback/biofeedback_providers.dart';
import '../email_triage/email_triage_providers.dart';
import '../financas/finance_connection.dart';
import '../financas/finance_providers.dart';
import '../home/home_layout_mode.dart';
import '../home/home_providers.dart';
import '../onboarding/anamnese/anamnese_providers.dart';
import '../onboarding/anamnese/anamnese_wizard_screen.dart';
import '../onboarding/onboarding_providers.dart';
import '../trusted_contacts/trusted_contacts_screen.dart';
import '../../core/theme/theme_mode_preference.dart';
import '../home/home_design_style.dart';

/// Resultado do diálogo de dia de recebimento. Existe para separar "cancelou" (o `showDialog`
/// devolve `null`) de "pediu para limpar" (devolve uma instância com `dia == null`).
class _DiaRecebimentoEdicao {
  const _DiaRecebimentoEdicao.salvar(int this.dia);
  const _DiaRecebimentoEdicao.limpar() : dia = null;

  final int? dia;
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _busy = false;

  Future<void> _editSensoryProfile() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AnamneseWizardScreen(isEditing: true)),
    );
  }

  Future<void> _deleteSensoryProfile() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Apagar perfil sensorial?'),
        content: const Text(
          'Suas respostas sobre notificações, gatilhos e tom preferido serão apagadas. '
          'Você pode preenchê-las novamente quando quiser.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Apagar')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(sensoryProfileRepositoryProvider).remove();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Perfil sensorial apagado.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível apagar seu perfil sensorial. Tente novamente.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editHomeLayout() async {
    final atual = await ref.read(homeLayoutPreferenceProvider).getModo();
    if (!mounted) return;

    final escolhido = await showDialog<HomeLayoutMode>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Layout da tela inicial'),
        children: HomeLayoutMode.values.map((m) {
          return RadioListTile<HomeLayoutMode>(
            title: Text(m.label),
            value: m,
            groupValue: atual,
            onChanged: (v) => Navigator.pop(dialogContext, v),
          );
        }).toList(),
      ),
    );
    if (escolhido == null) return;

    await ref.read(homeLayoutPreferenceProvider).setModo(escolhido);
    ref.invalidate(homeLayoutModeProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Layout atualizado.')),
      );
    }
  }

  Future<void> _editThemeMode() async {
    final atual = await ref.read(themeModePreferenceProvider).getMode();
    if (!mounted) return;

    final escolhido = await showDialog<ThemeModePreference>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Tema'),
        children: ThemeModePreference.values.map((t) {
          return RadioListTile<ThemeModePreference>(
            title: Text(t.label),
            value: t,
            groupValue: atual,
            onChanged: (v) => Navigator.pop(dialogContext, v),
          );
        }).toList(),
      ),
    );
    if (escolhido == null) return;

    await ref.read(themeModePreferenceProvider).setMode(escolhido);
    ref.invalidate(themeModeProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tema atualizado.')),
      );
    }
  }

  Future<void> _editDesignStyle() async {
    final atual = await ref.read(homeLayoutPreferenceProvider).getDesign();
    if (!mounted) return;

    final escolhido = await showDialog<HomeDesignStyle>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Estilo de design'),
        children: HomeDesignStyle.values.map((d) {
          return RadioListTile<HomeDesignStyle>(
            title: Text(d.label),
            value: d,
            groupValue: atual,
            onChanged: (v) => Navigator.pop(dialogContext, v),
          );
        }).toList(),
      ),
    );
    if (escolhido == null) return;

    await ref.read(homeLayoutPreferenceProvider).setDesign(escolhido);
    ref.invalidate(homeDesignStyleProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Estilo atualizado.')),
      );
    }
  }

  void _manageContacts() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TrustedContactsScreen()),
    );
  }

  Future<void> _disconnectGmail() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Desconectar Gmail?'),
        content: const Text(
          'O resumo da sua caixa de entrada será apagado. Você pode reconectar quando quiser.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Desconectar')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(gmailConnectionRepositoryProvider).disconnect();
      ref.invalidate(gmailConnectionStatusProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gmail desconectado.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível desconectar o Gmail. Tente novamente.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editDiaRecebimento() async {
    // Lemos o valor atual para o campo já abrir preenchido — antes o diálogo sempre aparecia
    // vazio, sem nenhuma forma de o usuário saber o que já estava configurado.
    int? valorAtual;
    try {
      valorAtual = (await ref.read(usersRepositoryProvider).getMe()).diaRecebimento;
    } catch (_) {
      // Se a leitura falhar, o diálogo abre vazio — não vale bloquear a edição por isso.
    }
    if (!mounted) return;

    final controller = TextEditingController(text: valorAtual?.toString() ?? '');
    final result = await showDialog<_DiaRecebimentoEdicao>(
      context: context,
      builder: (dialogContext) {
        String? errorText;
        // StatefulBuilder para o erro aparecer no próprio diálogo e o diálogo continuar
        // aberto: antes, "Salvar" com o campo vazio devolvia o mesmo `null` de "Cancelar",
        // então um erro de digitação simplesmente não fazia nada, sem nenhum retorno visual.
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Dia de recebimento'),
            content: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Ex: 5 (dia 5 de cada mês)',
                errorText: errorText,
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, const _DiaRecebimentoEdicao.limpar()),
                child: const Text('Limpar'),
              ),
              ElevatedButton(
                onPressed: () {
                  final dia = int.tryParse(controller.text.trim());
                  if (dia == null || dia < 1 || dia > 31) {
                    setDialogState(() => errorText = 'Informe um dia entre 1 e 31.');
                    return;
                  }
                  Navigator.pop(dialogContext, _DiaRecebimentoEdicao.salvar(dia));
                },
                child: const Text('Salvar'),
              ),
            ],
          ),
        );
      },
    );
    controller.dispose();
    if (result == null) return;

    setState(() => _busy = true);
    try {
      await ref.read(diaRecebimentoRepositoryProvider).update(result.dia);
      ref.invalidate(onboardingStatusProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.dia == null ? 'Dia de recebimento removido.' : 'Dia de recebimento salvo.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível salvar. Tente novamente.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnectFinanceConnection(FinanceConnection connection) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Desconectar ${connection.instituicao}?'),
        content: const Text('Os dados dessa conexão serão apagados. Você pode reconectar quando quiser.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Desconectar')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(financeConnectionRepositoryProvider).disconnect(connection.id);
      ref.invalidate(financeConnectionsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${connection.instituicao} desconectado.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível desconectar. Tente novamente.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editBiofeedbackFrequencia() async {
    final atual = await ref.read(biofeedbackCacheProvider).getFrequenciaMinutos();
    if (!mounted) return;

    final escolhida = await showDialog<int>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Frequência de atualização'),
        children: BiofeedbackFrequencia.values.map((f) {
          return RadioListTile<int>(
            title: Text(f.label),
            value: f.duracao.inMinutes,
            groupValue: atual,
            onChanged: (v) => Navigator.pop(dialogContext, v),
          );
        }).toList(),
      ),
    );
    if (escolhida == null) return;

    setState(() => _busy = true);
    try {
      await ref.read(biofeedbackCacheProvider).setFrequenciaMinutos(escolhida);
      final ativo = await ref.read(biofeedbackCacheProvider).isAtivo();
      if (ativo) {
        await ref.read(biofeedbackBackgroundTaskProvider).registrar(Duration(minutes: escolhida));
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Frequência atualizada.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível salvar. Tente novamente.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _alternarAlertasBiofeedback(bool valor) async {
    setState(() => _busy = true);
    try {
      await ref.read(biofeedbackCacheProvider).setAlertasAtivos(valor);
      ref.invalidate(biofeedbackAlertasAtivosProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível salvar. Tente novamente.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _desativarBiofeedback() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Desativar Biofeedback?'),
        content: const Text(
          'Os dados de frequência cardíaca guardados no app serão apagados. '
          'Você pode ativar novamente quando quiser.\n\n'
          'A permissão de acesso à saúde continua concedida no sistema: o app não consegue '
          'revogá-la sozinho. Se quiser removê-la, faça isso no HealthKit (Ajustes > Saúde) ou '
          'no Health Connect do seu aparelho.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Desativar')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(biofeedbackBackgroundTaskProvider).cancelar();
      await ref.read(biofeedbackCacheProvider).clear();
      ref.invalidate(biofeedbackAtivoProvider);
      ref.invalidate(biofeedbackResumoProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Biofeedback desativado.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível desativar. Tente novamente.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    try {
      await ref.read(authServiceProvider).signOut();
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível sair. Tente novamente.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final connectionsAsync = ref.watch(financeConnectionsProvider);
    final biofeedbackAtivo = ref.watch(biofeedbackAtivoProvider).maybeWhen(
          data: (ativo) => ativo,
          orElse: () => false,
        );
    final biofeedbackAlertasAtivos = ref.watch(biofeedbackAlertasAtivosProvider).maybeWhen(
          data: (ativos) => ativos,
          orElse: () => true,
        );
    final isAdmin = ref.watch(onboardingStatusProvider).maybeWhen(
          data: (status) => status.isAdmin,
          orElse: () => false,
        );
    final financeConnectionTiles = connectionsAsync.maybeWhen(
      data: (connections) => connections
          .map(
            (c) => ListTile(
              leading: const Icon(Icons.account_balance_outlined),
              title: Text('Desconectar ${c.instituicao}'),
              onTap: _busy ? null : () => _disconnectFinanceConnection(c),
            ),
          )
          .toList(),
      orElse: () => <Widget>[],
    );

    final destructiveColor = Theme.of(context).colorScheme.error;

    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: ListView(
        children: [
          const _SectionHeader('Perfil & Preferências'),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Editar perfil sensorial'),
            onTap: _busy ? null : _editSensoryProfile,
          ),
          ListTile(
            leading: const Icon(Icons.dashboard_customize_outlined),
            title: const Text('Layout da tela inicial'),
            onTap: _busy ? null : _editHomeLayout,
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Estilo de design'),
            onTap: _busy ? null : _editDesignStyle,
          ),
          ListTile(
            leading: const Icon(Icons.brightness_4_outlined),
            title: const Text('Tema'),
            onTap: _busy ? null : _editThemeMode,
          ),
          ListTile(
            leading: const Icon(Icons.people_outline),
            title: const Text('Gerenciar contatos de confiança'),
            onTap: _busy ? null : _manageContacts,
          ),
          ListTile(
            leading: Icon(Icons.delete_outline, color: destructiveColor),
            title: const Text('Apagar perfil sensorial'),
            onTap: _busy ? null : _deleteSensoryProfile,
          ),
          const _SectionHeader('Conexões'),
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: const Text('Desconectar Gmail'),
            onTap: _busy ? null : _disconnectGmail,
          ),
          ListTile(
            leading: const Icon(Icons.calendar_today_outlined),
            title: const Text('Definir dia de recebimento'),
            onTap: _busy ? null : _editDiaRecebimento,
          ),
          ...financeConnectionTiles,
          // Ambos os itens só fazem sentido com o Biofeedback ativo: a frequência só governa o
          // agendamento em background, que nem existe enquanto o pilar está desativado.
          if (biofeedbackAtivo) ...[
            const _SectionHeader('Biofeedback'),
            ListTile(
              leading: const Icon(Icons.favorite_border),
              title: const Text('Frequência do Biofeedback'),
              onTap: _busy ? null : _editBiofeedbackFrequencia,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.notifications_outlined),
              title: const Text('Alertas de estresse'),
              value: biofeedbackAlertasAtivos,
              onChanged: _busy ? null : _alternarAlertasBiofeedback,
            ),
            ListTile(
              leading: Icon(Icons.favorite_border, color: destructiveColor),
              title: const Text('Desativar Biofeedback'),
              onTap: _busy ? null : _desativarBiofeedback,
            ),
          ],
          if (isAdmin) ...[
            const _SectionHeader('Administração'),
            ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: const Text('Gerenciar profissionais (admin)'),
              onTap: _busy
                  ? null
                  : () => Navigator.of(context).pushNamed('/admin/professionals'),
            ),
            ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: const Text('Gerenciar cartões de aterramento (admin)'),
              onTap: _busy
                  ? null
                  : () => Navigator.of(context).pushNamed('/admin/grounding-cards'),
            ),
          ],
          const _SectionHeader('Conta'),
          ListTile(
            leading: Icon(Icons.logout, color: destructiveColor),
            title: const Text('Sair'),
            onTap: _busy ? null : _signOut,
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
      ),
    );
  }
}
