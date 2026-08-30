import 'package:flutter/material.dart';
import 'app_card.dart';

/// Tela de demonstração do componente AppCard.
/// Exibe todas as variantes, estados e comportamentos para validação interativa.
class AppCardDemo extends StatefulWidget {
  const AppCardDemo({super.key});

  @override
  State<AppCardDemo> createState() => _AppCardDemoState();
}

class _AppCardDemoState extends State<AppCardDemo> {
  late Set<int> selectedCards;

  @override
  void initState() {
    super.initState();
    selectedCards = {};
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AppCard Demo'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Seção: Variantes
            _buildSection('Variantes', [
              // Variante Elevado (com sombra)
              AppCard(
                title: 'Card Elevado',
                subtitle: 'Com sombra sutil — feedback de elevação clara',
                icon: Icons.card_travel,
                variant: AppCardVariant.elevated,
              ),
              const SizedBox(height: 16.0),

              // Variante Plano (com border)
              AppCard(
                title: 'Card Plano',
                subtitle: 'Com border — estilo outline, mais minimalista',
                icon: Icons.rectangle,
                variant: AppCardVariant.flat,
              ),
            ]),

            const SizedBox(height: 32.0),

            // Seção: Com Conteúdo Variado
            _buildSection('Com Conteúdo Variado', [
              // Card com ícone, subtitle e ações
              AppCard(
                title: 'Email Importante',
                subtitle: 'Vence em 5 dias',
                icon: Icons.mail,
                iconColor: Theme.of(context).colorScheme.primary,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () => _showSnackBar('Editando...'),
                    tooltip: 'Editar',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () => _showSnackBar('Deletado!'),
                    tooltip: 'Deletar',
                  ),
                ],
                onTap: () => _showSnackBar('Card tapped!'),
                variant: AppCardVariant.elevated,
              ),
              const SizedBox(height: 16.0),

              // Card com conteúdo custom (child)
              AppCard(
                title: 'Saldo em Conta',
                variant: AppCardVariant.flat,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'R\$ 1.234,56',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 8.0),
                    Text(
                      'Última atualização: Hoje às 14:30',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ]),

            const SizedBox(height: 32.0),

            // Seção: Estados
            _buildSection('Estados', [
              // Card Normal
              AppCard(
                title: 'Card Normal',
                subtitle: 'Estado padrão — não selecionado',
                variant: AppCardVariant.elevated,
              ),
              const SizedBox(height: 16.0),

              // Card Selecionado
              AppCard(
                title: 'Card Selecionado',
                subtitle: 'Estado selecionado — border/sombra mais proeminentes',
                selected: true,
                variant: AppCardVariant.elevated,
              ),
              const SizedBox(height: 16.0),

              // Card Desabilitado
              AppCard(
                title: 'Card Desabilitado',
                subtitle: 'Opacidade reduzida, não tátil',
                enabled: false,
                variant: AppCardVariant.elevated,
              ),
            ]),

            const SizedBox(height: 32.0),

            // Seção: Seleção Múltipla (Toggle)
            _buildSection('Seleção Múltipla (Toggle)', [
              for (int i = 1; i <= 3; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: AppCard(
                    title: 'Card $i',
                    subtitle: 'Toque para selecionar',
                    icon: Icons.check_circle,
                    selected: selectedCards.contains(i),
                    onTap: () => setState(() {
                      if (selectedCards.contains(i)) {
                        selectedCards.remove(i);
                      } else {
                        selectedCards.add(i);
                      }
                    }),
                    variant: AppCardVariant.flat,
                  ),
                ),
            ]),

            const SizedBox(height: 32.0),

            // Seção: Dark Mode
            _buildSection('Dark Mode', [
              Text(
                isDarkMode
                    ? 'Dark mode ativo — cards visíveis contra fundo (contraste OK)'
                    : 'Light mode ativo — paleta clara e suave',
                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              ),
              const SizedBox(height: 12.0),
              AppCard(
                title: 'Tema Ativo',
                subtitle: 'Observe a visibilidade e contraste em ambos os modos',
                variant: AppCardVariant.elevated,
              ),
            ]),

            const SizedBox(height: 32.0),

            // Seção: Espaçamento
            _buildSection('Espaçamento (gap >= 16 dp)', [
              Text(
                'Os cards abaixo têm gap de 16 dp entre eles — sem sobreposição',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16.0),
              AppCardGroup(
                cards: [
                  AppCard(
                    title: 'Card A',
                    subtitle: 'Gap: 16 dp',
                    variant: AppCardVariant.elevated,
                  ),
                  AppCard(
                    title: 'Card B',
                    subtitle: 'Gap: 16 dp',
                    variant: AppCardVariant.elevated,
                  ),
                  AppCard(
                    title: 'Card C',
                    subtitle: 'Gap: 16 dp',
                    variant: AppCardVariant.elevated,
                  ),
                ],
                isColumn: true,
              ),
            ]),

            const SizedBox(height: 32.0),

            // Seção: Hierarquia
            _buildSection('Hierarquia Textual', [
              AppCard(
                title: 'Título Proeminente',
                subtitle: 'Subtítulo menor — diferença clara de tamanho/peso',
                icon: Icons.layers,
                variant: AppCardVariant.flat,
              ),
              const SizedBox(height: 16.0),
              AppCard(
                title: 'Com Conteúdo Custom',
                variant: AppCardVariant.elevated,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Esse é um heading de conteúdo interno',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8.0),
                    Text(
                      'Esse é um parágrafo corpo — com line-height generoso para legibilidade.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
                    ),
                  ],
                ),
              ),
            ]),

            const SizedBox(height: 32.0),

            // Seção: Overflow Handling
            _buildSection('Sem Overflow — Content Respira', [
              AppCard(
                title: 'Texto longo no título que pode quebrar para duas linhas sem truncamento',
                subtitle:
                    'Subtítulo também pode quebrar naturalmente para múltiplas linhas quando necessário, sempre respeitando hierarquia',
                icon: Icons.text_fields,
                variant: AppCardVariant.flat,
              ),
            ]),

            const SizedBox(height: 32.0),
          ],
        ),
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12.0),
        ...children,
      ],
    );
  }
}
