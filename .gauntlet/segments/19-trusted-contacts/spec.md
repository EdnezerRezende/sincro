# Segmento 19 — Trusted Contacts (Rede de Apoio)

- **Onda**: 3
- **Depende de**: 02-component-card, 01-component-button, 08-scaffold-layout
- **Escopo de arquivos**: `mobile/lib/features/trusted_contacts/trusted_contacts_screen.dart`, `mobile/lib/features/trusted_contacts/add_contact_screen.dart`

## Entregável
Trusted contacts screen redesenhada com:
- Lista de contatos em cards espaçados
- Cada card tem: nome, relação (familiar/profissional), telefone/email
- Botão "Avisar" por contato ou "Avisar Todos"
- Botão adicionar novo contato bem visível
- Edit/delete por contato
- Empty state se nenhum contato

## Critérios de aceitação
1. Cards de contato são espaçados (gap >= 16 dp)
2. Informações (nome, relação, telefone) são legíveis
3. Botão "Avisar" é primário (cor, tamanho)
4. Botão adicionar novo é flutuante ou no topo (bem visível)
5. Edit/delete são acessíveis (swipe ou menu)
6. Delete pede confirmação (modal com warning)
7. Empty state é claro (com CTA "Adicionar Primeiro Contato")
8. Add contact form tem campos claros (nome, relação, telefone)
9. Dark mode funciona
10. Validação de telefone/email é clara (error inline)

## Benchmark
Contatos estilo Apple, WhatsApp. Limpo, bem organizado, acessível.

## Método de verificação
- Nível: 3 (interactive)
- Ferramenta: App emulador, teste de adicionar/editar/deletar

### Roteiro de experiência
1. Abrir Trusted Contacts (pós-onboarding)
2. Ver empty state (claro? CTA visível?)
3. Clicar "Adicionar" → form aparece?
4. Preencher nome, relação, telefone → validação inline?
5. Salvar → contato aparece na lista?
6. Clicar "Avisar" → abre WhatsApp com mensagem?
7. Swipe/menu delete → pede confirmação?
8. Dark mode → tudo legível?

## Histórico de notas
| Rodada | Nota | Status |
|---|---|---|
| 1 | — | pending |
