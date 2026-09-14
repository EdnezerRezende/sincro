# Sincro — Agenda: Integração com Finanças e Categorização de Compromissos

## Contexto

O pilar de Agenda (`mobile/lib/features/calendar/`) hoje é um espelho puro do Google Calendar do
usuário: `CalendarEvent`/`EventoCalendario` tem só título, descrição, datas e flag de dia inteiro.
A modal que abre ao tocar num dia (`_abrirEventosDoDia` em `calendar_screen.dart`) já lista os
eventos do dia e já permite criar, editar e excluir compromissos via `_EventFormDialog` — CRUD
completo já existe nesse ponto.

O pilar de Finanças (`mobile/lib/features/financas/`) tem `LancamentoFinanceiro` com `tipo`
(despesa/receita/faturaCartao), `status` (pendenteRevisao/confirmado/ignorado) e um campo
independente `isPago`. O backend já tem um mecanismo parcial de sincronização com a Agenda:
`LancamentosService.confirmar()`/`update()` chamam `FinanceCalendarSyncService.syncOnConfirm()`
sempre que um lançamento fica `CONFIRMADO`, que cria ou atualiza um evento real no Google Calendar
do usuário e grava o id retornado em `LancamentoFinanceiro.googleEventId`. Hoje esse mecanismo:

- roda para **qualquer** tipo confirmado, inclusive receita;
- **nunca remove** o evento quando `isPago` passa a `true` — só remove em `ignorar()`/`remove()`
  (lançamento ignorado ou apagado), nunca no fluxo normal de "paguei essa conta".

Os dois módulos hoje não se conhecem: nenhum import cruzado, nenhum campo de categoria em nenhum
dos dois, nenhum ícone diferenciando o tipo de compromisso na Agenda.

Este documento especifica fechar essa integração: despesas e faturas de cartão confirmadas
aparecem como eventos reais na Agenda, somem de lá quando marcadas como pagas, e todo evento
(financeiro ou manual) ganha uma categoria visual (financeiro/social/trabalho/geral) exibida como
ícone na lista do dia.

## Objetivo desta fase

Ao final desta fase, o usuário deve poder:

1. Ver, na Agenda, um evento real (sincronizado com o Google Calendar) para cada lançamento do
   tipo despesa ou fatura de cartão que ele confirmou em Finanças — na data de vencimento.
2. Marcar esse lançamento como pago (switch já existente em `novo_lancamento_screen.dart`) e ver o
   evento correspondente desaparecer da Agenda, automaticamente, sem ação manual na Agenda.
3. Abrir a modal do dia, ver todos os compromissos daquele dia (financeiros e manuais juntos),
   criar um novo compromisso manual, editar ou excluir um compromisso manual existente — tudo já
   suportado hoje, mantido sem regressão.
4. Ao criar ou editar um compromisso manual, escolher uma categoria: Financeiro, Social, Trabalho
   ou Geral (padrão).
5. Ver, em cada card de evento na lista do dia, um ícone de categoria (financeiro/social/
   trabalho/geral), no mesmo padrão visual do badge de tipo já usado em Finanças
   (`_TipoIconBadge`: círculo com alpha 15%, ícone colorido, tooltip + semantics).
6. Ao tocar num evento gerado a partir de uma despesa/fatura (categoria financeiro com
   `lancamentoId`), ver uma visualização somente leitura explicando que ele vem de Finanças, sem
   poder editá-lo ou excluí-lo diretamente pela Agenda.

## Fora de escopo

- **Receitas na Agenda.** Só despesa e fatura de cartão geram evento — receber dinheiro não é um
  "compromisso a cumprir" no mesmo sentido, e o pedido original falou explicitamente em
  "pagamentos de despesas".
- **Botão de "marcar como pago" na lista de Finanças.** Continua existindo só como switch na tela
  de edição do lançamento (`novo_lancamento_screen.dart`) — não é o pedido desta fase.
- **Categorização automática por inferência de texto** (ex.: adivinhar "reunião" → trabalho). A
  categoria de evento manual é sempre escolhida explicitamente pelo usuário, padrão Geral.
- **Editar/reclassificar um evento financeiro pela Agenda** (mudar categoria, data, título). O
  lançamento em Finanças é a fonte da verdade; a Agenda só reflete.
