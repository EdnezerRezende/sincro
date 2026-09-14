# Agenda x Finanças + Categorias de Evento Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Despesas e faturas de cartão confirmadas em Finanças aparecem como eventos reais na Agenda, somem automaticamente quando marcadas como pagas, e todo evento (financeiro ou manual) exibe um ícone de categoria (financeiro/social/trabalho/geral) na lista do dia.

**Architecture:** Backend (NestJS + Prisma + Google Calendar API via `googleapis`) grava a categoria e o id do lançamento vinculado em `extendedProperties.private` do evento do Google Calendar (não há tabela própria de evento). `LancamentosService` centraliza, num único método privado, a decisão de criar/atualizar/remover o evento a partir do estado resultante do lançamento (tipo, status, isPago) — chamado de `createManual`, `update` e `confirmar`. Mobile (Flutter + Riverpod) desserializa a categoria, mostra um badge de ícone reutilizando o padrão visual já usado em Finanças, restringe a edição/exclusão de eventos financeiros pela Agenda, e invalida os providers de Agenda sempre que Finanças salva algo que pode ter mudado o calendário.

**Tech Stack:** Backend: NestJS, Prisma, Jest, `googleapis` (mockado em teste), `class-validator`. Mobile: Flutter, Riverpod (`flutter_riverpod`), `flutter_test`, Dio.

**Spec:** `docs/superpowers/specs/2026-09-14-agenda-financas-categorias-design.md`

## Global Constraints

- Só despesa (`DESPESA`) e fatura de cartão (`FATURA_CARTAO`) geram evento na Agenda — nunca receita.
- A categoria `FINANCEIRO` nunca pode ser escolhida pelo cliente mobile ao criar/editar um evento manual — é reservada ao fluxo de sincronização financeira; o backend rejeita com 400 se vier de fora.
- Evento com categoria `FINANCEIRO` é somente leitura na Agenda (sem editar/excluir por lá).
- Todo campo/valor novo no wire (JSON) usa maiúsculas para os enums (`FINANCEIRO`, `SOCIAL`, `TRABALHO`, `GERAL`, `DESPESA`, `FATURA_CARTAO`), igual ao padrão já usado em `tipo`/`status` de `LancamentoFinanceiro`.
- Nenhuma migração de banco é necessária — a categoria vive inteiramente em `extendedProperties` do Google Calendar, não em nenhuma tabela Prisma.

---

## Backend

### Task 1: `CalendarApiClient` grava e lê `categoria`/`lancamentoId` via `extendedProperties`

**Files:**
- Modify: `backend/src/calendar/calendar-api-client.service.ts`
- Test: `backend/src/calendar/calendar-api-client.service.spec.ts`

**Interfaces:**
- Produces: `export type CategoriaEvento = 'FINANCEIRO' | 'SOCIAL' | 'TRABALHO' | 'GERAL';` exportado de `calendar-api-client.service.ts`. `EventoCalendario.categoria: CategoriaEvento` (sempre presente, default `'GERAL'`). `EventoCalendario.lancamentoId?: string`. `EventoCompletoParams.categoria?: CategoriaEvento`. `EventoCompletoParams.lancamentoId?: string`.

- [ ] **Step 1: Escrever os testes que falham**

Adicionar ao final de `describe('CalendarApiClient.criarEventoCompleto', ...)` em `calendar-api-client.service.spec.ts`:

```ts
  it('inclui extendedProperties.private com a categoria quando informada', async () => {
    const { __insert } = mocksGoogleapis();
    __insert.mockResolvedValueOnce({ data: { id: 'ev1' } });

    await buildClient().criarEventoCompleto('rt-123', {
      titulo: 'Pagar: Nubank',
      descricao: '',
      dataHoraInicio: '2026-09-01',
      dataHoraFim: '2026-09-01',
      ehDiaInteiro: true,
      categoria: 'FINANCEIRO',
      lancamentoId: 'lanc-1',
    });

    const body = corpoEnviado();
    expect(body.extendedProperties).toEqual({
      private: { categoria: 'FINANCEIRO', lancamentoId: 'lanc-1' },
    });
  });

  it('inclui extendedProperties.private só com a categoria quando lancamentoId não é informado', async () => {
    const { __insert } = mocksGoogleapis();
    __insert.mockResolvedValueOnce({ data: { id: 'ev1' } });

    await buildClient().criarEventoCompleto('rt-123', {
      titulo: 'Aniversário',
      descricao: '',
      dataHoraInicio: '2026-09-01T15:00:00-03:00',
      dataHoraFim: '2026-09-01T16:00:00-03:00',
      categoria: 'SOCIAL',
    });

    const body = corpoEnviado();
    expect(body.extendedProperties).toEqual({ private: { categoria: 'SOCIAL' } });
  });

  it('não inclui extendedProperties quando categoria não é informada (preserva chamadas antigas)', async () => {
    const { __insert } = mocksGoogleapis();
    __insert.mockResolvedValueOnce({ data: { id: 'ev1' } });

    await buildClient().criarEventoCompleto('rt-123', {
      titulo: 'Consulta',
      descricao: 'Com o dentista',
      dataHoraInicio: '2026-09-01T15:00:00-03:00',
      dataHoraFim: '2026-09-01T16:00:00-03:00',
    });

    const body = corpoEnviado();
    expect(body.extendedProperties).toBeUndefined();
  });
```

Adicionar ao final de `describe('CalendarApiClient.atualizarEvento', ...)`:

```ts
  it('inclui extendedProperties.private no patch quando categoria é informada', async () => {
    const { __patch } = mocksGoogleapis();
    __patch.mockResolvedValueOnce({ data: { id: 'ev1' } });

    await buildClient().atualizarEvento('rt-123', 'ev1', {
      titulo: 'Pagar: Nubank',
      descricao: '',
      dataHoraInicio: '2026-09-01',
      dataHoraFim: '2026-09-01',
      ehDiaInteiro: true,
      categoria: 'FINANCEIRO',
      lancamentoId: 'lanc-1',
    });

    const body = __patch.mock.calls[0][0].requestBody;
    expect(body.extendedProperties).toEqual({
      private: { categoria: 'FINANCEIRO', lancamentoId: 'lanc-1' },
    });
  });
```

Substituir o teste `'mapeia os itens do Google para o shape EventoCalendario esperado pelo app'` em `describe('CalendarApiClient.listarEventos', ...)` (agora `categoria` é sempre presente no resultado):

```ts
  it('mapeia os itens do Google para o shape EventoCalendario esperado pelo app', async () => {
    const { __list } = mocksGoogleapis();
    __list.mockResolvedValueOnce({
      data: {
        items: [
          {
            id: 'ev1',
            summary: 'Reunião',
            description: 'Pauta',
            start: { dateTime: '2026-09-01T15:00:00-03:00' },
            end: { dateTime: '2026-09-01T16:00:00-03:00' },
          },
        ],
      },
    });

    const eventos = await buildClient().listarEventos(
      'rt-123',
      '2026-09-01T00:00:00.000Z',
      '2026-10-01T00:00:00.000Z',
    );

    expect(eventos).toEqual([
      {
        id: 'ev1',
        titulo: 'Reunião',
        descricao: 'Pauta',
        dataHoraInicio: '2026-09-01T15:00:00-03:00',
        dataHoraFim: '2026-09-01T16:00:00-03:00',
        ehDiaInteiro: false,
        categoria: 'GERAL',
      },
    ]);
  });

  it('lê a categoria e o lancamentoId de extendedProperties.private quando presentes', async () => {
    const { __list } = mocksGoogleapis();
    __list.mockResolvedValueOnce({
      data: {
        items: [
          {
            id: 'ev2',
            summary: 'Pagar: Nubank',
            description: 'Valor: R$ 500.00',
            start: { date: '2026-09-10' },
            end: { date: '2026-09-10' },
            extendedProperties: { private: { categoria: 'FINANCEIRO', lancamentoId: 'lanc-1' } },
          },
        ],
      },
    });

    const eventos = await buildClient().listarEventos(
      'rt-123',
      '2026-09-01T00:00:00.000Z',
      '2026-10-01T00:00:00.000Z',
    );

    expect(eventos[0].categoria).toBe('FINANCEIRO');
    expect(eventos[0].lancamentoId).toBe('lanc-1');
  });

  it('cai em GERAL quando extendedProperties.private.categoria é um valor desconhecido', async () => {
    const { __list } = mocksGoogleapis();
    __list.mockResolvedValueOnce({
      data: {
        items: [
          {
            id: 'ev3',
            summary: 'Evento antigo',
            start: { dateTime: '2026-09-01T15:00:00-03:00' },
            end: { dateTime: '2026-09-01T16:00:00-03:00' },
            extendedProperties: { private: { categoria: 'ALGO_INVALIDO' } },
          },
        ],
      },
    });

    const eventos = await buildClient().listarEventos(
      'rt-123',
      '2026-09-01T00:00:00.000Z',
      '2026-10-01T00:00:00.000Z',
    );

    expect(eventos[0].categoria).toBe('GERAL');
    expect(eventos[0].lancamentoId).toBeUndefined();
  });
```

- [ ] **Step 2: Rodar os testes e verificar que falham**

Run: `cd backend && npx jest calendar-api-client.service.spec.ts`
Expected: FAIL — `categoria`/`extendedProperties`/`lancamentoId` não existem ainda em `EventoCompletoParams`/`EventoCalendario`, e `body.extendedProperties` é sempre `undefined`.

- [ ] **Step 3: Implementar**

Em `backend/src/calendar/calendar-api-client.service.ts`, substituir o topo do arquivo (interfaces) por:

