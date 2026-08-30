# Segmento 12 — Auth Flow (LoginScreen + SignupScreen)

- **Onda**: 2
- **Depende de**: 01-component-button, 03-component-input, 05-component-modal
- **Escopo de arquivos**: `mobile/lib/features/auth/login_screen.dart`, `mobile/lib/features/auth/signup_screen.dart`

## Entregável
Telas de autenticação redesenhadas com:
- Logo ou branding claro no topo
- Campos de email e senha com labels, placeholders, error states
- Botão login/signup primário e claro
- Link "Criar conta" ou "Já tem conta?" bem visível
- Validação em tempo real (email format, password length)
- Estado loading com spinner
- Error messages claras (ex: "email inválido", "senha muito curta")
- Sem hardcoding de cores (use tema)

## Critérios de aceitação
1. Branding/logo é visível e alegre no topo
2. Campos têm labels claros (não placeholder só)
3. Botão primário é óbvio (cor, tamanho, posição)
4. Link "Criar conta" é bem visível (contraste OK)
5. Validação mostra erro inline (sem submit necessário)
6. Senha mostra/esconde com ícone
7. Teclado numérico em campo de email (mobile)
8. Dark mode funciona
9. Layout centr ado e espaçado (não aperto)
10. Nenhuma hardcoded color (use theme tokens)

## Benchmark
Login/signup moderno tipo Figma, Slack, Linear. Claro, profissional, acessível.

## Método de verificação
- Nível: 3 (interactive + form validation)
- Ferramenta: App emulador, teste de navegação, validação e erro

### Roteiro de experiência
1. Abrir app novo (deve mostrar login screen)
2. Ver layout (logo visível? Campos claros?)
3. Digitar email inválido → error message aparece?
4. Digitar email válido, senha curta → error no campo senha?
5. Clicar signup → navega para signup? (ou alterna inline?)
6. Clicar login com dados inválidos → error claro?
7. Testar show/hide senha → funciona?
8. Dark mode → cores ainda legíveis?

## Histórico de notas
| Rodada | Nota | Status |
|---|---|---|
| 1 | — | pending |
