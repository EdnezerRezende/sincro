# Sincro — Gestão Executiva: Rascunhos de Resposta por IA + Agenda

## Contexto

O pilar de Gestão Executiva tem sua primeira fase implementada e revisada
(`docs/superpowers/specs/2026-08-02-gestao-executiva-triagem-email-design.md`): conecta o Gmail,
classifica e-mails como `PRECISA_ATENCAO`/`PODE_ESPERAR`, e mostra um resumo calmo somente-leitura.
Aquele documento listou explicitamente como fora de escopo, para uma fase futura: *"Geração de
rascunhos de resposta por IA"* e *"Extração de compromissos/eventos para a agenda"*.

Este documento especifica essa fase seguinte por inteiro — as duas fatias juntas, decisão
explícita do usuário, já que no fluxo real elas formam um único pipeline (e-mail → rascunho →
envio → extração de compromisso → confirmação no calendário), não dois recursos independentes.

Ao contrário da Fase 1 (só leitura), esta fase introduz duas ações que alteram o mundo fora do
Sincro — enviar um e-mail de verdade e criar um evento real no Google Calendar da pessoa — e por
isso exige escopos OAuth novos, mais sensíveis, que a Fase 1 nunca pediu.

## Objetivo desta fase

Ao final desta fase, para um e-mail classificado como `PRECISA_ATENCAO`, o usuário deve poder:

1. Abrir uma tela de detalhe do e-mail (nova — a Fase 1 não tem nenhuma tela de toque) e ver 3
   rascunhos de resposta gerados pela IA (tons: Curto/Direto, Formal, Padrão), gerados sob demanda
   na hora que a tela abre.
2. Escolher um rascunho, editá-lo livremente, e enviá-lo de verdade pelo Gmail — sem sair do
   Sincro.
3. Ver, imediatamente após o envio, uma sugestão de compromisso (título, data/hora, antecedência)
   quando a IA identificar uma promessa de prazo/reunião no texto enviado — e confirmar essa
   sugestão com um toque, criando um evento real no Google Calendar com lembretes configurados.
4. Reconectar o Gmail (mesmo botão da Fase 1, agora pedindo escopos adicionais) para habilitar
   essas duas capacidades, caso já tenha conectado antes desta fase existir.

## Fora de escopo

- **Extrair compromisso do e-mail original recebido.** Só a resposta que o usuário efetivamente
  envia pelo Sincro é analisada — não o e-mail que a pessoa recebeu. Reduz a superfície de falsos
  positivos (qualquer menção casual a uma data em qualquer e-mail recebido viraria sugestão de
  agenda) e mantém a extração ligada a um compromisso que o próprio usuário assumiu.
- **Adicionar o remetente como convidado do evento.** O evento é só para o próprio usuário — evita
  notificar terceiros sem consentimento explícito deles.
- **Editar ou cancelar, pelo Sincro, um evento já confirmado.** Uma vez criado, o evento passa a
  ser responsabilidade do Google Calendar nativo da pessoa; o Sincro não gerencia o ciclo de vida
  dele depois de criado.
- **Suporte a Outlook/Microsoft Graph** — mesma decisão já tomada na Fase 1 deste pilar.
- **Diferenciação por `plano` (`simples`/`pro`)** — disponível igual para todos, mesma postura da
  Fase 1.
- **Anexos ou HTML no envio** — só texto simples.
- **Mais de um compromisso por resposta enviada** — a IA identifica no máximo um.
- **Geração proativa de rascunhos durante a sincronização em background.** Geração é sempre sob
  demanda, disparada só quando o usuário abre a tela de detalhe de um e-mail específico — evita
  custo/latência de IA para e-mails que a pessoa nunca chega a abrir, e mantém o ciclo de sync tão
  rápido quanto hoje.

## Arquitetura

### Escopos OAuth e reconexão

`mobile/lib/features/email_triage/email_triage_providers.dart` passa a solicitar três escopos no
`GoogleSignIn`, em vez de só `gmail.readonly`:

```dart
const _gmailReadonlyScope = 'https://www.googleapis.com/auth/gmail.readonly';
const _gmailSendScope = 'https://www.googleapis.com/auth/gmail.send';
const _calendarEventsScope = 'https://www.googleapis.com/auth/calendar.events';
```