```ts
import { Injectable } from '@nestjs/common';
import { google, calendar_v3 } from 'googleapis';
import { GmailOAuthService } from '../gmail/gmail-oauth.service';

export interface CriarEventoParams {
  tituloCompromisso: string;
  dataHoraLimite: string; // ISO 8601, idealmente com offset explícito (ex.: 2026-09-01T15:00:00-03:00)
  antecedenciaMinutos: number;
}

/** Categoria visual do evento, exibida como ícone na Agenda do app mobile. `FINANCEIRO` é
 *  reservado ao fluxo de sincronização de Finanças — nunca aceito vindo do cliente no endpoint
 *  de evento manual (ver `CriarEventoDto`). */
export type CategoriaEvento = 'FINANCEIRO' | 'SOCIAL' | 'TRABALHO' | 'GERAL';

/** Shape geral de um evento de agenda exposto ao app mobile — distinto de `CriarEventoParams`,
 *  que é específico do fluxo de compromisso sugerido por e-mail. `categoria` e `lancamentoId`
 *  vêm de `extendedProperties.private` do evento real no Google Calendar (metadado invisível ao
 *  usuário no app do Google, só lido/escrito via API) — não existe tabela própria de evento. */
export interface EventoCalendario {
  id: string;
  titulo: string;
  descricao: string;
  dataHoraInicio: string;
  dataHoraFim: string;
  ehDiaInteiro: boolean; // true se o evento é um evento de dia inteiro (all-day)
  categoria: CategoriaEvento; // 'GERAL' quando o evento não tem a extended property (inclusive todo evento pré-existente)
  lancamentoId?: string; // presente só quando categoria === 'FINANCEIRO', liga o evento ao LancamentoFinanceiro de origem
}

/** Parâmetros para criar/atualizar um evento completo (agenda sempre-editável do usuário),
 *  diferente de `CriarEventoParams` (duração fixa de 30min, lembretes fixos, usado só pelo fluxo
 *  de confirmação de compromisso sugerido). */
export interface EventoCompletoParams {
  titulo: string;
  descricao: string;
  dataHoraInicio: string;
  dataHoraFim: string;
  ehDiaInteiro?: boolean; // true se o evento é um evento de dia inteiro (all-day)
  lembretesMinutosAntes?: number[];
  categoria?: CategoriaEvento; // omitido: nenhum extendedProperties é enviado (preserva chamadas antigas)
  lancamentoId?: string; // só tem efeito quando categoria também é informada
}
```

Adicionar o método privado `extendedPropertiesOverride` (junto aos outros helpers privados, perto de `remindersOverride`):

```ts
  /** Monta `extendedProperties.private` quando `categoria` é informada — omitido inteiramente
   *  quando não é, para não alterar o payload de chamadas que ainda não passam esse parâmetro
   *  (ex.: fluxo de compromisso sugerido por e-mail, que usa `criarEvento`, não este método). */
  private extendedPropertiesOverride(
    categoria?: CategoriaEvento,
    lancamentoId?: string,
  ): { extendedProperties: calendar_v3.Schema$Event['extendedProperties'] } | Record<string, never> {
    if (!categoria) return {};
    return {
      extendedProperties: {
        private: {
          categoria,
          ...(lancamentoId ? { lancamentoId } : {}),
        },
      },
    };
  }
```

Em `criarEventoCompleto`, adicionar `...this.extendedPropertiesOverride(params.categoria, params.lancamentoId),` no `requestBody` dos dois branches (all-day e com hora) — logo após `...this.remindersOverride(params.lembretesMinutosAntes),`. Fazer o mesmo nos dois branches de `atualizarEvento`.

Substituir `paraEventoCalendario`:

```ts
  private paraEventoCalendario(
    item: calendar_v3.Schema$Event,
  ): EventoCalendario {
    // Determina se é um evento de dia inteiro (all-day): Google Calendar usa `date` em vez de
    // `dateTime` para esses eventos. A presença de `start.date` (sem `start.dateTime`) indica
    // um evento all-day. Essencial para a mobile app não corromper all-day events ao editá-los.
    const ehDiaInteiro = !item.start?.dateTime && !!item.start?.date;
    const categoriaBruta = item.extendedProperties?.private?.categoria;
    const categoria: CategoriaEvento =
      categoriaBruta === 'FINANCEIRO' ||
      categoriaBruta === 'SOCIAL' ||
      categoriaBruta === 'TRABALHO'
        ? categoriaBruta
        : 'GERAL';
    const lancamentoId = item.extendedProperties?.private?.lancamentoId;
    return {
      id: item.id ?? '',
      titulo: item.summary ?? '',
      descricao: item.description ?? '',
      dataHoraInicio: item.start?.dateTime ?? item.start?.date ?? '',
      dataHoraFim: item.end?.dateTime ?? item.end?.date ?? '',
      ehDiaInteiro,
      categoria,
      ...(lancamentoId ? { lancamentoId } : {}),
    };
  }
```

- [ ] **Step 4: Rodar os testes e verificar que passam**

Run: `cd backend && npx jest calendar-api-client.service.spec.ts`
Expected: PASS (todos os testes do arquivo, incluindo os pré-existentes).

- [ ] **Step 5: Commit**

```bash
git add backend/src/calendar/calendar-api-client.service.ts backend/src/calendar/calendar-api-client.service.spec.ts
git commit -m "feat(calendar): categoria e lancamentoId via extendedProperties do evento"
```

---

### Task 2: `/calendario` aceita `categoria` em criar/atualizar evento manual, rejeitando `FINANCEIRO`

**Files:**
- Modify: `backend/src/calendar/dto/criar-evento.dto.ts`
- Modify: `backend/src/calendar/calendar.controller.ts`
- Modify: `backend/src/calendar/calendar.controller.spec.ts`
- Create: `backend/src/calendar/dto/criar-evento.dto.spec.ts`

**Interfaces:**
- Consumes: `CategoriaEvento` de `calendar-api-client.service.ts` (Task 1).
- Produces: `CriarEventoDto.categoria?: 'SOCIAL' | 'TRABALHO' | 'GERAL'`.

- [ ] **Step 1: Escrever o teste de validação do DTO que falha**

Criar `backend/src/calendar/dto/criar-evento.dto.spec.ts`:

```ts
import { validate } from 'class-validator';
import { plainToInstance } from 'class-transformer';
import { CriarEventoDto } from './criar-evento.dto';

const base = {
  titulo: 'Reunião',
  dataHoraInicio: '2026-09-01T15:00:00-03:00',
  dataHoraFim: '2026-09-01T16:00:00-03:00',
};

describe('CriarEventoDto — categoria', () => {
  it('aceita SOCIAL, TRABALHO e GERAL', async () => {
    for (const categoria of ['SOCIAL', 'TRABALHO', 'GERAL']) {
      const dto = plainToInstance(CriarEventoDto, { ...base, categoria });
      const erros = await validate(dto);
      expect(erros).toHaveLength(0);
    }
  });

  it('aceita ausência de categoria', async () => {
    const dto = plainToInstance(CriarEventoDto, base);
    const erros = await validate(dto);
    expect(erros).toHaveLength(0);
  });

  it('rejeita FINANCEIRO — reservado ao fluxo de sincronização de Finanças', async () => {
    const dto = plainToInstance(CriarEventoDto, { ...base, categoria: 'FINANCEIRO' });
    const erros = await validate(dto);
    expect(erros).not.toHaveLength(0);
    expect(erros[0].property).toBe('categoria');
  });

  it('rejeita um valor arbitrário', async () => {
    const dto = plainToInstance(CriarEventoDto, { ...base, categoria: 'QUALQUER_COISA' });
    const erros = await validate(dto);
    expect(erros).not.toHaveLength(0);
  });
});
```

- [ ] **Step 2: Rodar e verificar que falha**

Run: `cd backend && npx jest criar-evento.dto.spec.ts`
Expected: FAIL — `categoria` ainda não existe no DTO, `plainToInstance` simplesmente ignora o campo e todos os testes de validação de fato passam vazios, mas o teste de rejeição (`'rejeita FINANCEIRO'`) falha porque `erros` fica vazio (nada valida um campo que não existe no DTO).

- [ ] **Step 3: Implementar**

`backend/src/calendar/dto/criar-evento.dto.ts`:

```ts
import { IsIn, IsISO8601, IsOptional, IsString, IsBoolean, MinLength } from 'class-validator';

export class CriarEventoDto {
  @IsString()
  @MinLength(1)
  titulo: string;

  @IsOptional()
  @IsString()
  descricao?: string;

  @IsISO8601()
  dataHoraInicio: string;

  @IsISO8601()
  dataHoraFim: string;

  @IsOptional()
  @IsBoolean()
  ehDiaInteiro?: boolean; // true se o evento é um evento de dia inteiro (all-day)

  /** 'FINANCEIRO' é reservado ao fluxo de sincronização de Finanças (`FinanceCalendarSyncService`)
   *  e nunca é aceito vindo do cliente — só as três categorias abaixo, escolhidas manualmente
   *  pelo usuário ao criar/editar um compromisso na Agenda. */
  @IsOptional()
  @IsIn(['SOCIAL', 'TRABALHO', 'GERAL'])
  categoria?: 'SOCIAL' | 'TRABALHO' | 'GERAL';
}
```

- [ ] **Step 4: Rodar e verificar que passa**

Run: `cd backend && npx jest criar-evento.dto.spec.ts`
Expected: PASS

- [ ] **Step 5: Atualizar os testes de roteamento do controller (falham antes da implementação)**

Em `backend/src/calendar/calendar.controller.spec.ts`, substituir os dois testes existentes em `describe('CalendarController — roteamento para o client', ...)`:

```ts
  it('criarEvento repassa os campos do dto para criarEventoCompleto, default GERAL sem categoria', async () => {
    const { controller, calendarApiClient } = buildController();

    await controller.criarEvento('fb1', dtoValido);

    expect(calendarApiClient.criarEventoCompleto).toHaveBeenCalledWith(
      'rt-123',
      {
        titulo: 'Reunião',
        descricao: 'Pauta',
        dataHoraInicio: '2026-09-01T15:00:00-03:00',
        dataHoraFim: '2026-09-01T16:00:00-03:00',
        ehDiaInteiro: false,
        categoria: 'GERAL',
      },
    );
  });

  it('criarEvento repassa a categoria informada no dto', async () => {
    const { controller, calendarApiClient } = buildController();

    await controller.criarEvento('fb1', { ...dtoValido, categoria: 'TRABALHO' });

    expect(calendarApiClient.criarEventoCompleto).toHaveBeenCalledWith(
      'rt-123',
      expect.objectContaining({ categoria: 'TRABALHO' }),
    );
  });

  it('atualizarEvento repassa o id e os campos do dto para atualizarEvento do client, default GERAL sem categoria', async () => {
    const { controller, calendarApiClient } = buildController();

    await controller.atualizarEvento('fb1', 'ev1', dtoValido);

    expect(calendarApiClient.atualizarEvento).toHaveBeenCalledWith(
      'rt-123',
      'ev1',
      {
        titulo: 'Reunião',
        descricao: 'Pauta',
        dataHoraInicio: '2026-09-01T15:00:00-03:00',
        dataHoraFim: '2026-09-01T16:00:00-03:00',
        ehDiaInteiro: false,
        categoria: 'GERAL',
      },
    );
  });
```

