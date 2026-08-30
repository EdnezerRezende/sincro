import 'package:flutter/material.dart';
import 'app_button.dart';

/// Tela de demonstração do componente AppButton.
/// Exibe todas as variantes, tamanhos e estados para validação interativa.
class AppButtonDemo extends StatefulWidget {
  const AppButtonDemo({Key? key}) : super(key: key);

  @override
  State<AppButtonDemo> createState() => _AppButtonDemoState();
}

class _AppButtonDemoState extends State<AppButtonDemo> {
  bool _isLoadingPrimary = false;
  bool _isLoadingSecondary = false;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AppButton Demo'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Seção: Variantes + Tamanhos
            _buildSection('Variantes x Tamanhos', [
              // Primary
              _buildVariantSection('Primary', AppButtonVariant.primary, isDarkMode),

              const SizedBox(height: 24.0),

              // Secondary
              _buildVariantSection('Secondary', AppButtonVariant.secondary, isDarkMode),

              const SizedBox(height: 24.0),

              // Outline
              _buildVariantSection('Outline', AppButtonVariant.outline, isDarkMode),

              const SizedBox(height: 24.0),

              // Text
              _buildVariantSection('Text', AppButtonVariant.text, isDarkMode),
            ]),

            const SizedBox(height: 32.0),

            // Seção: Estados
            _buildSection('Estados', [
              const Text(
                'Normal (acima)',
                style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              ),
              const SizedBox(height: 12.0),

              // Disabled
              _buildStateRow(
                'Disabled',
                [
                  AppButton(
                    label: 'Desabilitado',
                    onPressed: null,
                    size: AppButtonSize.medium,
                    variant: AppButtonVariant.primary,
                  ),
                  AppButton(
                    label: 'Desabilitado',
                    onPressed: null,
                    size: AppButtonSize.medium,
                    variant: AppButtonVariant.outline,
                  ),
                ],
              ),

              const SizedBox(height: 12.0),

              // Loading
              _buildStateRow(
                'Loading',
                [
                  AppButton(
                    label: 'Processando...',
                    isLoading: _isLoadingPrimary,
                    onPressed: _isLoadingPrimary ? null : () {
                      setState(() => _isLoadingPrimary = true);
                      Future.delayed(const Duration(seconds: 2), () {
                        if (mounted) setState(() => _isLoadingPrimary = false);
                      });
                    },
                    variant: AppButtonVariant.primary,
                    size: AppButtonSize.medium,
                  ),
                  AppButton(
                    label: 'Processando...',
                    isLoading: _isLoadingSecondary,
                    onPressed: _isLoadingSecondary ? null : () {
                      setState(() => _isLoadingSecondary = true);
                      Future.delayed(const Duration(seconds: 2), () {
                        if (mounted) setState(() => _isLoadingSecondary = false);
                      });
                    },
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.medium,
                  ),
                ],
              ),
            ]),

            const SizedBox(height: 32.0),

            // Seção: Com Ícones
            _buildSection('Com Ícones', [
              _buildIconRow('Ícone à Esquerda', false),
              const SizedBox(height: 12.0),
              _buildIconRow('Ícone à Direita', true),
            ]),

            const SizedBox(height: 32.0),

            // Seção: Helpers (syntactic sugar)
            _buildSection('Helpers Semânticos', [
              const Text(
                'PrimaryButton, SecondaryButton, OutlineButton, TextButtonApp',
                style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              ),
              const SizedBox(height: 12.0),
              Row(
                children: [
                  Expanded(
                    child: PrimaryButton(
                      label: 'PrimaryButton',
                      onPressed: () {},
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  Expanded(
                    child: OutlineButton(
                      label: 'OutlineButton',
                      onPressed: () {},
                    ),
                  ),
                ],
              ),
            ]),

            const SizedBox(height: 32.0),

            // Seção: Dark Mode
            _buildSection('Dark Mode', [
              Text(
                isDarkMode
                    ? 'Dark mode ativo — cores legíveis e contrastes mantidos'
                    : 'Light mode ativo — paleta clara e suave',
                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              ),
              const SizedBox(height: 12.0),
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: 'Tema ativo',
                      onPressed: () {},
                      variant: AppButtonVariant.primary,
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  Expanded(
                    child: AppButton(
                      label: 'Teste aqui',
                      onPressed: () {},
                      variant: AppButtonVariant.outline,
                    ),
                  ),
                ],
              ),
            ]),

            const SizedBox(height: 32.0),

            // Seção: Touch Target (48x48 mínimo)
            _buildSection('Touch Target (48 dp min)', [
              const Text(
                'Todos os tamanhos (small, medium, large) respeitam mínimo 48x48 dp de toque.',
                style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              ),
              const SizedBox(height: 12.0),
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: 'Small',
                      onPressed: () {},
                      size: AppButtonSize.small,
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  Expanded(
                    child: AppButton(
                      label: 'Medium',
                      onPressed: () {},
                      size: AppButtonSize.medium,
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  Expanded(
                    child: AppButton(
                      label: 'Large',
                      onPressed: () {},
                      size: AppButtonSize.large,
                    ),
                  ),
                ],
              ),
            ]),

            const SizedBox(height: 32.0),
          ],
        ),
      ),
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

  Widget _buildVariantSection(
    String variantName,
    AppButtonVariant variant,
    bool isDarkMode,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          variantName,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8.0),
        // Small
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: 'Small',
                onPressed: () {},
                variant: variant,
                size: AppButtonSize.small,
              ),
            ),
            const SizedBox(width: 8.0),
            Expanded(
              child: AppButton(
                label: 'Small Icon',
                onPressed: () {},
                variant: variant,
                size: AppButtonSize.small,
                icon: Icons.check,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8.0),
        // Medium
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: 'Medium',
                onPressed: () {},
                variant: variant,
                size: AppButtonSize.medium,
              ),
            ),
            const SizedBox(width: 8.0),
            Expanded(
              child: AppButton(
                label: 'Medium Icon',
                onPressed: () {},
                variant: variant,
                size: AppButtonSize.medium,
                icon: Icons.add,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8.0),
        // Large
        AppButton(
          label: 'Large',
          onPressed: () {},
          variant: variant,
          size: AppButtonSize.large,
        ),
      ],
    );
  }

  Widget _buildStateRow(String label, List<Widget> buttons) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        ),
        const SizedBox(height: 8.0),
        Row(
          children: [
            for (int i = 0; i < buttons.length; i++) ...[
              Expanded(child: buttons[i]),
              if (i < buttons.length - 1) const SizedBox(width: 8.0),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildIconRow(String label, bool iconAfterLabel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        ),
        const SizedBox(height: 8.0),
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: 'Guardar',
                onPressed: () {},
                icon: Icons.save,
                iconAfterLabel: iconAfterLabel,
                variant: AppButtonVariant.primary,
              ),
            ),
            const SizedBox(width: 8.0),
            Expanded(
              child: AppButton(
                label: 'Cancelar',
                onPressed: () {},
                icon: Icons.close,
                iconAfterLabel: iconAfterLabel,
                variant: AppButtonVariant.outline,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