- **Trocar o tipo de um lançamento já sincronizado** (ex. despesa → receita) depois de já ter
  evento criado. Não tratado especialmente nesta fase — caso raro, fica como comportamento não
  garantido (o evento pode ficar órfão até a próxima atualização do lançamento).
- **Categoria em eventos pré-existentes** criados antes desta fase (sem `extendedProperties`).
  Aparecem com ícone Geral (fallback), sem migração retroativa.
- **Notificação/push quando o evento é removido por pagamento.** A remoção é silenciosa; o usuário
  só percebe ao abrir a Agenda.

## Arquitetura

### 1. Categoria como `extendedProperties` do Google Calendar (backend)

O Google Calendar não tem campo nativo de categoria de negócio, mas a API suporta
`extendedProperties.private`, um mapa `string→string` opaco para o usuário (não aparece no app do
Google, só é lido/escrito via API) — mecanismo certo para guardar metadado nosso sem depender de
parsing de texto do título.

`backend/src/calendar/calendar-api-client.service.ts`:

- `EventoCalendario` (DTO exposto ao mobile) ganha `categoria: 'FINANCEIRO' | 'SOCIAL' | 'TRABALHO' | 'GERAL'`
  (default `'GERAL'` quando o evento não tem a propriedade, incluindo todo evento pré-existente).
- `EventoCompletoParams` ganha `categoria?: string` e `lancamentoId?: string` (opcional).
- `criarEventoCompleto()`/`atualizarEvento()` passam
  `extendedProperties: { private: { categoria, ...(lancamentoId ? { lancamentoId } : {}) } }` para
  `calendar.events.insert`/`.patch` quando `categoria` for informado.
- `paraEventoCalendario()` (mapeamento de resposta do Google → `EventoCalendario`) lê
  `item.extendedProperties?.private?.categoria`, com fallback `'GERAL'` se ausente ou valor
  desconhecido.

### 2. Regra de sincronização financeiro → Agenda (backend)

`backend/src/financas/calendar-sync.service.ts`, `FinanceCalendarSyncService.syncOnConfirm()`:
passa `categoria: 'FINANCEIRO'` e `lancamentoId: lancamento.id` nos `params` ao chamar
`criarEventoCompleto`/`atualizarEvento`. Sem outra mudança de comportamento aqui — a decisão de
*quando* chamar `syncOnConfirm` versus `removeEvent` migra para o chamador (item abaixo), porque é
ali que `tipo` e `isPago` do lançamento já resultante estão disponíveis.

`backend/src/financas/lancamentos.service.ts`, em `update()` e `confirmar()`: após o
`prisma.lancamentoFinanceiro.update`, a lógica de calendário passa a ser, para o lançamento
resultante (`atualizado`):

```
tipoElegivel = atualizado.tipo === 'DESPESA' || atualizado.tipo === 'FATURA_CARTAO'

se atualizado.status !== 'CONFIRMADO':
    nada (comportamento atual — só lançamento confirmado tem evento)
senão se atualizado.isPago === true:
    removeEvent(userId, atualizado.googleEventId)
    se atualizado.googleEventId não era nulo: persistir googleEventId = null
senão se tipoElegivel:
    googleEventId = syncOnConfirm(userId, atualizado)
    se googleEventId: persistir
// tipo não elegível (receita) e não pago: nenhuma ação — nunca teve evento
```

`ignorar()`/`remove()` continuam chamando `removeEvent()` sem mudança — já cobrem o caso de
lançamento cancelado/apagado.

### 3. API de eventos manuais aceita categoria (backend)

O controller de calendário (`/calendario/eventos`, criar e atualizar) já delega para
`criarEventoCompleto`/`atualizarEvento`. O DTO de criação/atualização de evento ganha um campo
opcional `categoria` (`'SOCIAL' | 'TRABALHO' | 'GERAL'` — `'FINANCEIRO'` não é aceito vindo do
cliente nesse endpoint, é reservado ao fluxo de sincronização financeira; um valor `FINANCEIRO`
enviado manualmente é rejeitado com 400), repassado como está para `EventoCompletoParams`. Sem
`categoria` no corpo, default `'GERAL'` (mesmo default de leitura).

### 4. Mobile: modelo e providers de Agenda

`mobile/lib/features/calendar/calendar_event.dart`: `CalendarEvent` ganha
`categoria` (enum `CategoriaEvento { financeiro, social, trabalho, geral }`, parse/serialize
como o resto do model) e `lancamentoId` (`String?`, só presente quando `categoria == financeiro`).
Enum e (de)serialização seguem o padrão já usado em `lancamento_financeiro.dart`
(`categoriaEventoFromJson`/`ToJson`, valores em maiúsculo no wire).

