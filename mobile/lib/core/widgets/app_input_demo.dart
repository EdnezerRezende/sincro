import 'package:flutter/material.dart';
import 'app_input.dart';

/// Demo de todos os estados do AppInput para validação e teste.
/// Use esta screen para verificar:
/// 1. Label é sempre visível
/// 2. Focus state tem cor clara (border, shadow, cor)
/// 3. Error state é visível (texto vermelho, ícone, border vermelha)
/// 4. Placeholder é cinza/opaco (distinção clara do texto digitado)
/// 5. Altura >= 48 dp
/// 6. Sem text overflow — trunca ou wraps sensatamente
/// 7. Ícone clear ou show-password tem tamanho tátil (24x24 mínimo)
/// 8. Dark mode: focus/error cores ainda legíveis
class AppInputDemoScreen extends StatefulWidget {
  const AppInputDemoScreen({super.key});

  @override
  State<AppInputDemoScreen> createState() => _AppInputDemoScreenState();
}

class _AppInputDemoScreenState extends State<AppInputDemoScreen> {
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  String? _emailError;
  String? _passwordError;

  @override
  void dispose() {
    _textController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _validateEmail() {
    final email = _emailController.text;
    if (email.isEmpty) {
      setState(() => _emailError = 'Email é obrigatório');
    } else if (!email.contains('@')) {
      setState(() => _emailError = 'Email inválido');
    } else {
      setState(() => _emailError = null);
    }
  }

  void _validatePassword() {
    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() => _passwordError = 'Senha é obrigatória');
    } else if (password.length < 8) {
      setState(() => _passwordError = 'Senha deve ter mínimo 8 caracteres');
    } else {
      setState(() => _passwordError = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AppInput Demo')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 24.0,
          children: [
            // Seção: Default State
            _buildSection(
              title: 'Default State',
              description: 'Input vazio, sem foco. Label visível, placeholder claro.',
              child: AppInput(
                label: 'Nome completo',
                placeholder: 'Digite seu nome',
                onChanged: (value) {},
              ),
            ),

            // Seção: Focused State
            _buildSection(
              title: 'Focused State',
              description: 'Focus state com border + shadow em cor primária.',
              child: AppInput(
                label: 'Email',
                placeholder: 'seu@email.com',
                keyboardType: TextInputType.emailAddress,
                autofocus: true,
              ),
            ),

            // Seção: Filled State
            _buildSection(
              title: 'Filled State',
              description: 'Texto digitado, placeholder desaparece, label escuro.',
              child: AppInput(
                label: 'Cidade',
                placeholder: 'Digite sua cidade',
                controller: TextEditingController(text: 'São Paulo'),
              ),
            ),

            // Seção: Error State
            _buildSection(
              title: 'Error State',
              description: 'Border vermelha, label vermelha, error message clara abaixo.',
              child: AppInput(
                label: 'Email',
                placeholder: 'seu@email.com',
                error: 'Email inválido ou já utilizado',
                keyboardType: TextInputType.emailAddress,
              ),
            ),

            // Seção: Disabled State
            _buildSection(
              title: 'Disabled State',
              description: 'Visualmente morto, opacidade reduzida, não interativo.',
              child: AppInput(
                label: 'ID do usuário',
                placeholder: '12345',
                controller: TextEditingController(text: 'user_123'),
                enabled: false,
              ),
            ),

            // Seção: With Helper Text
            _buildSection(
              title: 'With Helper Text',
              description: 'Texto auxiliar abaixo do input.',
              child: AppInput(
                label: 'Telefone',
                placeholder: '(11) 9 8765-4321',
                keyboardType: TextInputType.phone,
                helperText: 'Formato: (XX) XXXXX-XXXX',
              ),
            ),

            // Seção: Suffix Icon - Clear
            _buildSection(
              title: 'Suffix Icon - Clear',
              description: 'Ícone clear (X) aparece quando há texto. 40x40 min.',
              child: AppInput(
                label: 'Buscar',
                placeholder: 'Digite para buscar...',
                suffixIcon: AppInputSuffixIcon.clear,
                controller: _textController,
                onChanged: (value) => setState(() {}),
              ),
            ),

            // Seção: Suffix Icon - Show/Hide Password
            _buildSection(
              title: 'Suffix Icon - Show/Hide Password',
              description: 'Ícone olho para toggle password visibility.',
              child: AppInput(
                label: 'Senha',
                placeholder: 'Mínimo 8 caracteres',
                obscureText: true,
                suffixIcon: AppInputSuffixIcon.showPassword,
                controller: _passwordController,
              ),
            ),

            // Seção: Suffix Icon - Info
            _buildSection(
              title: 'Suffix Icon - Info',
              description: 'Ícone de informação (i).',
              child: AppInput(
                label: 'CPF',
                placeholder: '000.000.000-00',
                suffixIcon: AppInputSuffixIcon.info,
                keyboardType: TextInputType.number,
              ),
            ),

            // Seção: Multi-line
            _buildSection(
              title: 'Multi-line (maxLines: 4)',
              description: 'Texto quebra automaticamente sem truncagem.',
              child: AppInput(
                label: 'Observações',
                placeholder: 'Digite suas observações aqui...',
                maxLines: 4,
                onChanged: (value) {},
              ),
            ),

            // Seção: With Character Count
            _buildSection(
              title: 'With Character Count',
              description: 'Limite de 100 caracteres com contador.',
              child: AppInput(
                label: 'Bio',
                placeholder: 'Conte algo sobre você',
                maxLength: 100,
                showCharacterCount: true,
              ),
            ),

            // Seção: Interactive Email Validation
            _buildSection(
              title: 'Interactive Email Validation',
              description: 'Validação em tempo real ao sair do foco.',
              child: Column(
                spacing: 12.0,
                children: [
                  AppInput(
                    label: 'Email',
                    placeholder: 'seu@email.com',
                    keyboardType: TextInputType.emailAddress,
                    controller: _emailController,
                    error: _emailError,
                    onChanged: (value) {
                      if (_emailError != null) {
                        // Validar enquanto digita se estava em erro
                        _validateEmail();
                      }
                    },
                  ),
                  ElevatedButton(
                    onPressed: _validateEmail,
                    child: const Text('Validar Email'),
                  ),
                ],
              ),
            ),

            // Seção: Interactive Password Validation
            _buildSection(
              title: 'Interactive Password Validation',
              description: 'Validação de força de senha em tempo real.',
              child: Column(
                spacing: 12.0,
                children: [
                  AppInput(
                    label: 'Senha',
                    placeholder: 'Mínimo 8 caracteres',
                    obscureText: true,
                    suffixIcon: AppInputSuffixIcon.showPassword,
                    controller: _passwordController,
                    error: _passwordError,
                    onChanged: (value) {
                      if (_passwordError != null) {
                        // Re-validar enquanto digita
                        _validatePassword();
                      }
                    },
                  ),
                  ElevatedButton(
                    onPressed: _validatePassword,
                    child: const Text('Validar Senha'),
                  ),
                ],
              ),
            ),

            // Seção: Dark Mode Note
            _buildSection(
              title: 'Dark Mode',
              description:
                  'Use o system settings para ativar dark mode. Cores devem permanecer legíveis.',
              child: const Text(
                'Sistema de cores adaptável ao tema claro/escuro.\n\n'
                'Light: Verde floresta (#3F7268), marrom (#A6503A)\n'
                'Dark: Verde claro (#8FBFAE), laranja (#D98872)',
                style: TextStyle(fontSize: 14.0),
              ),
            ),

            const SizedBox(height: 24.0),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required String description,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8.0,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        Text(
          description,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        Container(
          padding: const EdgeInsets.all(12.0),
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
            ),
            borderRadius: BorderRadius.circular(8.0),
          ),
          child: child,
        ),
      ],
    );
  }
}