Run: `cd backend && npx jest calendar.controller.spec.ts`
Expected: FAIL (controller ainda não passa `categoria`).

- [ ] **Step 6: Implementar no controller**

Em `backend/src/calendar/calendar.controller.ts`, em `criarEvento` e `atualizarEvento`, adicionar `categoria: dto.categoria ?? 'GERAL',` ao objeto passado para `criarEventoCompleto`/`atualizarEvento`:

```ts
  @Post('criar-evento')
  async criarEvento(
    @CurrentFirebaseUid() firebaseUid: string,
    @Body() dto: CriarEventoDto,
  ) {
    this.validarIntervalo(dto);
    const refreshToken = await this.refreshTokenComEscopoAgenda(firebaseUid);
    return this.calendarApiClient.criarEventoCompleto(refreshToken, {
      titulo: dto.titulo,
      descricao: dto.descricao ?? '',
      dataHoraInicio: dto.dataHoraInicio,
      dataHoraFim: dto.dataHoraFim,
      ehDiaInteiro: dto.ehDiaInteiro ?? false,
      categoria: dto.categoria ?? 'GERAL',
    });
  }

  @Put('evento/:id')
  async atualizarEvento(
    @CurrentFirebaseUid() firebaseUid: string,
    @Param('id') id: string,
    @Body() dto: CriarEventoDto,
  ) {
    this.validarIntervalo(dto);
    const refreshToken = await this.refreshTokenComEscopoAgenda(firebaseUid);
    return this.calendarApiClient.atualizarEvento(refreshToken, id, {
      titulo: dto.titulo,
      descricao: dto.descricao ?? '',
      dataHoraInicio: dto.dataHoraInicio,
      dataHoraFim: dto.dataHoraFim,
      ehDiaInteiro: dto.ehDiaInteiro ?? false,
      categoria: dto.categoria ?? 'GERAL',
    });
  }
```

- [ ] **Step 7: Rodar todos os testes do módulo e verificar que passam**

Run: `cd backend && npx jest src/calendar`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add backend/src/calendar
git commit -m "feat(calendar): endpoint de evento manual aceita categoria (SOCIAL/TRABALHO/GERAL)"
```

---

### Task 3: `FinanceCalendarSyncService` marca o evento sincronizado como `FINANCEIRO`

**Files:**
- Modify: `backend/src/financas/calendar-sync.service.ts`
- Modify: `backend/src/financas/calendar-sync.service.spec.ts`

**Interfaces:**
- Consumes: `CategoriaEvento` (Task 1), `EventoCompletoParams.categoria`/`.lancamentoId`.
- Produces: nenhuma mudança de assinatura pública — `syncOnConfirm(userId, lancamento)` continua igual, só o payload interno muda.

- [ ] **Step 1: Atualizar o teste que falha**

Em `backend/src/financas/calendar-sync.service.spec.ts`, o primeiro teste (`'creates a new event when the lançamento has no googleEventId yet'`) espera o `params` exato passado a `criarEventoCompleto`. Substituí-lo:

```ts
  it('creates a new event when the lançamento has no googleEventId yet, tagged as FINANCEIRO', async () => {
    const deps = buildDeps();
    const service = new FinanceCalendarSyncService(deps.calendarApiClient as any, deps.gmailConnectionsService as any);

    const eventId = await service.syncOnConfirm('user-1', lancamentoBase as any);

    expect(deps.calendarApiClient.criarEventoCompleto).toHaveBeenCalledWith('refresh-token', {
      titulo: 'Pagar: Nubank · Fatura Nubank',
      descricao: 'Valor: R$ 512.40',
      dataHoraInicio: '2026-10-10',
      dataHoraFim: '2026-10-10',
      ehDiaInteiro: true,
      lembretesMinutosAntes: [1440],
      categoria: 'FINANCEIRO',
      lancamentoId: 'lanc-1',
    });
    expect(eventId).toBe('evt-1');
  });
```

Manter os demais testes do arquivo como estão (não dependem do payload exato).

- [ ] **Step 2: Rodar e verificar que falha**

Run: `cd backend && npx jest calendar-sync.service.spec.ts`
Expected: FAIL — `categoria`/`lancamentoId` ausentes no `params` recebido por `criarEventoCompleto`.

- [ ] **Step 3: Implementar**

Em `backend/src/financas/calendar-sync.service.ts`, dentro de `syncOnConfirm`, adicionar `categoria: 'FINANCEIRO'` e `lancamentoId: lancamento.id` ao objeto `params`:

```ts
      const params = {
        titulo,
        descricao: valorNumero !== null ? `Valor: R$ ${valorNumero.toFixed(2)}` : '',
        dataHoraInicio: dataIso,
        dataHoraFim: dataIso,
        ehDiaInteiro: true,
        lembretesMinutosAntes: [24 * 60],
        categoria: 'FINANCEIRO' as const,
        lancamentoId: lancamento.id,
      };
```

- [ ] **Step 4: Rodar e verificar que passa**

Run: `cd backend && npx jest calendar-sync.service.spec.ts`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add backend/src/financas/calendar-sync.service.ts backend/src/financas/calendar-sync.service.spec.ts
git commit -m "feat(financas): evento sincronizado é marcado como categoria FINANCEIRO"
```

---

### Task 4: `LancamentosService` decide criar/remover o evento a partir de tipo + status + isPago

Esta é a tarefa central: hoje `syncOnConfirm` roda para qualquer tipo confirmado (inclusive receita) e nunca é removido quando `isPago` vira `true`; `createManual` nunca sincroniza. Substitui os três pontos de chamada por um único método privado.

**Files:**
- Modify: `backend/src/financas/lancamentos.service.ts`
- Modify: `backend/src/financas/lancamentos.service.spec.ts`

**Interfaces:**
- Consumes: `FinanceCalendarSyncService.syncOnConfirm`/`.removeEvent` (já existentes, Task 3 só mudou o payload interno).
- Produces: nenhuma API pública nova — `createManual`, `update`, `confirmar`, `ignorar`, `remove` mantêm assinatura.

- [ ] **Step 1: Escrever os testes que falham**

Em `backend/src/financas/lancamentos.service.spec.ts`, atualizar `buildDeps()` para o mock de `prisma.lancamentoFinanceiro.update` devolver um objeto completo por padrão (os testes existentes sobrescrevem com `.mockResolvedValue` quando precisam de outra coisa, então isso não quebra nada):

```ts
function buildDeps() {
  const prisma = {
    lancamentoFinanceiro: {
      findMany: jest.fn().mockResolvedValue([]),
      create: jest.fn().mockResolvedValue({ id: 'lanc-1' }),
      update: jest.fn().mockResolvedValue({ id: 'lanc-1' }),
      findFirst: jest.fn(),
      delete: jest.fn(),
    },
    contaFinanceira: {
      findFirst: jest.fn().mockResolvedValue({ id: 'conta-1', userId: 'user-1' }),
    },
    cartaoCredito: {
      findFirst: jest.fn().mockResolvedValue({ id: 'cartao-1', userId: 'user-1' }),
    },
  };
  const calendarSync = {
    syncOnConfirm: jest.fn().mockResolvedValue(null),
    removeEvent: jest.fn().mockResolvedValue(undefined),
  };
  return { prisma, calendarSync, service: new LancamentosService(prisma as any, calendarSync as any) };
}
```

Substituir o teste `'creates a lançamento already CONFIRMADO with origem MANUAL'` em `describe('LancamentosService — createManual', ...)` por três testes:

```ts
  it('creates a lançamento already CONFIRMADO with origem MANUAL', async () => {
    const { prisma, service } = buildDeps();
    prisma.lancamentoFinanceiro.create.mockResolvedValue({
      id: 'lanc-1', tipo: 'DESPESA', status: 'CONFIRMADO', isPago: false, googleEventId: null,
    });

    await service.createManual('user-1', {
      tipo: 'DESPESA',
      descricao: 'Mercado',
      dataVencimento: '2026-09-20',
    });

    expect(prisma.lancamentoFinanceiro.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        userId: 'user-1',
        tipo: 'DESPESA',
        descricao: 'Mercado',
        status: 'CONFIRMADO',
        origem: 'MANUAL',
        dataVencimento: new Date('2026-09-20'),
        dataCompetencia: new Date('2026-09-20'),
      }),
    });
  });

  it('syncs a calendar event for a manually created DESPESA not yet paid', async () => {
    const { prisma, calendarSync, service } = buildDeps();
    const criado = { id: 'lanc-1', tipo: 'DESPESA', status: 'CONFIRMADO', isPago: false, googleEventId: null };
    prisma.lancamentoFinanceiro.create.mockResolvedValue(criado);
    calendarSync.syncOnConfirm.mockResolvedValue('evt-novo');

    await service.createManual('user-1', { tipo: 'DESPESA', descricao: 'Mercado', dataVencimento: '2026-09-20' });

    expect(calendarSync.syncOnConfirm).toHaveBeenCalledWith('user-1', criado);
    expect(prisma.lancamentoFinanceiro.update).toHaveBeenCalledWith({
      where: { id: 'lanc-1' },
      data: { googleEventId: 'evt-novo' },
    });
  });

  it('never syncs a calendar event for a manually created RECEITA', async () => {
    const { prisma, calendarSync, service } = buildDeps();
    prisma.lancamentoFinanceiro.create.mockResolvedValue({
      id: 'lanc-1', tipo: 'RECEITA', status: 'CONFIRMADO', isPago: false, googleEventId: null,
    });

    await service.createManual('user-1', { tipo: 'RECEITA', descricao: 'Salário', dataVencimento: '2026-09-20' });

    expect(calendarSync.syncOnConfirm).not.toHaveBeenCalled();
    expect(prisma.lancamentoFinanceiro.update).not.toHaveBeenCalled();
  });

  it('throws when contaId belongs to a different user', async () => {
    const { prisma, service } = buildDeps();
    prisma.contaFinanceira.findFirst.mockResolvedValue(null);

    await expect(
      service.createManual('user-1', {
        tipo: 'DESPESA',
        descricao: 'Mercado',
        dataVencimento: '2026-09-20',
        contaId: 'conta-de-outro-usuario',
      }),
    ).rejects.toThrow();
    expect(prisma.lancamentoFinanceiro.create).not.toHaveBeenCalled();
  });

  it('throws when cartaoId belongs to a different user', async () => {
    const { prisma, service } = buildDeps();
    prisma.cartaoCredito.findFirst.mockResolvedValue(null);

    await expect(
      service.createManual('user-1', {
        tipo: 'FATURA_CARTAO',
        descricao: 'Fatura',
        dataVencimento: '2026-09-20',
        cartaoId: 'cartao-de-outro-usuario',
      }),
    ).rejects.toThrow();
    expect(prisma.lancamentoFinanceiro.create).not.toHaveBeenCalled();
  });
```