`calendar_repository.dart`: `createEvent()`/`updateEvent()` passam a aceitar `categoria` opcional
no payload (default omitido = backend usa `GERAL`); a listagem já desserializa o campo novo vindo
do backend sem mudança de assinatura.

### 5. Mobile: modal do dia — categoria e bloqueio de edição financeira

`calendar_screen.dart`:

- `_EventCard` (linha ~787): recebe um badge de categoria à esquerda do título, componente novo
  `_CategoriaIconBadge` no mesmo arquivo — mesmo padrão visual do `_TipoIconBadge` de Finanças
  (círculo 32×32, `color: cor.withValues(alpha: 0.15)`, ícone central, `Tooltip` +
  `Semantics(label:, excludeSemantics: true)`). Mapeamento ícone/cor:
  - `financeiro` → `Icons.payments_rounded`, cor de despesa já usada em Finanças (mesma função
    `_corTipo` ou equivalente portado).
  - `social` → `Icons.celebration_rounded`, cor terciária do tema.
  - `trabalho` → `Icons.work_rounded`, cor primária do tema.
  - `geral` → `Icons.event_note_rounded`, cor neutra (`onSurfaceVariant`), tooltip "Compromisso".
- Toque num `_EventCard` com `categoria == financeiro`: abre um diálogo somente leitura (não o
  `_EventFormDialog` de edição) mostrando título, descrição, data e um aviso fixo — "Gerado a
  partir de uma despesa em Finanças. Marque como paga em Finanças para remover da agenda." — com
  um único botão "Fechar". Nenhuma ação de editar/excluir disponível nesse caminho.
- Toque num evento com qualquer outra categoria: abre `_EventFormDialog` como hoje, com um seletor
  de categoria novo (chips ou dropdown — Financeiro **não** aparece como opção selecionável aqui,
  só Social/Trabalho/Geral, reforçando a regra do item 3), default Geral para evento novo, valor
  atual pré-selecionado para edição.
- Botão "novo compromisso" na modal do dia: mesmo `_EventFormDialog`, sem mudança de entrada além
  do seletor de categoria acima.

### 6. Mobile: refresh cruzado ao marcar como pago

`novo_lancamento_screen.dart`, no fluxo de salvar (`_salvar` ou equivalente) quando o PATCH de
`update()` é bem-sucedido e o lançamento tinha `isPago` alterado para `true`: além do
`ref.invalidate` já existente sobre os providers de Finanças, invalidar também
`monthEventsProvider`/`upcomingEventsProvider` (import de `calendar_providers.dart`). Efeito: se a
aba de Agenda já estiver montada, o evento some da lista assim que o usuário voltar para ela, sem
precisar trocar de mês/forçar refresh manual.

## Testes

- **Backend (unit, Jest):** `lancamentos.service.spec.ts` — casos: despesa confirmada não paga
  sincroniza; despesa confirmada paga remove evento e limpa `googleEventId`; receita confirmada
  nunca chama `syncOnConfirm`; fatura de cartão segue mesma regra de despesa; lançamento não
  confirmado não mexe em calendário. `calendar-api-client.service.spec.ts` — `extendedProperties`
  é passado corretamente para `events.insert`/`.patch`; `paraEventoCalendario` lê `categoria` com
  fallback `GERAL` quando ausente.
- **Mobile (widget/unit):** parse de `CalendarEvent` com e sem `categoria`/`lancamentoId` no JSON;
  `_CategoriaIconBadge` renderiza ícone/cor/tooltip/semantics corretos para as 4 categorias;
  toque em evento financeiro abre diálogo somente leitura (sem botões editar/excluir); toque em
  evento manual abre `_EventFormDialog` com seletor de categoria e sem opção Financeiro
  disponível; salvar lançamento com `isPago: true` invalida os providers de Agenda.
- **Manual (dispositivo real ou emulador com conta Google de teste):** confirmar uma despesa em
  Finanças → evento aparece na Agenda com ícone financeiro na data de vencimento; marcar como paga
  → evento some da Agenda; criar compromisso manual com categoria Social/Trabalho → ícone correto
  aparece; tentar editar evento financeiro pela Agenda → vê só a visualização somente leitura.
