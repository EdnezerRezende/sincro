# Segmento 15 — Onboarding Anamnese Wizard

- **Onda**: 3
- **Depende de**: 04-component-chip, 01-component-button, 08-scaffold-layout
- **Escopo de arquivos**: `mobile/lib/features/onboarding/anamnese/anamnese_wizard_screen.dart`

## Entregável
Wizard de anamnese redesenhado com:
- Progress bar visual (step 1 de 4, 2 de 4, etc)
- Título claro para cada step
- Chips selecionáveis para opções (não radio buttons com texto longos)
- Botões Next/Back bem espaçados
- Sumário visual no final antes de confirmar
- Sem texto obrigatório (apenas cliques)

## Critérios de aceitação
1. Progress bar mostra step atual (ex: "Passo 2 de 4")
2. Título de cada step é claro (ex: "Qual sua tolerância a notificações?")
3. Chips selecionáveis são bem espaçados (não aperto)
4. Máx 3-4 chips por passo
5. Botão Next/Back são primários e estão no rodapé
6. Sumário final mostra todas as seleções antes de confirmar
7. Nenhum texto longo (máx 2 frases por pergunta)
8. Dark mode funciona
9. Transição entre steps é suave (slide, fade)
10. Usuário pode voltar e editar qualquer step antes de confirmar

## Benchmark
Wizard bem feito tipo Notion onboarding, Figma setup. Progresso claro, sem overhead.

## Método de verificação
- Nível: 3 (interactive + navigation)
- Ferramenta: App emulador, teste de múltiplos steps, voltar/editar

### Roteiro de experiência
1. Abrir app novo (pós-login, antes de home)
2. Ver wizard (progress bar visível? Título claro?)
3. Selecionar opções (chips respondem ao toque?)
4. Clicar Next → step 2 aparece?
5. Clicar Back → volta ao step 1?
6. Editar seleção anterior → funciona?
7. Ir até step 4 (sumário) → todas seleções aparecem?
8. Confirmar → onboarding completa?

## Histórico de notas
| Rodada | Nota | Status |
|---|---|---|
| 1 | — | pending |
