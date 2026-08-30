# Segmento 16 — Email Inbox (List + Detail)

- **Onda**: 3
- **Depende de**: 02-component-card, 08-scaffold-layout, 10-error-state
- **Escopo de arquivos**: `mobile/lib/features/email_triage/inbox_screen.dart`, `mobile/lib/features/email_triage/email_detail_screen.dart`

## Entregável
Email inbox redesenhada com:
- Lista de emails em cards espaçados
- Categoria visual: "Precisa Atenção" (vermelho/destaque) vs "Pode Esperar" (cinza)
- Remetente, assunto, resumo curto, data recebida
- Ícone de status (não lido, importante, etc)
- Detail screen com email completo
- Botão "Responder" ou "Arquivar" bem visível
- Conexão Gmail mostra status (conectado/desconectado)

## Critérios de aceitação
1. Emails "Precisa Atenção" têm destaque visual (cor, ícone)
2. Emails "Pode Esperar" são cinzas mas legíveis
3. Card de email é espaçado (gap >= 16 dp entre eles)
4. Remetente e assunto são claros (truncam se muito longos)
5. Resumo curto é truncado inteligentemente (elipsis ou wrap 2 linhas)
6. Data é legível (ex: "Hoje 14h", "Ontem", "2 dias atrás")
7. Clique em card → detail screen com email completo
8. Status de conexão Gmail é claro (icon + text "Conectado" ou "Desconectar")
9. Dark mode funciona
10. Swipe delete ou botão delete com confirmação

## Benchmark
Email inbox moderno tipo Inbox by Gmail, Apple Mail. Claro, categor izado, profissional.

## Método de verificação
- Nível: 3 (interactive + API mocking)
- Ferramenta: App emulador + mock alguns emails de teste

### Roteiro de experiência
1. Abrir app, navegar para Email tab
2. Ver inbox vazia (empty state?) ou com emails
3. Tirar screenshot (categoria visual clara?)
4. Clicar em email → detail screen aparece?
5. Observar: remetente, assunto, corpo legível?
6. Voltar à inbox → lista intacta?
7. Observar status de conexão Gmail (conectado?)
8. Dark mode → cores claras?

## Histórico de notas
| Rodada | Nota | Status |
|---|---|---|
| 1 | — | pending |