Substituir o primeiro teste de `describe('LancamentosService — confirmar', ...)`:

```ts
  it('applies the adjustment, sets status CONFIRMADO, and syncs the calendar event for an unpaid DESPESA', async () => {
    const { prisma, calendarSync, service } = buildDeps();
    prisma.lancamentoFinanceiro.findFirst.mockResolvedValue({
      id: 'lanc-1', userId: 'user-1', status: 'PENDENTE_REVISAO', googleEventId: null,
    });
    prisma.lancamentoFinanceiro.update.mockResolvedValue({
      id: 'lanc-1', tipo: 'DESPESA', status: 'CONFIRMADO', isPago: false, descricao: 'Fatura Nubank',
      instituicao: 'Nubank', valor: 500, dataVencimento: new Date(Date.UTC(2026, 9, 10)), googleEventId: null,
    });
    calendarSync.syncOnConfirm.mockResolvedValue('evt-novo');

    await service.confirmar('user-1', 'lanc-1', { valor: 500 });

    expect(prisma.lancamentoFinanceiro.update).toHaveBeenNthCalledWith(1, {
      where: { id: 'lanc-1' },
      data: { valor: 500, status: 'CONFIRMADO' },
    });
    expect(calendarSync.syncOnConfirm).toHaveBeenCalled();
    expect(prisma.lancamentoFinanceiro.update).toHaveBeenNthCalledWith(2, {
      where: { id: 'lanc-1' },
      data: { googleEventId: 'evt-novo' },
    });
  });

  it('confirming a RECEITA never syncs a calendar event', async () => {
    const { prisma, calendarSync, service } = buildDeps();
    prisma.lancamentoFinanceiro.findFirst.mockResolvedValue({
      id: 'lanc-1', userId: 'user-1', status: 'PENDENTE_REVISAO', googleEventId: null,
    });
    prisma.lancamentoFinanceiro.update.mockResolvedValue({
      id: 'lanc-1', tipo: 'RECEITA', status: 'CONFIRMADO', isPago: false, googleEventId: null,
    });

    await service.confirmar('user-1', 'lanc-1', {});

    expect(calendarSync.syncOnConfirm).not.toHaveBeenCalled();
  });
```

Adicionar um novo `describe` para `update()` (não existia antes):

```ts
describe('LancamentosService — update', () => {
  it('syncs the calendar event when the DESPESA stays CONFIRMADO and unpaid', async () => {
    const { prisma, calendarSync, service } = buildDeps();
    prisma.lancamentoFinanceiro.findFirst.mockResolvedValue({
      id: 'lanc-1', userId: 'user-1', status: 'CONFIRMADO', googleEventId: null,
    });
    prisma.lancamentoFinanceiro.update.mockResolvedValue({
      id: 'lanc-1', tipo: 'DESPESA', status: 'CONFIRMADO', isPago: false, googleEventId: null,
    });
    calendarSync.syncOnConfirm.mockResolvedValue('evt-1');

    await service.update('user-1', 'lanc-1', { descricao: 'Mercado (editado)' });

    expect(calendarSync.syncOnConfirm).toHaveBeenCalled();
    expect(prisma.lancamentoFinanceiro.update).toHaveBeenLastCalledWith({
      where: { id: 'lanc-1' },
      data: { googleEventId: 'evt-1' },
    });
  });

  it('removes the calendar event and clears googleEventId when isPago becomes true', async () => {
    const { prisma, calendarSync, service } = buildDeps();
    prisma.lancamentoFinanceiro.findFirst.mockResolvedValue({
      id: 'lanc-1', userId: 'user-1', status: 'CONFIRMADO', googleEventId: 'evt-existente',
    });
    prisma.lancamentoFinanceiro.update.mockResolvedValue({
      id: 'lanc-1', tipo: 'DESPESA', status: 'CONFIRMADO', isPago: true, googleEventId: 'evt-existente',
    });

    await service.update('user-1', 'lanc-1', { isPago: true });

    expect(calendarSync.removeEvent).toHaveBeenCalledWith('user-1', 'evt-existente');
    expect(calendarSync.syncOnConfirm).not.toHaveBeenCalled();
    expect(prisma.lancamentoFinanceiro.update).toHaveBeenLastCalledWith({
      where: { id: 'lanc-1' },
      data: { googleEventId: null },
    });
  });

  it('does nothing to the calendar when isPago becomes true but there was no event yet', async () => {
    const { prisma, calendarSync, service } = buildDeps();
    prisma.lancamentoFinanceiro.findFirst.mockResolvedValue({
      id: 'lanc-1', userId: 'user-1', status: 'CONFIRMADO', googleEventId: null,
    });
    prisma.lancamentoFinanceiro.update.mockResolvedValue({
      id: 'lanc-1', tipo: 'DESPESA', status: 'CONFIRMADO', isPago: true, googleEventId: null,
    });

    await service.update('user-1', 'lanc-1', { isPago: true });

    expect(calendarSync.removeEvent).not.toHaveBeenCalled();
    expect(prisma.lancamentoFinanceiro.update).toHaveBeenCalledTimes(1); // só a atualização principal
  });

  it('never syncs a RECEITA even when CONFIRMADO and unpaid', async () => {
    const { prisma, calendarSync, service } = buildDeps();
    prisma.lancamentoFinanceiro.findFirst.mockResolvedValue({
      id: 'lanc-1', userId: 'user-1', status: 'CONFIRMADO', googleEventId: null,
    });
    prisma.lancamentoFinanceiro.update.mockResolvedValue({
      id: 'lanc-1', tipo: 'RECEITA', status: 'CONFIRMADO', isPago: false, googleEventId: null,
    });

    await service.update('user-1', 'lanc-1', { valor: 999 });

    expect(calendarSync.syncOnConfirm).not.toHaveBeenCalled();
    expect(calendarSync.removeEvent).not.toHaveBeenCalled();
  });

  it('does nothing to the calendar when the lançamento is still PENDENTE_REVISAO', async () => {
    const { prisma, calendarSync, service } = buildDeps();
    prisma.lancamentoFinanceiro.findFirst.mockResolvedValue({
      id: 'lanc-1', userId: 'user-1', status: 'PENDENTE_REVISAO', googleEventId: null,
    });
    prisma.lancamentoFinanceiro.update.mockResolvedValue({
      id: 'lanc-1', tipo: 'DESPESA', status: 'PENDENTE_REVISAO', isPago: false, googleEventId: null,
    });

    await service.update('user-1', 'lanc-1', { descricao: 'ajuste' });

    expect(calendarSync.syncOnConfirm).not.toHaveBeenCalled();
    expect(calendarSync.removeEvent).not.toHaveBeenCalled();
  });

  it('throws when updating with a cartaoId that belongs to a different user', async () => {
    const { prisma, service } = buildDeps();
    prisma.lancamentoFinanceiro.findFirst.mockResolvedValue({
      id: 'lanc-1', userId: 'user-1', status: 'CONFIRMADO', googleEventId: null,
    });
    prisma.cartaoCredito.findFirst.mockResolvedValue(null);

    await expect(
      service.update('user-1', 'lanc-1', { cartaoId: 'cartao-de-outro-usuario' }),
    ).rejects.toThrow();
    expect(prisma.lancamentoFinanceiro.update).not.toHaveBeenCalled();
  });
});
```

- [ ] **Step 2: Rodar e verificar que falham**

Run: `cd backend && npx jest lancamentos.service.spec.ts`
Expected: FAIL — `createManual` não sincroniza nada ainda; `confirmar`/`update` ainda sincronizam receita e não removem evento ao pagar.

- [ ] **Step 3: Implementar**

Substituir `backend/src/financas/lancamentos.service.ts` inteiro por:

```ts
import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { FinanceCalendarSyncService } from './calendar-sync.service';
import { ConfirmarLancamentoDto } from './dto/confirmar-lancamento.dto';
import { CreateLancamentoDto } from './dto/create-lancamento.dto';
import { UpdateLancamentoDto } from './dto/update-lancamento.dto';

const TIPOS_ELEGIVEIS_PARA_AGENDA = ['DESPESA', 'FATURA_CARTAO'];

/** Superset dos campos que `sincronizarCalendarioParaResultado` precisa: `tipo`/`status`/`isPago`
 *  para a decisão de criar/remover, e o restante (`descricao`, `instituicao`, `valor`,
 *  `dataVencimento`) porque é exatamente o que `FinanceCalendarSyncService.syncOnConfirm` espera
 *  (`LancamentoParaCalendar` em `calendar-sync.service.ts`) — mantendo os dois em sincronia evita
 *  um cast manual ao repassar `resultado` para `syncOnConfirm`. */
interface LancamentoParaSincCalendario {
  id: string;
  tipo: string;
  status: string;
  isPago: boolean;
  googleEventId: string | null;
  descricao: string;
  instituicao: string | null;
  valor: unknown;
  dataVencimento: Date;
}

@Injectable()
export class LancamentosService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly calendarSync: FinanceCalendarSyncService,
  ) {}

  list(userId: string, filtros: { status?: string; mes?: string }) {
    const where: Record<string, unknown> = { userId };
    if (filtros.status) where.status = filtros.status;
    if (filtros.mes) {
      const [ano, mes] = filtros.mes.split('-').map(Number);
      where.dataVencimento = {
        gte: new Date(Date.UTC(ano, mes - 1, 1)),
        lt: new Date(Date.UTC(ano, mes, 1)),
      };
    }
    return this.prisma.lancamentoFinanceiro.findMany({ where, orderBy: { dataVencimento: 'asc' } });
  }

  async createManual(userId: string, dto: CreateLancamentoDto) {
    await this.assertContaECartaoPertencemAoUsuario(userId, dto.contaId, dto.cartaoId);
    const dataVencimento = new Date(dto.dataVencimento);
    const dataCompetencia = dto.dataCompetencia ? new Date(dto.dataCompetencia) : dataVencimento;
    const criado = await this.prisma.lancamentoFinanceiro.create({
      data: {
        userId,
        tipo: dto.tipo,
        descricao: dto.descricao,
        instituicao: dto.instituicao,
        valor: dto.valor,
        dataVencimento,
        dataCompetencia,
        status: 'CONFIRMADO',
        origem: 'MANUAL',
        contaId: dto.contaId,
        cartaoId: dto.cartaoId,
        isPago: dto.isPago ?? false,
      },
    });
    await this.sincronizarCalendarioParaResultado(userId, criado);
    return criado;
  }

  async update(userId: string, id: string, dto: UpdateLancamentoDto) {
    await this.getOwnedOrThrow(userId, id); // garante posse; o resultado não é mais lido — a decisão de calendário usa `atualizado`, não o estado anterior
    await this.assertContaECartaoPertencemAoUsuario(userId, dto.contaId, dto.cartaoId);
    const data: Record<string, unknown> = { ...dto };
    if (dto.dataVencimento) data.dataVencimento = new Date(dto.dataVencimento);
    if (dto.dataCompetencia) data.dataCompetencia = new Date(dto.dataCompetencia);

    const atualizado = await this.prisma.lancamentoFinanceiro.update({ where: { id }, data });
    await this.sincronizarCalendarioParaResultado(userId, atualizado);
    return atualizado;
  }

  async confirmar(userId: string, id: string, dto: ConfirmarLancamentoDto) {
    await this.getOwnedOrThrow(userId, id);
    await this.assertContaECartaoPertencemAoUsuario(userId, dto.contaId, dto.cartaoId);
    const data: Record<string, unknown> = { status: 'CONFIRMADO' };
    if (dto.valor !== undefined) data.valor = dto.valor;
    if (dto.dataVencimento) data.dataVencimento = new Date(dto.dataVencimento);
    if (dto.contaId !== undefined) data.contaId = dto.contaId;
    if (dto.cartaoId !== undefined) data.cartaoId = dto.cartaoId;

    const atualizado = await this.prisma.lancamentoFinanceiro.update({ where: { id }, data });
    await this.sincronizarCalendarioParaResultado(userId, atualizado);
    return atualizado;
  }

  async ignorar(userId: string, id: string) {
    const lancamento = await this.getOwnedOrThrow(userId, id);
    const atualizado = await this.prisma.lancamentoFinanceiro.update({
      where: { id },
      data: { status: 'IGNORADO' },
    });
    await this.calendarSync.removeEvent(userId, lancamento.googleEventId);
    return atualizado;
  }

  async remove(userId: string, id: string): Promise<void> {
    const lancamento = await this.getOwnedOrThrow(userId, id);
    await this.prisma.lancamentoFinanceiro.delete({ where: { id } });
    await this.calendarSync.removeEvent(userId, lancamento.googleEventId);
  }

  /** Único ponto de decisão de calendário para o resultado de uma escrita em
   *  `LancamentoFinanceiro` (`createManual`, `update`, `confirmar`) — evita que as três
   *  chamadas divirjam sobre quando um evento deve existir. Regra: só lançamento CONFIRMADO
   *  de tipo DESPESA/FATURA_CARTAO tem evento; se `isPago` for true, o evento (se houver) é
   *  removido em vez de sincronizado. `ignorar`/`remove` continuam removendo incondicionalmente
   *  fora deste método, pois ali o lançamento deixa de existir/valer independente de tipo. */
  private async sincronizarCalendarioParaResultado(
    userId: string,
    resultado: LancamentoParaSincCalendario,
  ): Promise<void> {
    if (resultado.status !== 'CONFIRMADO') return;

    if (resultado.isPago) {
      if (!resultado.googleEventId) return;
      await this.calendarSync.removeEvent(userId, resultado.googleEventId);
      await this.prisma.lancamentoFinanceiro.update({
        where: { id: resultado.id },
        data: { googleEventId: null },
      });
      return;
    }

    if (!TIPOS_ELEGIVEIS_PARA_AGENDA.includes(resultado.tipo)) return;

    const googleEventId = await this.calendarSync.syncOnConfirm(userId, resultado);
    if (googleEventId) {
      await this.prisma.lancamentoFinanceiro.update({
        where: { id: resultado.id },
        data: { googleEventId },
      });
    }
  }

  protected async getOwnedOrThrow(userId: string, id: string) {
    const lancamento = await this.prisma.lancamentoFinanceiro.findFirst({ where: { id, userId } });
    if (!lancamento) throw new NotFoundException('Lançamento não encontrado');
    return lancamento;
  }

  private async assertContaECartaoPertencemAoUsuario(
    userId: string,
    contaId: string | undefined,
    cartaoId: string | undefined,
  ) {
    if (contaId) {
      const conta = await this.prisma.contaFinanceira.findFirst({ where: { id: contaId, userId } });
      if (!conta) throw new NotFoundException('Conta não encontrada');
    }
    if (cartaoId) {
      const cartao = await this.prisma.cartaoCredito.findFirst({ where: { id: cartaoId, userId } });
      if (!cartao) throw new NotFoundException('Cartão não encontrado');
    }
  }
}
```

- [ ] **Step 4: Rodar e verificar que passam**

Run: `cd backend && npx jest lancamentos.service.spec.ts`
Expected: PASS — todos os testes (novos e pré-existentes: `list`, `ignorar`, `remove` inalterados).

- [ ] **Step 5: Rodar a suíte inteira do backend**

Run: `cd backend && npx jest`
Expected: PASS (nenhuma regressão em outros módulos).

- [ ] **Step 6: Commit**

```bash
git add backend/src/financas/lancamentos.service.ts backend/src/financas/lancamentos.service.spec.ts
git commit -m "feat(financas): sincroniza agenda só para despesa/fatura, remove evento ao marcar como pago"
```

---

## Mobile

### Task 5: `CalendarEvent` ganha `categoria` e `lancamentoId`

**Files:**
- Modify: `mobile/lib/features/calendar/calendar_event.dart`
- Test: `mobile/test/features/calendar/categoria_evento_test.dart` (novo)

**Interfaces:**
- Produces: `enum CategoriaEvento { financeiro, social, trabalho, geral }`, `categoriaEventoFromJson(String?)`, `categoriaEventoToJson(CategoriaEvento)`, `CalendarEvent.categoria` (default `CategoriaEvento.geral`), `CalendarEvent.lancamentoId` (`String?`), `CalendarEvent.isGeradoPorFinancas` (getter bool).

- [ ] **Step 1: Escrever o teste que falha**

Criar `mobile/test/features/calendar/categoria_evento_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/calendar/calendar_event.dart';

void main() {
  group('CalendarEvent.categoria', () {
    test('parses FINANCEIRO com lancamentoId', () {
      final event = CalendarEvent.fromJson({
        'id': 'ev1',
        'titulo': 'Pagar: Nubank',
        'descricao': '',
        'dataHoraInicio': '2026-09-10',
        'dataHoraFim': '2026-09-10',
        'ehDiaInteiro': true,
        'categoria': 'FINANCEIRO',
        'lancamentoId': 'lanc-1',
      });

      expect(event.categoria, CategoriaEvento.financeiro);
      expect(event.lancamentoId, 'lanc-1');
      expect(event.isGeradoPorFinancas, isTrue);
    });

    test('parses SOCIAL, TRABALHO e GERAL', () {
      for (final par in {
        'SOCIAL': CategoriaEvento.social,
        'TRABALHO': CategoriaEvento.trabalho,
        'GERAL': CategoriaEvento.geral,
      }.entries) {
        final event = CalendarEvent.fromJson({
          'id': 'ev1',
          'titulo': 'Evento',
          'descricao': '',
          'dataHoraInicio': '2026-09-10T10:00:00-03:00',
          'dataHoraFim': '2026-09-10T11:00:00-03:00',
          'categoria': par.key,
        });
        expect(event.categoria, par.value);
      }
    });

    test('cai em GERAL quando categoria ausente ou desconhecida', () {
      final semCampo = CalendarEvent.fromJson({
        'id': 'ev1', 'titulo': 'Evento', 'descricao': '',
        'dataHoraInicio': '2026-09-10T10:00:00-03:00', 'dataHoraFim': '2026-09-10T11:00:00-03:00',
      });
      expect(semCampo.categoria, CategoriaEvento.geral);

      final desconhecida = CalendarEvent.fromJson({
        'id': 'ev1', 'titulo': 'Evento', 'descricao': '',
        'dataHoraInicio': '2026-09-10T10:00:00-03:00', 'dataHoraFim': '2026-09-10T11:00:00-03:00',
        'categoria': 'ALGO_INVALIDO',
      });
      expect(desconhecida.categoria, CategoriaEvento.geral);
    });

    test('isGeradoPorFinancas é false sem lancamentoId, mesmo com categoria FINANCEIRO', () {
      final event = CalendarEvent.fromJson({
        'id': 'ev1', 'titulo': 'Evento', 'descricao': '',
        'dataHoraInicio': '2026-09-10T10:00:00-03:00', 'dataHoraFim': '2026-09-10T11:00:00-03:00',
        'categoria': 'FINANCEIRO',
      });
      expect(event.isGeradoPorFinancas, isFalse);
    });

    test('toJson serializa a categoria em maiúsculas', () {
      const event = CalendarEvent(
        id: 'ev1', titulo: 'Evento', descricao: '',
        dataHoraInicio: null_safe, dataHoraFim: null_safe,
        categoria: CategoriaEvento.trabalho,
      );
      expect(event.toJson()['categoria'], 'TRABALHO');
    });
  });
}
```

Corrigir o último teste antes de rodar (o helper `null_safe` não existe — usar `DateTime` reais):