`gmail.send` (não `gmail.modify` nem `mail.google.com`) e `calendar.events` (não `calendar`
completo, que daria acesso de leitura/escrita a todas as agendas da pessoa) — os escopos mais
restritos que cobrem exatamente as duas ações desta fase, mesmo princípio de least privilege já
aplicado ao `gmail.readonly` na Fase 1.

O backend, na troca do código de autorização (`backend/src/gmail/gmail-oauth.service.ts`), lê o
campo `scope` devolvido pelo Google junto do token e grava, na mesma linha de `GmailConnection`,
quais dos dois escopos novos foram de fato concedidos — o usuário pode aceitar `gmail.send` e
recusar `calendar.events` na tela de consentimento do Google, então os dois são checados e
persistidos de forma independente, nunca assumidos a partir de "o fluxo pediu, então foi
concedido".

Quem já tinha conectado o Gmail antes desta fase existir tem `temEscopoEnvio`/`temEscopoAgenda`
como `false` (default) e precisa reconectar — o mesmo botão "Desconectar Gmail" das Configurações
(Fase 1) continua existindo; um novo texto de aviso na tela de detalhe do e-mail ("Reconecte o
Gmail para responder por aqui") aparece quando `temEscopoEnvio` é `false`, com um atalho direto
para o fluxo de reconexão. Reconectar refaz o mesmo fluxo OAuth já existente com a lista de escopos
ampliada; o backend sobrescreve `refreshTokenCriptografado` e os dois booleanos na mesma linha
(não cria uma segunda `GmailConnection`).

### Geração de rascunho (sob demanda)

Novo endpoint `POST /resumos-email/:id/rascunhos`, autenticado. `:id` é o `id` interno (UUID) do
`EmailSummary`, não o `gmailMessageId` bruto — o backend busca a linha via
`prisma.emailSummary.findFirst({ where: { id, userId } })` (mesmo padrão de tenant isolation já
usado em toda a Fase 1: o filtro por `userId` vem do token verificado, nunca de um parâmetro do
cliente), e só então usa o `gmailMessageId` daquela linha para chamar a API do Gmail — um id de
outro usuário simplesmente não é encontrado (404), nunca vaza qual `gmailMessageId` pertence a quem.
Fluxo:

1. Busca o corpo completo da mensagem via `gmail.users.messages.get` com `format: 'full'` — a
   Fase 1 só lê `format: 'metadata'` (nunca o corpo); esta fase precisa do texto real para gerar
   uma resposta coerente, mas continua sem persistir esse corpo em lugar nenhum.
2. Chama a Anthropic (mesmo cliente/modelo já usado pelo `LlmEmailClassifier` da Fase 1 —
   `claude-haiku-4-5-20251001`, via `backend/src/email-classification/`), pedindo 3 variações de
   resposta num único prompt estruturado, retornando JSON: `{ direto: string, formal: string,
   padrao: string }`.
3. Devolve os 3 textos à resposta HTTP. Nada — nem o corpo buscado no passo 1, nem os rascunhos
   gerados no passo 2 — é gravado no banco. Mesma garantia de "dados efêmeros" da Fase 1.

Se `temEscopoEnvio` for `false` para a conexão do usuário, o endpoint responde `403` antes de
gastar qualquer chamada à Anthropic — a tela mobile já sabe disso de antemão (lê o status da
conexão) e nem oferece o botão que dispara esta chamada, mas o backend também não confia só na UI.

### Envio + extração de compromisso (uma chamada só)

Novo endpoint `POST /resumos-email/:id/enviar` (mesma semântica de `:id` do endpoint de rascunhos
acima — `EmailSummary.id`, tenant-escopado), corpo `{ texto: string }` — o texto final escolhido
e/ou editado pelo usuário, exatamente como será enviado (sem nenhum pós-processamento silencioso
da IA entre a tela e o envio real). Fluxo:

1. Envia via `gmail.users.messages.send`: MIME simples, texto puro, `In-Reply-To`/`References`
   preenchidos com o `gmailMessageId` original para manter a thread.
2. Na mesma requisição, chama a Anthropic uma segunda vez sobre o `texto` recém-enviado, pedindo
   para identificar uma promessa de prazo/reunião, retornando JSON estruturado:
   `{ tituloCompromisso: string, dataHoraLimite: string (ISO), antecedenciaMinutos: number } |
   null`. `antecedenciaMinutos` é um número de minutos antes do prazo — não texto livre —, e o
   prompt restringe a IA a escolher entre um conjunto fixo de valores razoáveis (`60` para tarefas
   simples, `1440` para tarefas complexas), mesmo espírito de "opções pré-definidas em vez de campo
   livre" já usado noutros pontos do app (ex.: frequência do Biofeedback); esse número vai direto
   para o `reminders.overrides` do Calendar sem nenhuma etapa de conversão de texto. `null` é o
   resultado esperado e comum (a maioria das respostas não contém um compromisso — "ok, obrigado"
   não gera nada).
3. Responde `{ enviado: true, compromissoSugerido: {...} | null }`.

Falha no envio (passo 1) é reportada como erro ao mobile, que mantém o texto editado no campo —
nunca perde o que a pessoa escreveu. Falha na extração (passo 2, depois que o envio no passo 1 já
teve sucesso) não desfaz o envio: o endpoint responde `{ enviado: true, compromissoSugerido: null
}` mesmo assim — a extração é um bônus sobre um envio que já aconteceu, uma falha nela não pode
fingir que o e-mail não foi enviado.

### Confirmação do compromisso no Calendar

Novo endpoint `POST /resumos-email/compromissos/confirmar`, corpo com os mesmos campos que
`compromissoSugerido` devolveu (o cliente reenvia o que recebeu — como nada foi persistido, não há
o que "buscar de volta" no backend). Chama `calendar.events.insert` na agenda primária do usuário
(`calendarId: 'primary'`), com:

- `summary`: `tituloCompromisso`.
- `start`: `dataHoraLimite`; `end`: `dataHoraLimite` + 30 minutos — duração curta fixa só para
  garantir um evento válido e visível na agenda (a API do Google Calendar não aceita `start`
  igual a `end`); não representa um bloco de trabalho, só marca o prazo.
- `reminders.overrides`: dois lembretes — um em `antecedenciaMinutos` (o valor de 60 ou 1440
  decidido no passo de extração) e um fixo 30 minutos antes do prazo final.

O próprio Google Calendar entrega essas notificações — o Sincro não precisa de nenhum mecanismo de
agendamento próprio para isso (nenhuma tabela nova, nenhum cron novo).

Se `temEscopoAgenda` for `false`, este endpoint nunca é chamado — a tela mobile não mostra o card
de compromisso quando a conexão não tem esse escopo, mesmo que a IA tenha identificado um no passo
anterior (a sugestão é descartada silenciosamente nesse caso, não é possível confirmá-la sem o
escopo).

## Modelo de dados

```sql
ALTER TABLE conexoes_gmail ADD COLUMN tem_escopo_envio BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE conexoes_gmail ADD COLUMN tem_escopo_agenda BOOLEAN NOT NULL DEFAULT false;
```

Nenhuma tabela nova. Rascunhos e compromissos sugeridos nunca são persistidos — vivem só na
resposta HTTP e no estado da tela mobile entre uma chamada e a próxima.

## Mobile: UI

- **Inbox** (`inbox_screen.dart`, Fase 1): cada `_EmailTile` ganha `onTap`, navegando para a nova
  tela de detalhe — hoje a lista é 100% somente-leitura, sem nenhuma navegação.
- **Tela de Detalhe do E-mail** (`/inbox/:id`, nova): mostra assunto/remetente, e:
  - Se `temEscopoEnvio` for `false`: mensagem "Reconecte o Gmail para responder por aqui" +
    atalho para reconexão. Sem geração de rascunho.
  - Se `true`: ao abrir, dispara `POST /resumos-email/:id/rascunhos` (loading calmo enquanto
    espera); mostra os 3 rascunhos como opções de clique único, cada um editável antes de
    confirmar; falha na geração mostra aviso curto + um campo de texto livre como alternativa,
    nunca bloqueia a pessoa de responder.
  - Botão "Enviar" dispara `POST /resumos-email/:id/enviar` com o texto final.
- **Tela de Confirmação de Envio** (nova, substitui a tela de detalhe após o envio): "Enviado!" +,
  se `compromissoSugerido` não for nulo e `temEscopoAgenda` for `true`, um card com o compromisso
  e dois botões — "Confirmar no Calendário" (chama o endpoint de confirmação, depois mostra
  "Agendado ✓") e "Não agendar" (descarta, sem chamada nenhuma).
- **Configurações:** o aviso de reconexão já mencionado acima; nenhuma tela nova além dessa e das
  duas listadas.

Fluxo ponta a ponta:

```
Inbox → toca num e-mail "precisa de atenção"
  → Tela de Detalhe → gera 3 rascunhos → escolhe/edita → "Enviar"
  → Tela de Confirmação → "Enviado!" [+ card de compromisso, se houver] → "Confirmar no Calendário"
```

## Segurança e LGPD

- Escopos mínimos necessários para cada ação (`gmail.send`, não `gmail.modify`/`mail.google.com`;
  `calendar.events`, não `calendar` completo) — mesmo princípio de least privilege da Fase 1.
- `refreshTokenCriptografado` continua um único campo criptografado via `pgcrypto`, sobrescrito na
  reconexão — cobre a união dos escopos concedidos depois do re-consentimento.
- Corpo completo do e-mail (buscado só ao gerar rascunho) e os rascunhos/compromissos gerados nunca
  tocam o banco nem aparecem em log — mesma garantia de dados efêmeros da Fase 1, estendida às duas
  novas chamadas de IA.
- O texto exatamente como a pessoa viu/editou é o que é enviado — sem pós-processamento silencioso
  entre a tela e o envio real.
- Tenant isolation: os três endpoints novos resolvem `user_id` só do token Firebase verificado,
  nunca de parâmetro vindo do cliente — mesmo padrão de toda a Fase 1 e do resto do backend.
- Escopo revogado externamente (a pessoa remove a permissão direto na conta Google, fora do
  Sincro): as chamadas ao Gmail/Calendar falham com erro de permissão insuficiente; o backend
  responde 403 e a tela mobile mostra o mesmo aviso de reconexão da tela de detalhe.

## Testes

- **Backend:**
  - Unitário: geração de rascunho (cliente Anthropic mockado, formato do prompt e parsing das 3
    variações, incluindo resposta malformada da IA); extração de compromisso (Anthropic mockada,
    parsing do JSON estruturado e o caso `null` quando não há compromisso identificado); gravação
    dos dois booleanos de escopo a partir da string `scope` devolvida pelo Google (casos: nenhum
    escopo novo concedido, só `gmail.send`, só `calendar.events`, os dois).
  - Tenant isolation: os três endpoints novos escopados ao usuário autenticado, 403 para tentativa
    de acessar e-mail/conexão de outro usuário.
  - Guard de escopo: `POST .../rascunhos` retorna 403 sem chamar a Anthropic quando
    `temEscopoEnvio` é `false`; confirmação de compromisso nunca é exposta como possível quando
    `temEscopoAgenda` é `false` (mobile nem oferece; backend também valida).
  - E2E cobrindo: conectar Gmail com escopos completos (mockado) → gerar rascunhos (mockado) →
    enviar (Gmail send mockado) → compromisso sugerido → confirmar (Calendar insert mockado) →
    verificar que nenhuma linha do banco em nenhum momento contém corpo de e-mail, rascunho ou
    dado do compromisso — seguindo o padrão de `backend/test/onboarding-flow.e2e-spec.ts`.
- **Mobile:** repositórios dos três endpoints novos testados via interceptor do Dio (mesmo padrão
  já usado em `email_summary_repository.dart` e no resto do app). As telas novas seguem a mesma
  convenção já estabelecida no restante do projeto (Conexão Profissional, Alívio Sensorial) — sem
  teste de `pumpWidget`, cobertas por verificação manual.
- **Verificação manual** (não automatizável em `flutter test`): fluxo OAuth de reconexão em
  dispositivo real concedendo/negando escopos individualmente; envio real de um e-mail de teste;
  criação real de um evento no Google Calendar e confirmação visual dos dois lembretes
  configurados.