```dart
    test('toJson serializa a categoria em maiúsculas', () {
      final event = CalendarEvent(
        id: 'ev1',
        titulo: 'Evento',
        descricao: '',
        dataHoraInicio: DateTime(2026, 9, 10),
        dataHoraFim: DateTime(2026, 9, 10),
        categoria: CategoriaEvento.trabalho,
      );
      expect(event.toJson()['categoria'], 'TRABALHO');
    });
```

- [ ] **Step 2: Rodar e verificar que falha**

Run: `cd mobile && flutter test test/features/calendar/categoria_evento_test.dart`
Expected: FAIL — `CategoriaEvento` não existe.

- [ ] **Step 3: Implementar**

Substituir `mobile/lib/features/calendar/calendar_event.dart`:

```dart
/// Categoria visual do evento, exibida como ícone na lista do dia. Espelha
/// `CategoriaEvento` em `backend/src/calendar/calendar-api-client.service.ts`.
/// `financeiro` só é considerado "gerado por Finanças" (ver [CalendarEvent.isGeradoPorFinancas])
/// quando também vem acompanhado de [CalendarEvent.lancamentoId] — o backend nunca envia um
/// sem o outro, mas o parse trata os dois campos de forma independente por segurança.
enum CategoriaEvento { financeiro, social, trabalho, geral }

CategoriaEvento categoriaEventoFromJson(String? value) {
  switch (value) {
    case 'FINANCEIRO':
      return CategoriaEvento.financeiro;
    case 'SOCIAL':
      return CategoriaEvento.social;
    case 'TRABALHO':
      return CategoriaEvento.trabalho;
    default:
      return CategoriaEvento.geral;
  }
}

String categoriaEventoToJson(CategoriaEvento categoria) {
  switch (categoria) {
    case CategoriaEvento.financeiro:
      return 'FINANCEIRO';
    case CategoriaEvento.social:
      return 'SOCIAL';
    case CategoriaEvento.trabalho:
      return 'TRABALHO';
    case CategoriaEvento.geral:
      return 'GERAL';
  }
}

/// Model para um evento de calendário sincronizado do Google Calendar.
///
/// Os nomes dos campos espelham exatamente o JSON devolvido/aceito pelo backend
/// (`EventoCalendario` em `backend/src/calendar/calendar-api-client.service.ts` e o
/// `CriarEventoDto` em `backend/src/calendar/dto/criar-evento.dto.ts`) — em português, para não
/// precisar de nenhuma tradução de campo entre o app e a API.
class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.titulo,
    required this.descricao,
    required this.dataHoraInicio,
    required this.dataHoraFim,
    this.ehDiaInteiro = false,
    this.categoria = CategoriaEvento.geral,
    this.lancamentoId,
  });

  final String id;
  final String titulo;
  final String descricao;
  final DateTime dataHoraInicio;
  final DateTime dataHoraFim;
  final bool ehDiaInteiro; // true se o evento é um evento de dia inteiro (all-day)
  final CategoriaEvento categoria;
  final String? lancamentoId; // presente só quando categoria == financeiro

  /// True quando o evento foi criado pelo fluxo de sincronização de Finanças (categoria
  /// financeiro + link para o lançamento de origem) — nesse caso a Agenda mostra o evento
  /// como somente leitura, já que Finanças é a fonte da verdade.
  bool get isGeradoPorFinancas =>
      categoria == CategoriaEvento.financeiro && lancamentoId != null;

  factory CalendarEvent.fromJson(Map<String, dynamic> json) {
    return CalendarEvent(
      id: json['id'] as String? ?? '',
      titulo: json['titulo'] as String? ?? 'Evento sem título',
      descricao: json['descricao'] as String? ?? '',
      // `.toLocal()` é essencial aqui: quando a string ISO trazida pelo backend tem offset (ou
      // "Z"), `DateTime.parse` devolve um DateTime com `isUtc == true` — ler `.hour`/`.day` direto
      // dele exibe o horário em UTC, não no fuso do usuário. Um evento às 15h em São Paulo
      // (-03:00) viraria "18:00" na tela. Convertendo para local uma única vez aqui, todo o resto
      // do app (formatação de hora, agrupamento por dia no grid do mês) já recebe o instante certo.
      dataHoraInicio: DateTime.parse(json['dataHoraInicio'] as String? ?? '2000-01-01').toLocal(),
      dataHoraFim: DateTime.parse(json['dataHoraFim'] as String? ?? '2000-01-01').toLocal(),
      ehDiaInteiro: json['ehDiaInteiro'] as bool? ?? false,
      categoria: categoriaEventoFromJson(json['categoria'] as String?),
      lancamentoId: json['lancamentoId'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'titulo': titulo,
    'descricao': descricao,
    'dataHoraInicio': dataHoraInicio.toIso8601String(),
    'dataHoraFim': dataHoraFim.toIso8601String(),
    'ehDiaInteiro': ehDiaInteiro,
    'categoria': categoriaEventoToJson(categoria),
    if (lancamentoId != null) 'lancamentoId': lancamentoId,
  };
}
```

- [ ] **Step 4: Rodar e verificar que passa**

Run: `cd mobile && flutter test test/features/calendar/categoria_evento_test.dart test/features/calendar/all_day_event_test.dart`
Expected: PASS (os dois arquivos — o segundo garante que nada quebrou no model existente).

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/calendar/calendar_event.dart mobile/test/features/calendar/categoria_evento_test.dart
git commit -m "feat(calendar): CalendarEvent ganha categoria e lancamentoId"
```

---

### Task 6: `CalendarRepository` envia `categoria` ao criar/editar evento manual

**Files:**
- Modify: `mobile/lib/features/calendar/calendar_repository.dart`
- Test: `mobile/test/features/calendar/repository_categoria_test.dart` (novo)

**Interfaces:**
- Consumes: `CategoriaEvento`, `categoriaEventoToJson` (Task 5).
- Produces: `CalendarRepository.createEvent`/`.updateEvent` ganham parâmetro nomeado opcional `categoria` (default `CategoriaEvento.geral`).

- [ ] **Step 1: Escrever o teste que falha**

Criar `mobile/test/features/calendar/repository_categoria_test.dart`, seguindo o mesmo padrão de mock de `Dio` já usado em `mobile/test/features/financas/lancamentos_repository_test.dart` (um `Dio` real apontando para uma base fake, com um `InterceptorsWrapper` que intercepta `onRequest`, inspeciona `options` e resolve a resposta sinteticamente via `handler.resolve(...)` — sem nenhum pacote de mock extra):

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/calendar/calendar_event.dart';
import 'package:sincro_mobile/features/calendar/calendar_repository.dart';

void main() {
  group('CalendarRepository.createEvent — categoria', () {
    test('envia categoria GERAL por padrão quando não informada', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        expect(options.data['categoria'], 'GERAL');
        handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: {
            'id': 'ev1', 'titulo': 'Evento', 'descricao': '',
            'dataHoraInicio': '2026-09-10T10:00:00-03:00',
            'dataHoraFim': '2026-09-10T11:00:00-03:00', 'categoria': 'GERAL',
          },
        ));
      }));
      final repo = CalendarRepository(dio);

      await repo.createEvent(
        titulo: 'Evento',
        descricao: '',
        dataHoraInicio: DateTime(2026, 9, 10, 10),
        dataHoraFim: DateTime(2026, 9, 10, 11),
      );
    });

    test('envia a categoria informada', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        expect(options.data['categoria'], 'TRABALHO');
        handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: {
            'id': 'ev1', 'titulo': 'Reunião', 'descricao': '',
            'dataHoraInicio': '2026-09-10T10:00:00-03:00',
            'dataHoraFim': '2026-09-10T11:00:00-03:00', 'categoria': 'TRABALHO',
          },
        ));
      }));
      final repo = CalendarRepository(dio);

      await repo.createEvent(
        titulo: 'Reunião',
        descricao: '',
        dataHoraInicio: DateTime(2026, 9, 10, 10),
        dataHoraFim: DateTime(2026, 9, 10, 11),
        categoria: CategoriaEvento.trabalho,
      );
    });

    test('updateEvent também envia a categoria informada', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        expect(options.path, '/calendario/evento/ev1');
        expect(options.data['categoria'], 'SOCIAL');
        handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: {
            'id': 'ev1', 'titulo': 'Festa', 'descricao': '',
            'dataHoraInicio': '2026-09-10T10:00:00-03:00',
            'dataHoraFim': '2026-09-10T11:00:00-03:00', 'categoria': 'SOCIAL',
          },
        ));
      }));
      final repo = CalendarRepository(dio);

      await repo.updateEvent(
        eventId: 'ev1',
        titulo: 'Festa',
        descricao: '',
        dataHoraInicio: DateTime(2026, 9, 10, 10),
        dataHoraFim: DateTime(2026, 9, 10, 11),
        categoria: CategoriaEvento.social,
      );
    });
  });
}
```

- [ ] **Step 2: Rodar e verificar que falha**

Run: `cd mobile && flutter test test/features/calendar/repository_categoria_test.dart`
Expected: FAIL — `createEvent` não aceita `categoria` ainda, e o corpo nunca inclui o campo.

- [ ] **Step 3: Implementar**

Em `mobile/lib/features/calendar/calendar_repository.dart`, adicionar o import e o parâmetro em `createEvent`/`updateEvent`:

```dart
import 'calendar_event.dart';
```

(já existe — sem mudança no import).

```dart
  Future<CalendarEvent> createEvent({
    required String titulo,
    required String descricao,
    required DateTime dataHoraInicio,
    required DateTime dataHoraFim,
    bool ehDiaInteiro = false,
    CategoriaEvento categoria = CategoriaEvento.geral,
  }) async {
    final response = await _dio.post(
      '/calendario/criar-evento',
      data: {
        'titulo': titulo,
        'descricao': descricao,
        'dataHoraInicio': _isoComOffsetLocal(dataHoraInicio),
        'dataHoraFim': _isoComOffsetLocal(dataHoraFim),
        'ehDiaInteiro': ehDiaInteiro,
        'categoria': categoriaEventoToJson(categoria),
      },
    );
    return CalendarEvent.fromJson(response.data as Map<String, dynamic>);
  }
```

```dart
  Future<CalendarEvent> updateEvent({
    required String eventId,
    required String titulo,
    required String descricao,
    required DateTime dataHoraInicio,
    required DateTime dataHoraFim,
    bool ehDiaInteiro = false,
    CategoriaEvento categoria = CategoriaEvento.geral,
  }) async {
    final response = await _dio.put(
      '/calendario/evento/$eventId',
      data: {
        'titulo': titulo,
        'descricao': descricao,
        'dataHoraInicio': _isoComOffsetLocal(dataHoraInicio),
        'dataHoraFim': _isoComOffsetLocal(dataHoraFim),
        'ehDiaInteiro': ehDiaInteiro,
        'categoria': categoriaEventoToJson(categoria),
      },
    );
    return CalendarEvent.fromJson(response.data as Map<String, dynamic>);
  }
```

- [ ] **Step 4: Rodar e verificar que passa**

Run: `cd mobile && flutter test test/features/calendar/repository_categoria_test.dart`
Expected: PASS

Run também a suíte inteira de calendar para garantir zero regressão: `cd mobile && flutter test test/features/calendar/`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/calendar/calendar_repository.dart mobile/test/features/calendar/repository_categoria_test.dart
git commit -m "feat(calendar): repository envia categoria ao criar/editar evento"
```

---

### Task 7: Badge de ícone por categoria em `_EventCard`

**Files:**
- Modify: `mobile/lib/features/calendar/calendar_screen.dart`
- Test: `mobile/test/features/calendar/categoria_badge_test.dart` (novo)

**Interfaces:**
- Consumes: `CategoriaEvento` (Task 5).
- Produces: widget privado `_CategoriaIconBadge` (não exportado — testado indiretamente via `CalendarScreen`/`_EventCard`, igual ao padrão de `_TipoIconBadge` em Finanças, que também não é testado isoladamente por ser privado).

- [ ] **Step 1: Escrever o teste que falha**

Criar `mobile/test/features/calendar/categoria_badge_test.dart`. Este teste sobe a `CalendarScreen` inteira dentro de um `ProviderScope` com os providers de calendário sobrescritos — checar o padrão exato já usado em `mobile/test/features/calendar/touch_target_test.dart` ou `revalidation_test.dart` (como eles fazem override de `monthEventsProvider`/`calendarRepositoryProvider` num `ProviderScope` de teste) e replicar a mesma estrutura de setup. Usando esse padrão:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/calendar/calendar_event.dart';
import 'package:sincro_mobile/features/calendar/calendar_providers.dart';
import 'package:sincro_mobile/features/calendar/calendar_screen.dart';
import 'package:sincro_mobile/features/email_triage/email_triage_providers.dart';
import 'package:sincro_mobile/features/email_triage/gmail_connection_repository.dart';

void main() {
  testWidgets('mostra o ícone e o tooltip correspondentes à categoria do evento', (tester) async {
    final hoje = DateTime.now();
    final evento = CalendarEvent(
      id: 'ev1',
      titulo: 'Reunião de trabalho',
      descricao: '',
      dataHoraInicio: DateTime(hoje.year, hoje.month, hoje.day, 10),
      dataHoraFim: DateTime(hoje.year, hoje.month, hoje.day, 11),
      categoria: CategoriaEvento.trabalho,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // `CalendarScreen` também lê `gmailConnectionStatusProvider` (mostra painel de
          // reconexão quando não conectado) e `upcomingEventsProvider` (seção "Próximos
          // eventos") — sem sobrescrever os dois, a tela tentaria uma chamada de rede real
          // via `apiClientProvider`, tornando o teste não-determinístico. Mesmo padrão de
          // override usado em `revalidation_test.dart`/`touch_target_test.dart`.
          gmailConnectionStatusProvider.overrideWith(
            (ref) async => const GmailConnectionStatus(connected: true),
          ),
          upcomingEventsProvider.overrideWith((ref) async => <CalendarEvent>[]),
          monthEventsProvider.overrideWith((ref, params) async => [evento]),
        ],
        child: const MaterialApp(home: CalendarScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Abre a modal do dia de hoje tocando na célula correspondente (o número do dia
    // aparece só uma vez no grid de dias, já que `_DayCell` só renderiza dias do mês
    // atualmente exibido).
    await tester.tap(find.text('${hoje.day}').first);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Trabalho'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Rodar e verificar que falha**

Run: `cd mobile && flutter test test/features/calendar/categoria_badge_test.dart`
Expected: FAIL — nenhum `Tooltip` com texto "Trabalho" existe ainda no card.

- [ ] **Step 3: Implementar**

Em `mobile/lib/features/calendar/calendar_screen.dart`, adicionar a classe `_CategoriaIconBadge` (colar logo antes de `class _EventCard`):

```dart
/// Badge redondo com o ícone da categoria do evento — mesmo padrão visual do
/// `_TipoIconBadge` de Finanças (círculo com alpha 15%, ícone colorido, tooltip +
/// semantics), para que os dois módulos leiam visualmente como parte do mesmo sistema.
class _CategoriaIconBadge extends StatelessWidget {
  const _CategoriaIconBadge({required this.categoria});

  final CategoriaEvento categoria;

  (IconData, Color, String) _visual(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    switch (categoria) {
      case CategoriaEvento.financeiro:
        return (Icons.payments_rounded, colorScheme.error, 'Financeiro');
      case CategoriaEvento.social:
        return (Icons.celebration_rounded, colorScheme.tertiary, 'Social');
      case CategoriaEvento.trabalho:
        return (Icons.work_rounded, colorScheme.primary, 'Trabalho');
      case CategoriaEvento.geral:
        return (Icons.event_note_rounded, colorScheme.onSurfaceVariant, 'Compromisso');
    }
  }

  @override
  Widget build(BuildContext context) {
    final (icone, cor, label) = _visual(context);
    // Sem `container: true`: o badge se funde no nó de semântica do `_EventCard` ancestral,
    // mesmo raciocínio do `_TipoIconBadge` em Finanças.
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: cor.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icone, size: 18, color: cor),
        ),
      ),
    );
  }
}
```

Em `_EventCard.build`, substituir o bloco do horário (linhas do `Text('$horaInicio – $horaFim', ...)`) por uma `Row` com o badge:

```dart
            // Categoria (ícone) + horário
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _CategoriaIconBadge(categoria: event.categoria),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$horaInicio – $horaFim',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
```

- [ ] **Step 4: Rodar e verificar que passa**

Run: `cd mobile && flutter test test/features/calendar/categoria_badge_test.dart`
Expected: PASS

Run também: `cd mobile && flutter test test/features/calendar/`
Expected: PASS (garante zero regressão nos testes de touch target/all-day/revalidation, que também exercitam `_EventCard`).

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/calendar/calendar_screen.dart mobile/test/features/calendar/categoria_badge_test.dart
git commit -m "feat(calendar): badge de ícone por categoria no card de evento"
```

---

### Task 8: Evento financeiro é somente leitura; evento manual ganha seletor de categoria

**Files:**
- Modify: `mobile/lib/features/calendar/calendar_screen.dart`
- Test: `mobile/test/features/calendar/evento_financeiro_readonly_test.dart` (novo)
- Test: `mobile/test/features/calendar/categoria_selector_test.dart` (novo)

**Interfaces:**
- Consumes: `CalendarEvent.isGeradoPorFinancas`, `CategoriaEvento` (Task 5); `CalendarRepository.createEvent`/`.updateEvent` com `categoria` (Task 6).
- Produces: widget privado `_FinanceEventInfoDialog`.

- [ ] **Step 1: Escrever os testes que falham**

Criar `mobile/test/features/calendar/evento_financeiro_readonly_test.dart` (mesmo padrão de setup de `ProviderScope` da Task 7, incluindo os overrides de `gmailConnectionStatusProvider`/`upcomingEventsProvider`):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/calendar/calendar_event.dart';
import 'package:sincro_mobile/features/calendar/calendar_providers.dart';
import 'package:sincro_mobile/features/calendar/calendar_screen.dart';
import 'package:sincro_mobile/features/email_triage/email_triage_providers.dart';
import 'package:sincro_mobile/features/email_triage/gmail_connection_repository.dart';

void main() {
  testWidgets('evento gerado por Finanças abre em modo somente leitura, sem editar/excluir', (tester) async {
    final hoje = DateTime.now();
    final evento = CalendarEvent(
      id: 'ev1',
      titulo: 'Pagar: Nubank',
      descricao: 'Valor: R\$ 500.00',
      dataHoraInicio: DateTime(hoje.year, hoje.month, hoje.day),
      dataHoraFim: DateTime(hoje.year, hoje.month, hoje.day),
      ehDiaInteiro: true,
      categoria: CategoriaEvento.financeiro,
      lancamentoId: 'lanc-1',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gmailConnectionStatusProvider.overrideWith(
            (ref) async => const GmailConnectionStatus(connected: true),
          ),
          upcomingEventsProvider.overrideWith((ref) async => <CalendarEvent>[]),
          monthEventsProvider.overrideWith((ref, params) async => [evento]),
        ],
        child: const MaterialApp(home: CalendarScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('${hoje.day}').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ver detalhes'));
    await tester.pumpAndSettle();

    expect(find.text('Pagar: Nubank'), findsWidgets);
    expect(
      find.textContaining('Gerado a partir de uma despesa em Finanças'),
      findsOneWidget,
    );
    expect(find.text('Editar'), findsNothing);
    expect(find.text('Excluir'), findsNothing);
    expect(find.text('Salvar'), findsNothing);
  });
}
```

Criar `mobile/test/features/calendar/categoria_selector_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/calendar/calendar_event.dart';
import 'package:sincro_mobile/features/calendar/calendar_providers.dart';
import 'package:sincro_mobile/features/calendar/calendar_screen.dart';
import 'package:sincro_mobile/features/email_triage/email_triage_providers.dart';
import 'package:sincro_mobile/features/email_triage/gmail_connection_repository.dart';

void main() {
  testWidgets('evento manual abre no formulário de edição com seletor de categoria, sem opção Financeiro', (tester) async {
    final hoje = DateTime.now();
    final evento = CalendarEvent(
      id: 'ev2',
      titulo: 'Jantar com amigos',
      descricao: '',
      dataHoraInicio: DateTime(hoje.year, hoje.month, hoje.day, 20),
      dataHoraFim: DateTime(hoje.year, hoje.month, hoje.day, 22),
      categoria: CategoriaEvento.social,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gmailConnectionStatusProvider.overrideWith(
            (ref) async => const GmailConnectionStatus(connected: true),
          ),
          upcomingEventsProvider.overrideWith((ref) async => <CalendarEvent>[]),
          monthEventsProvider.overrideWith((ref, params) async => [evento]),
        ],
        child: const MaterialApp(home: CalendarScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('${hoje.day}').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();

    expect(find.text('Categoria'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Social'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Trabalho'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Geral'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Financeiro'), findsNothing);
  });
}
```

- [ ] **Step 2: Rodar e verificar que falham**

Run: `cd mobile && flutter test test/features/calendar/evento_financeiro_readonly_test.dart test/features/calendar/categoria_selector_test.dart`
Expected: FAIL — botão ainda é sempre "Editar"/abre sempre `_EventFormDialog`, e o formulário não tem seletor de categoria.

- [ ] **Step 3: Implementar**

Em `mobile/lib/features/calendar/calendar_screen.dart`, adicionar a classe `_FinanceEventInfoDialog` (colar logo antes de `class _EventFormDialog`):

```dart
/// Visualização somente leitura de um evento gerado a partir de uma despesa/fatura em
/// Finanças. Sem botões de editar/excluir de propósito: Finanças é a fonte da verdade para
/// esse evento (o backend recria/atualiza o evento a cada sincronização), então permitir
/// edição direta pela Agenda criaria um estado divergente que seria sobrescrito na próxima
/// confirmação de Finanças, confundindo o usuário sobre onde a mudança "pegou".
class _FinanceEventInfoDialog extends StatelessWidget {
  const _FinanceEventInfoDialog({required this.event});

  final CalendarEvent event;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(event.titulo),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (event.descricao.isNotEmpty) ...[
            Text(event.descricao),
            const SizedBox(height: 12),
          ],
          Text(
            'Gerado a partir de uma despesa em Finanças. Marque como paga em Finanças '
            'para remover da agenda.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}
```

Em `_EventCard.build`, trocar o botão único de "Editar" por um que varia conforme `event.isGeradoPorFinancas`:

```dart
            // Botão de edição/detalhes (altura explícita de 48dp — o mínimo recomendado de
            // alvo de toque). Evento gerado por Finanças abre em modo somente leitura — ver
            // `_FinanceEventInfoDialog`.
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                icon: Icon(
                  event.isGeradoPorFinancas ? Icons.info_outline : Icons.edit_outlined,
                  size: 18,
                ),
                label: Text(event.isGeradoPorFinancas ? 'Ver detalhes' : 'Editar'),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: corBorda, width: 1.5),
                ),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => event.isGeradoPorFinancas
                      ? _FinanceEventInfoDialog(event: event)
                      : _EventFormDialog(event: event),
                ),
              ),
            ),
```

Em `_EventFormDialogState`, adicionar o campo de estado e inicializá-lo:

```dart
  late CategoriaEvento _categoria;
```

Em `initState`, logo após `_ehDiaInteiro = event?.ehDiaInteiro ?? false;`:

```dart
    // Eventos financeiros nunca chegam a este formulário (ver `_EventCard`, que os abre em
    // `_FinanceEventInfoDialog` em vez deste diálogo) — `event?.categoria` aqui é sempre
    // social/trabalho/geral quando editando, ou null (novo evento, default geral).
    _categoria = event?.categoria ?? CategoriaEvento.geral;
```

Adicionar o seletor no `content` do `AlertDialog`, logo após o `ListTile` de "Término" (antes do fechamento de `children: [...]` da `Column`):

```dart
            const SizedBox(height: 16),
            Text('Categoria', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Social'),
                  selected: _categoria == CategoriaEvento.social,
                  onSelected: (_) => setState(() {
                    _categoria = CategoriaEvento.social;
                    _hasChanges = true;
                  }),
                ),
                ChoiceChip(
                  label: const Text('Trabalho'),
                  selected: _categoria == CategoriaEvento.trabalho,
                  onSelected: (_) => setState(() {
                    _categoria = CategoriaEvento.trabalho;
                    _hasChanges = true;
                  }),
                ),
                ChoiceChip(
                  label: const Text('Geral'),
                  selected: _categoria == CategoriaEvento.geral,
                  onSelected: (_) => setState(() {
                    _categoria = CategoriaEvento.geral;
                    _hasChanges = true;
                  }),
                ),
              ],
            ),
```

Em `_salvar()`, passar `categoria: _categoria` nas duas chamadas ao repository:

```dart
      if (_isEditing) {
        await repo.updateEvent(
          eventId: widget.event!.id,
          titulo: titulo,
          descricao: _descriptionController.text.trim(),
          dataHoraInicio: _startTime,
          dataHoraFim: _endTime,
          ehDiaInteiro: _ehDiaInteiro,
          categoria: _categoria,
        );
      } else {
        await repo.createEvent(
          titulo: titulo,
          descricao: _descriptionController.text.trim(),
          dataHoraInicio: _startTime,
          dataHoraFim: _endTime,
          ehDiaInteiro: _ehDiaInteiro,
          categoria: _categoria,
        );
      }
```

- [ ] **Step 4: Rodar e verificar que passam**

Run: `cd mobile && flutter test test/features/calendar/evento_financeiro_readonly_test.dart test/features/calendar/categoria_selector_test.dart`
Expected: PASS

Run a suíte inteira de calendar: `cd mobile && flutter test test/features/calendar/`
Expected: PASS (zero regressão — `touch_target_test.dart`/`all_day_event_test.dart`/`revalidation_test.dart` continuam passando; o botão "Editar" ainda existe para eventos não-financeiros, que é o caso coberto por esses testes existentes).

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/calendar/calendar_screen.dart mobile/test/features/calendar/evento_financeiro_readonly_test.dart mobile/test/features/calendar/categoria_selector_test.dart
git commit -m "feat(calendar): evento financeiro somente leitura, seletor de categoria no formulário manual"
```

---

### Task 9: Invalida a Agenda ao salvar/confirmar em Finanças

**Files:**
- Modify: `mobile/lib/features/financas/novo_lancamento_screen.dart`
- Modify: `mobile/lib/features/financas/confirmar_lancamento_sheet.dart`

Sem teste widget dedicado nesta tarefa: `ref.invalidate` não tem efeito observável em um teste unitário isolado sem montar a árvore completa de providers das duas telas ao mesmo tempo (Finanças + Agenda), o que já está fora do padrão dos testes existentes dessas duas telas (que testam cada uma isoladamente). A garantia aqui é por leitura de código — mesmo padrão de `ref.invalidate` já usado nos dois arquivos para os providers de Finanças, só estendido aos de Agenda.

**Files:**
- Modify: `mobile/lib/features/financas/novo_lancamento_screen.dart`
- Modify: `mobile/lib/features/financas/confirmar_lancamento_sheet.dart`

**Interfaces:**
- Consumes: `upcomingEventsProvider`, `monthEventsProvider` de `../calendar/calendar_providers.dart` (já existentes).

- [ ] **Step 1: Implementar em `novo_lancamento_screen.dart`**

Adicionar o import:

```dart
import '../calendar/calendar_providers.dart';
```

Em `_salvar()`, após `ref.invalidate(financeSummaryProvider);`:

```dart
      ref.invalidate(lancamentosDoMesProvider);
      ref.invalidate(lancamentosPendentesProvider);
      ref.invalidate(financeSummaryProvider);
      // Salvar aqui pode ter criado, atualizado ou removido um evento na Agenda (despesa/
      // fatura confirmada, ou isPago mudando) — invalida para que a aba de Agenda, se já
      // montada, reflita sem precisar de refresh manual.
      ref.invalidate(upcomingEventsProvider);
      ref.invalidate(monthEventsProvider);
```

- [ ] **Step 2: Implementar em `confirmar_lancamento_sheet.dart`**

Adicionar o import:

```dart
import '../calendar/calendar_providers.dart';
```

Em `invalidateAfterMudanca()`:

```dart
  void invalidateAfterMudanca() {
    // Confirmar/ignorar muda o que `GET /financas/resumo` retorna (Saldo Livre,
    // despesas pendentes) e, no caso de confirmar, move o item para o mês —
    // por isso invalidamos as duas outras fontes de dados da tela de Finanças
    // além da lista de pendentes. `lancamentosDoMesProvider` é `.family`;
    // invalidar sem argumento invalida todas as instâncias, o que está correto
    // aqui porque não sabemos qual mês a tela tem aberto no momento.
    ref.invalidate(lancamentosPendentesProvider);
    ref.invalidate(financeSummaryProvider);
    ref.invalidate(lancamentosDoMesProvider);
    // Confirmar uma despesa/fatura cria um evento real na Agenda; ignorar remove o
    // eventual evento já existente. Mesmo raciocínio de invalidação cruzada.
    ref.invalidate(upcomingEventsProvider);
    ref.invalidate(monthEventsProvider);
  }
```

- [ ] **Step 3: Rodar a suíte de Finanças e Agenda para garantir zero regressão**

Run: `cd mobile && flutter test test/features/financas/ test/features/calendar/`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add mobile/lib/features/financas/novo_lancamento_screen.dart mobile/lib/features/financas/confirmar_lancamento_sheet.dart
git commit -m "feat(financas): invalida providers de Agenda ao salvar/confirmar/ignorar lançamento"
```

---

## Verificação final

- [ ] **Backend:** `cd backend && npx jest` — suíte inteira PASS.
- [ ] **Backend:** `cd backend && npx tsc --noEmit` (ou o comando de typecheck configurado no `package.json`) — sem erros de tipo.
- [ ] **Mobile:** `cd mobile && flutter analyze` — sem warnings novos.
- [ ] **Mobile:** `cd mobile && flutter test` — suíte inteira PASS.
- [ ] **Manual, dispositivo/emulador com conta Google de teste conectada** (`temEscopoAgenda: true`):
  1. Confirmar uma despesa em Finanças (via `confirmar_lancamento_sheet` ou criando manualmente com tipo Despesa) → evento aparece na Agenda, na data de vencimento, com ícone financeiro.
  2. Marcar essa despesa como paga (switch em `novo_lancamento_screen`) → evento some da Agenda ao reabrir a aba.
  3. Criar um compromisso manual escolhendo categoria Social → ícone de social aparece na lista do dia.
  4. Tocar em "Ver detalhes" de um evento financeiro → vê a visualização somente leitura, sem conseguir editar/excluir.
  5. Confirmar uma receita → nenhum evento aparece na Agenda.
