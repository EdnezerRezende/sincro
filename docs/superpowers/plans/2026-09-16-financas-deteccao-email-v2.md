# Finanças — detecção de e-mails financeiros v2 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** fazer e-mails de cobrança de **qualquer** instituição virarem `LancamentoFinanceiro` em `PENDENTE_REVISAO`, sem allowlist, sem valor fabricado, reprocessando o que já foi sincronizado e lendo o PDF anexo quando o corpo não traz valor/vencimento.

**Architecture:** a lógica financeira sai do loop de `EmailSyncService` para um `FinanceEmailProcessor` único usado por e-mails novos e pelo reprocessamento versionado (`EmailSummary.parserFinancasVersao`). A detecção vira duas etapas: `triagem()` (remetente + assunto + marcador → `nao|forte|fraco`) e `parse()` (corpo + anexos; `fraco` só cria com evidência de cobrança E1–E6). `INSTITUTION_MAP` vira enriquecimento.

**Tech Stack:** NestJS 11, Prisma 7 (PostgreSQL), googleapis/gaxios 7, pdf-parse 2.4.5 (API v2 `PDFParse`), Jest + ts-jest.

**Spec:** `docs/superpowers/specs/2026-09-15-financas-deteccao-email-v2-design.md` — o plano argumenta a partir dela; executores leem ambos.

## Global Constraints

- 100 % determinístico, **sem LLM** no caminho de finanças.
- Onde a spec escreve `\b`, a implementação usa fronteira Unicode `(?<![\p{L}\p{N}])…(?![\p{L}\p{N}])` com flag `u` (helper `wb()` da Task 2). Texto sempre NFC e case-insensitive, exceto `\b(IPTU|IPVA|DARF|DAS)\b` (case-sensitive).
- Regras de remetente (S3/S3f/S7/mapa) operam sobre o **endereço extraído**, nunca sobre o header `From` cru.
- Constantes: `CABECA_TIPO = 600`, `CABECA_EVIDENCIA = 1500`, `FINANCE_PARSER_VERSION = 2`, `LOTE_REPROCESSAMENTO = 50`, `PDF_MAX_BYTES = 5 * 1024 * 1024`, `PDF_PAGINAS = 3`, `PDF_TIMEOUT_MS = 10_000`, `MARCADOR_NOME = 'Sincro/Finanças'`, `MARCADOR_JANELA = 'newer_than:90d'`, `MARCADOR_MAX = 100`.
- Lançamentos `EMAIL_PARSER` + `PENDENTE_REVISAO` são da máquina (podem ser atualizados/removidos); `CONFIRMADO`, `IGNORADO` e `origem MANUAL` nunca são tocados.
- Valor extraído `0,00` → `null`. Nunca extrair valor de segmento de parcelamento.
- Comandos: `cd backend && npx jest <arquivo>`; commit após cada task na branch `feat/financas-deteccao-email-v2`.
- Mensagens de commit em português, sufixo `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`.

## File Structure

| Arquivo | Responsabilidade |
|---------|------------------|
| `backend/prisma/schema.prisma` + `prisma/migrations/20260916000000_add_email_finance_parser_version/migration.sql` | 3 colunas novas em `resumos_email` + índice |
| `backend/src/common/text-match.util.ts` (novo) | `wb()`, `normalizar()` — fronteira Unicode e NFC |
| `backend/src/common/email-address.util.ts` (novo) | `extrairEndereco`, `localPart`, `dominio`, `rotulosDominio` |
| `backend/src/common/with-timeout.ts` (novo) | `withTimeout`, `TimeoutError` |
| `backend/src/financas/parser/institution-map.ts` (novo) | mapa por sufixo de domínio + `UTILIDADE_RE` → `resolverInstituicao` |
| `backend/src/financas/parser/finance-email-detector.ts` (novo) | `triagem()` — vetos duros/brandos, S1–S8, S6/S3f/S7 |
| `backend/src/financas/parser/finance-extractors.ts` (novo) | `extrairValor`, `extrairDataVencimento`, `extrairCodigoBarras`, `DATE_ANCHORS`, `ANCORAS_VALOR_COBRANCA` |
| `backend/src/financas/parser/finance-evidence.ts` (novo) | E1–E6, suficiência, evidência negativa |
| `backend/src/financas/parser/email-finance-regex-parser.service.ts` (modificar) | `parse()` orientado a triagem, `complementarComTexto`, tipo por conteúdo; remove `matches`/`processEmail` |
| `backend/src/financas/parser/finance-email-processor.service.ts` (novo) | `processar()` — passos 1–5, `removerLancamentoDaMaquina` |
| `backend/src/gmail/gmail-error.util.ts` (modificar) | `classificarErroGmail` |
| `backend/src/gmail/gmail-api-client.service.ts` (modificar) | `labelIds` em `FetchedEmail`, `fetchFullBodyComAnexos`, HTML-em-text/plain, `fetchPdfAttachmentText`, `listarIdsComMarcador` |
| `backend/src/email-sync/email-sync.service.ts` (modificar) | passos 0 (marcador), A (novos), B (reprocessamento) |
| `backend/src/financas/financas.module.ts` (modificar) | provê/exporta `FinanceEmailProcessor` |
| `backend/src/financas/parser/__fixtures__/…` | amostra real, corpos reais, fictícios, adversariais |

---

### Task 1: Schema Prisma e migration

**Files:**
- Modify: `backend/prisma/schema.prisma` (model `EmailSummary`)
- Create: `backend/prisma/migrations/20260916000000_add_email_finance_parser_version/migration.sql`

**Interfaces:**
- Produces: campos `EmailSummary.labelIds: string[]`, `EmailSummary.parserFinancasVersao: number | null`, `EmailSummary.parserFinancasTentativas: number`.

- [ ] **Step 1: Editar o model**

Em `schema.prisma`, dentro de `model EmailSummary`, depois de `lidoNoApp`:

```prisma
  labelIds                 String[] @default([]) @map("label_ids")
  parserFinancasVersao     Int?     @map("parser_financas_versao")
  parserFinancasTentativas Int      @default(0) @map("parser_financas_tentativas")
```

e depois de `@@index([userId])`:

```prisma
  @@index([userId, parserFinancasVersao, parserFinancasTentativas])
```

- [ ] **Step 2: Criar a migration à mão** (sem banco local com dados; conteúdo igual ao que `prisma migrate dev` geraria)

`migration.sql`:

```sql
-- AlterTable
ALTER TABLE "resumos_email" ADD COLUMN     "label_ids" TEXT[] DEFAULT ARRAY[]::TEXT[],
ADD COLUMN     "parser_financas_versao" INTEGER,
ADD COLUMN     "parser_financas_tentativas" INTEGER NOT NULL DEFAULT 0;

-- CreateIndex
CREATE INDEX "resumos_email_user_id_parser_financas_versao_parser_financas_tentativas_idx" ON "resumos_email"("user_id", "parser_financas_versao", "parser_financas_tentativas");
```

- [ ] **Step 3: Gerar o client e validar**

Run: `cd backend && npx prisma validate && npx prisma generate`
Expected: `The schema at prisma/schema.prisma is valid` e client gerado sem erro.

- [ ] **Step 4: Rodar a suíte para garantir que nada quebrou**

Run: `cd backend && npx jest src/email-sync src/financas`
Expected: todos verdes (nenhum teste lê os campos novos ainda).

- [ ] **Step 5: Commit**

```bash
git add backend/prisma/schema.prisma backend/prisma/migrations/20260916000000_add_email_finance_parser_version
git commit -m "feat(financas): versão do parser, tentativas e labelIds em EmailSummary

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Utilitários de texto e endereço

**Files:**
- Create: `backend/src/common/text-match.util.ts`, `backend/src/common/text-match.util.spec.ts`
- Create: `backend/src/common/email-address.util.ts`, `backend/src/common/email-address.util.spec.ts`

**Interfaces:**
- Produces:
  - `wb(source: string, flags?: string): RegExp` — substitui cada `\b` literal do `source` por lookaround Unicode e compila com `flags` (padrão `'iu'`; sempre acrescenta `u`).
  - `normalizar(texto: string | null | undefined): string` — NFC, `''` para nulo.
  - `extrairEndereco(remetente: string): string | null` — `'Nome <a@b.com>'` → `'a@b.com'` minúsculo.
  - `localPart(endereco: string): string`, `dominio(endereco: string): string`, `rotulosDominio(endereco: string): string[]` (`'x@mail.nubank.com.br'` → `['mail','nubank','com','br']`).

- [ ] **Step 1: Testes de `wb`/`normalizar`**

`text-match.util.spec.ts`:

```ts
import { normalizar, wb } from './text-match.util';

describe('wb', () => {
  it('matches accented words as whole words (JS \\b would fail)', () => {
    expect(wb('\\bcarn[êe]\\b').test('seu carnê chegou')).toBe(true);
    expect(wb('\\bcarn[êe]\\b').test('carne de primeira')).toBe(false);
  });
  it('does not match inside a longer word', () => {
    expect(wb('\\b(sua|a)\\s+fatura\\b').test('parcelamento da fatura disponível')).toBe(false);
    expect(wb('\\b(sua|a)\\s+fatura\\b').test('a fatura do seu cartão')).toBe(true);
  });
  it('is case-insensitive by default and accepts explicit flags', () => {
    expect(wb('\\bDAS\\b').test('resumo das compras')).toBe(true);
    expect(wb('\\bDAS\\b', 'u').test('resumo das compras')).toBe(false);
    expect(wb('\\bDAS\\b', 'u').test('guia DAS emitida')).toBe(true);
  });
  it('treats venc. with the dot as a whole word', () => {
    expect(wb('\\bvenc\\.').test('Venc. 10/10/2026')).toBe(true);
  });
});

describe('normalizar', () => {
  it('normalizes NFD to NFC and tolerates null', () => {
    expect(normalizar('cartão')).toBe('cartão');
    expect(normalizar(null)).toBe('');
  });
});
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd backend && npx jest src/common/text-match.util.spec.ts`
Expected: FAIL — módulo não encontrado.

- [ ] **Step 3: Implementar**

`text-match.util.ts`:

```ts
/** Fronteira de palavra Unicode. O `\b` nativo do JS é ASCII: falha em `carnê`, `até`, `venc.`
 *  e deixa `da fatura` casar `a fatura`. Toda regex de detecção financeira passa por aqui. */
export const WB_L = '(?<![\\p{L}\\p{N}])';
export const WB_R = '(?![\\p{L}\\p{N}])';

export function wb(source: string, flags = 'iu'): RegExp {
  let i = 0;
  const converted = source.replace(/\\b/g, () => (i++ % 2 === 0 ? WB_L : WB_R));
  const finalFlags = flags.includes('u') ? flags : `${flags}u`;
  return new RegExp(converted, finalFlags);
}

export function normalizar(texto: string | null | undefined): string {
  return (texto ?? '').normalize('NFC');
}
```

Nota: `wb` alterna esquerda/direita a cada `\b` — escreva sempre pares abertura/fechamento no `source` (ex.: `\\bfoo\\b`). Para um só `\b` de abertura (ex.: `\\bvenc`), o primeiro é sempre esquerda — comportamento desejado.

- [ ] **Step 4: Rodar e ver passar**

Run: `cd backend && npx jest src/common/text-match.util.spec.ts`
Expected: PASS (4 testes).

- [ ] **Step 5: Testes de endereço**

`email-address.util.spec.ts`:

```ts
import { dominio, extrairEndereco, localPart, rotulosDominio } from './email-address.util';

describe('email-address.util', () => {
  it('extracts the address from a display-name header, lowercased', () => {
    expect(extrairEndereco('Pefisa <Pagamento@Pefisa.com.br>')).toBe('pagamento@pefisa.com.br');
    expect(extrairEndereco('todomundo@nubank.com.br')).toBe('todomundo@nubank.com.br');
    expect(extrairEndereco('"Nome <a@b.com> (não responda)"')).toBe('a@b.com');
  });
  it('returns null when there is no address', () => {
    expect(extrairEndereco('Fulano de Tal')).toBeNull();
  });
  it('splits local part, domain and labels', () => {
    expect(localPart('fatura_digital@cartaosamsclub.com.br')).toBe('fatura_digital');
    expect(dominio('x@leroymerlinpay.pefisa.com.br')).toBe('leroymerlinpay.pefisa.com.br');
    expect(rotulosDominio('x@mail.nubank.com.br')).toEqual(['mail', 'nubank', 'com', 'br']);
  });
});
```

- [ ] **Step 6: Implementar**

`email-address.util.ts`:

```ts
/** Endereço de e-mail a partir do header `From` cru (`Nome <a@b.com>`, `a@b.com` ou variações).
 *  Toda regra de detecção financeira baseada em remetente opera sobre este valor. */
export function extrairEndereco(remetente: string): string | null {
  const angle = remetente.match(/<([^<>]+)>/);
  const candidato = (angle ? angle[1] : remetente).trim();
  const m = candidato.match(/[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}/i);
  return m ? m[0].toLowerCase() : null;
}

export function localPart(endereco: string): string {
  return endereco.slice(0, endereco.lastIndexOf('@'));
}

export function dominio(endereco: string): string {
  return endereco.slice(endereco.lastIndexOf('@') + 1);
}

export function rotulosDominio(endereco: string): string[] {
  return dominio(endereco).split('.').filter(Boolean);
}
```

- [ ] **Step 7: Rodar e ver passar; commit**

Run: `cd backend && npx jest src/common`
Expected: PASS.

```bash
git add backend/src/common/text-match.util.ts backend/src/common/text-match.util.spec.ts backend/src/common/email-address.util.ts backend/src/common/email-address.util.spec.ts
git commit -m "feat(common): fronteira de palavra Unicode e extração de endereço de remetente

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Mapa de instituições como enriquecimento

**Files:**
- Create: `backend/src/financas/parser/institution-map.ts`, `backend/src/financas/parser/institution-map.spec.ts`

**Interfaces:**
- Consumes: `extrairEndereco`, `rotulosDominio` (Task 2).
- Produces:
  - `type TipoPadrao = 'CARTAO' | 'OUTRO'`
  - `interface Instituicao { nome: string; tipoPadrao?: TipoPadrao; mapeada: boolean }`
  - `resolverInstituicao(remetente: string, assunto: string): Instituicao`
  - `UTILIDADE_RE: RegExp`
  - `deriveInstituicaoFromDomain(endereco: string): string | null` (movido do parser, mesma lógica)

- [ ] **Step 1: Testes**

```ts
import { resolverInstituicao, UTILIDADE_RE } from './institution-map';

describe('resolverInstituicao', () => {
  it('matches by domain suffix, covering subdomains', () => {
    expect(resolverInstituicao('Leroy <noreply@leroymerlinpay.pefisa.com.br>', '')).toEqual({
      nome: 'Pefisa', tipoPadrao: 'CARTAO', mapeada: true,
    });
    expect(resolverInstituicao('x@faturaneoenergiabrasilia.com.br', '')).toEqual({
      nome: 'Neoenergia', tipoPadrao: 'OUTRO', mapeada: true,
    });
  });
  it('does not match a look-alike domain', () => {
    expect(resolverInstituicao('x@nubank.com.br.evil.com', '').mapeada).toBe(false);
  });
  it('derives a name for an unknown institution and leaves tipo undefined', () => {
    expect(resolverInstituicao('Banco Alfa <fatura@bancoalfa.com.br>', 'Sua fatura fechou')).toEqual({
      nome: 'Bancoalfa', tipoPadrao: undefined, mapeada: false,
    });
  });
  it('infers OUTRO for an unknown utility by domain radical or "conta de" subject', () => {
    expect(resolverInstituicao('avisos@energiaxyz.com.br', 'Sua conta chegou').tipoPadrao).toBe('OUTRO');
    expect(resolverInstituicao('contato@fornecedora.com.br', 'Sua conta de luz chegou').tipoPadrao).toBe('OUTRO');
  });
  it('UTILIDADE_RE does not match gastrobar or netflix', () => {
    expect(UTILIDADE_RE.test('gastrobar')).toBe(false);
    expect(UTILIDADE_RE.test('netflix')).toBe(false);
    expect(UTILIDADE_RE.test('neoenergia')).toBe(true);
    expect(UTILIDADE_RE.test('comgas')).toBe(true);
  });
  it('falls back to "Desconhecida" without an address', () => {
    expect(resolverInstituicao('Fulano', '').nome).toBe('Desconhecida');
  });
});
```

- [ ] **Step 2: Rodar e ver falhar** — `npx jest src/financas/parser/institution-map.spec.ts` → módulo não encontrado.

- [ ] **Step 3: Implementar**

```ts
import { extrairEndereco, dominio, rotulosDominio } from '../../common/email-address.util';
import { wb } from '../../common/text-match.util';

export type TipoPadrao = 'CARTAO' | 'OUTRO';
export interface Instituicao { nome: string; tipoPadrao?: TipoPadrao; mapeada: boolean }

interface Entrada { dominio: string; nome: string; tipoPadrao: TipoPadrao }

/** ENRIQUECIMENTO, não porta de entrada: dá nome bonito e tipo padrão a quem conhecemos. A
 *  detecção (finance-email-detector.ts) funciona sem esta lista. Casamento por SUFIXO de domínio. */
const INSTITUTION_MAP: Entrada[] = [
  { dominio: 'bb.com.br', nome: 'Banco do Brasil', tipoPadrao: 'CARTAO' },
  { dominio: 'caixa.gov.br', nome: 'Caixa', tipoPadrao: 'CARTAO' },
  { dominio: 'santander.com.br', nome: 'Santander', tipoPadrao: 'CARTAO' },
  { dominio: 'itau.com.br', nome: 'Itaú', tipoPadrao: 'CARTAO' },
  { dominio: 'itaucard.com.br', nome: 'Itaú', tipoPadrao: 'CARTAO' },
  { dominio: 'bradesco.com.br', nome: 'Bradesco', tipoPadrao: 'CARTAO' },
  { dominio: 'nubank.com.br', nome: 'Nubank', tipoPadrao: 'CARTAO' },
  { dominio: 'bancointer.com.br', nome: 'Inter', tipoPadrao: 'CARTAO' },
  { dominio: 'c6bank.com.br', nome: 'C6 Bank', tipoPadrao: 'CARTAO' },
  { dominio: 'btgpactual.com', nome: 'BTG Pactual', tipoPadrao: 'CARTAO' },
  { dominio: 'neon.com.br', nome: 'Neon', tipoPadrao: 'CARTAO' },
  { dominio: 'picpay.com', nome: 'PicPay', tipoPadrao: 'CARTAO' },
  { dominio: 'mercadopago.com.br', nome: 'Mercado Pago', tipoPadrao: 'CARTAO' },
  { dominio: 'pagseguro.com.br', nome: 'PagBank', tipoPadrao: 'CARTAO' },
  { dominio: 'willbank.com.br', nome: 'Will Bank', tipoPadrao: 'CARTAO' },
  { dominio: 'xpi.com.br', nome: 'XP', tipoPadrao: 'CARTAO' },
  { dominio: 'sicoob.com.br', nome: 'Sicoob', tipoPadrao: 'CARTAO' },
  { dominio: 'sicredi.com.br', nome: 'Sicredi', tipoPadrao: 'CARTAO' },
  { dominio: 'brb.com.br', nome: 'BRB', tipoPadrao: 'CARTAO' },
  { dominio: 'bancopan.com.br', nome: 'Banco Pan', tipoPadrao: 'CARTAO' },
  { dominio: 'bancobmg.com.br', nome: 'BMG', tipoPadrao: 'CARTAO' },
  { dominio: 'pefisa.com.br', nome: 'Pefisa', tipoPadrao: 'CARTAO' },
  { dominio: 'cartaosamsclub.com.br', nome: "Sam's Club", tipoPadrao: 'CARTAO' },
  { dominio: 'midway.com.br', nome: 'Midway', tipoPadrao: 'CARTAO' },
  { dominio: 'claro.com.br', nome: 'Claro', tipoPadrao: 'OUTRO' },
  { dominio: 'vivo.com.br', nome: 'Vivo', tipoPadrao: 'OUTRO' },
  { dominio: 'tim.com.br', nome: 'TIM', tipoPadrao: 'OUTRO' },
  { dominio: 'enel.com.br', nome: 'Enel', tipoPadrao: 'OUTRO' },
  { dominio: 'neoenergiabrasilia.com.br', nome: 'Neoenergia', tipoPadrao: 'OUTRO' },
  { dominio: 'faturaneoenergiabrasilia.com.br', nome: 'Neoenergia', tipoPadrao: 'OUTRO' },
  { dominio: 'light.com.br', nome: 'Light', tipoPadrao: 'OUTRO' },
  { dominio: 'cpfl.com.br', nome: 'CPFL', tipoPadrao: 'OUTRO' },
  { dominio: 'cemig.com.br', nome: 'Cemig', tipoPadrao: 'OUTRO' },
  { dominio: 'sabesp.com.br', nome: 'Sabesp', tipoPadrao: 'OUTRO' },
  { dominio: 'comgas.com.br', nome: 'Comgás', tipoPadrao: 'OUTRO' },
  { dominio: 'starlink.com', nome: 'Starlink', tipoPadrao: 'OUTRO' },
  { dominio: 'portoseguro.com.br', nome: 'Porto Seguro', tipoPadrao: 'OUTRO' },
];

/** Radicais de concessionária, como prefixo/sufixo de um rótulo do domínio (`^gas` e `^net` ficaram
 *  de fora: casavam `gastrobar`/`netflix`). Só decide tipoPadrao de desconhecidos. */
export const UTILIDADE_RE = /^(energia|eletr|luz|agua|saneamento|telecom)|(energia|eletrica|luz|agua|gas)$/i;
const CONTA_DE_RE = wb('\\bconta de (luz|energia|[áa]gua|g[áa]s|internet|telefone)\\b');

const GENERIC_SECOND_LEVEL = new Set(['com', 'net', 'org', 'gov', 'edu', 'co']);
const GENERIC_SUBDOMAIN_LABELS = new Set([
  'mail', 'email', 'e', 'news', 'notificacoes', 'notificacao', 'mailer', 'info', 'no-reply', 'noreply',
]);

export function deriveInstituicaoFromDomain(endereco: string): string | null {
  const labels = rotulosDominio(endereco);
  if (labels.length < 2) return null;
  const publicSuffixLength = labels.length > 2 && GENERIC_SECOND_LEVEL.has(labels[labels.length - 2]) ? 2 : 1;
  const candidates = labels.slice(0, labels.length - publicSuffixLength);
  if (candidates.length === 0) return null;
  const significant = candidates.find((l) => !GENERIC_SUBDOMAIN_LABELS.has(l)) ?? candidates[candidates.length - 1];
  return significant.charAt(0).toUpperCase() + significant.slice(1);
}

export function resolverInstituicao(remetente: string, assunto: string): Instituicao {
  const endereco = extrairEndereco(remetente);
  if (!endereco) return { nome: 'Desconhecida', tipoPadrao: undefined, mapeada: false };
  const dom = dominio(endereco);
  const entrada = INSTITUTION_MAP.find((e) => dom === e.dominio || dom.endsWith(`.${e.dominio}`));
  if (entrada) return { nome: entrada.nome, tipoPadrao: entrada.tipoPadrao, mapeada: true };

  const utilidade = rotulosDominio(endereco).some((l) => UTILIDADE_RE.test(l)) || CONTA_DE_RE.test(assunto.normalize('NFC'));
  return {
    nome: deriveInstituicaoFromDomain(endereco) ?? 'Desconhecida',
    tipoPadrao: utilidade ? 'OUTRO' : undefined,
    mapeada: false,
  };
}
```

- [ ] **Step 4: Rodar e ver passar; commit**

Run: `cd backend && npx jest src/financas/parser/institution-map.spec.ts` → PASS.

```bash
git add backend/src/financas/parser/institution-map.ts backend/src/financas/parser/institution-map.spec.ts
git commit -m "feat(financas): mapa de instituições por sufixo de domínio como enriquecimento

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Triagem genérica (`finance-email-detector.ts`)

**Files:**
- Create: `backend/src/financas/parser/finance-email-detector.ts`, `backend/src/financas/parser/finance-email-detector.spec.ts`
- Create: `backend/src/financas/parser/__fixtures__/amostra-real-2026-09.json`

**Interfaces:**
- Consumes: `wb`, `normalizar` (Task 2); `extrairEndereco`, `localPart`, `rotulosDominio` (Task 2); `isSettledPaymentSubject` (existente em `invoice-subject-patterns.ts`).
- Produces:
  - `type NivelTriagem = 'nao' | 'forte' | 'fraco'`
  - `interface ResultadoTriagem { nivel: NivelTriagem; sinais: string[]; motivo: string | null; assuntoTemSubstantivoCobranca: boolean }`
  - `triagem(remetente: string, assunto: string, opts: { marcado: boolean }): ResultadoTriagem`
  - `SUBSTANTIVO_COBRANCA_RE: RegExp` (usado pela suficiência de E2 na Task 6)

- [ ] **Step 1: Fixture da amostra real** — `__fixtures__/amostra-real-2026-09.json` (remetente no formato real `Nome <endereço>`; `financeiro: true` deve dar `forte|fraco`, `false` deve dar `!== 'forte'`):

```json
[
  { "remetente": "Sam's Club <cartaosamsclub@sams.cartaosamsclub.com.br>", "assunto": "A fatura do seu Cartão de Crédito Sam’s Club vence em breve! Confira as formas de pagamento.", "financeiro": true },
  { "remetente": "Leroy Merlin Pay <noreply@leroymerlinpay.pefisa.com.br>", "assunto": "A fatura do seu Cartão Celebre! Elo chegou!", "financeiro": true },
  { "remetente": "Porto Consórcio <portoconsorcio@portoseguro.com.br>", "assunto": "Informativo Consórcio Porto Bank", "financeiro": true },
  { "remetente": "Nubank <todomundo@nubank.com.br>", "assunto": "Novo boleto emitido no seu CPF", "financeiro": true },
  { "remetente": "Nubank <todomundo@nubank.com.br>", "assunto": "A fatura do seu cartão Nubank está fechada", "financeiro": true },
  { "remetente": "Nubank <todomundo@nubank.com.br>", "assunto": "A fatura do seu cartão Nu Empresas está fechada", "financeiro": true },
  { "remetente": "Sam's Club <fatura_digital@cartaosamsclub.com.br>", "assunto": "A fatura do seu Cartão Sam's Club chegou. Confira!", "financeiro": true },
  { "remetente": "Santander <faturaporemail@santander.com.br>", "assunto": "Fatura por e-mail - Setembro/2026", "financeiro": true },
  { "remetente": "Santander <faturaporemail@santander.com.br>", "assunto": "Fatura por e-mail - Agosto/2026", "financeiro": true },
  { "remetente": "Starlink <no-reply@starlink.com>", "assunto": "Fatura da Starlink", "financeiro": true },
  { "remetente": "Pefisa <pagamento@pefisa.com.br>", "assunto": "Sua Fatura CELEBRE! ELO MAIS", "financeiro": true },
  { "remetente": "Neoenergia <cliente@faturaneoenergiabrasilia.com.br>", "assunto": "Fatura Digital 🧾 | 3288653", "financeiro": true },
  { "remetente": "Nomad <noreply@nomadglobal.com>", "assunto": "iPhone 18: 50% OFF no seguro! 🛡️ 📱", "financeiro": false },
  { "remetente": "LUZ <news@email.sualuz.com.br>", "assunto": "Quer ter economia na conta de luz?", "financeiro": false },
  { "remetente": "Neoenergia <cliente@neoenergiabrasilia.com.br>", "assunto": "Hoje celebramos a nossa parceria", "financeiro": false },
  { "remetente": "Nubank <todomundo@nubank.com.br>", "assunto": "O cadastro do seu Débito automático foi concluído.", "financeiro": false },
  { "remetente": "Nubank <todomundo@novidades.nubank.com.br>", "assunto": "Chegou o Respiro no cartão Nu Empresas", "financeiro": false },
  { "remetente": "Nubank <todomundo@novidades.nubank.com.br>", "assunto": "Descubra o seu novo Cartão PJ", "financeiro": false },
  { "remetente": "Nubank <todomundo@nubank.com.br>", "assunto": "Seu extrato da conta Nu Empresas", "financeiro": false },
  { "remetente": "Nubank <todomundo@nubank.com.br>", "assunto": "Extrato da sua conta do Nubank", "financeiro": false },
  { "remetente": "Nubank <todomundo@nubank.com.br>", "assunto": "Extrato da fatura do Cartão Nubank", "financeiro": false },
  { "remetente": "Neoenergia <cliente@neoenergiabrasilia.com.br>", "assunto": "Escolha como receber sua conta de luz", "financeiro": false },
  { "remetente": "Drogarias Pacheco <noreply@vtexcommerce.com.br>", "assunto": "Drogarias Pacheco | Seu pedido foi faturado!", "financeiro": false },
  { "remetente": "Google Play <googleplay-noreply@google.com>", "assunto": "Seu recibo de pedido do Google Play em 30 de ago. de 2026", "financeiro": false }
]
```

- [ ] **Step 2: Testes** — `finance-email-detector.spec.ts`:

```ts
import { readFileSync } from 'fs';
import { join } from 'path';
import { triagem } from './finance-email-detector';

const amostra = JSON.parse(readFileSync(join(__dirname, '__fixtures__', 'amostra-real-2026-09.json'), 'utf-8')) as {
  remetente: string; assunto: string; financeiro: boolean;
}[];
const t = (r: string, a: string, marcado = false) => triagem(r, a, { marcado });

describe('triagem — amostra real', () => {
  it.each(amostra.filter((e) => e.financeiro))('$assunto é candidato', ({ remetente, assunto }) => {
    expect(['forte', 'fraco']).toContain(t(remetente, assunto).nivel);
  });
  it.each(amostra.filter((e) => !e.financeiro))('$assunto não é forte', ({ remetente, assunto }) => {
    expect(t(remetente, assunto).nivel).not.toBe('forte');
  });
});

describe('triagem — instituições fictícias fora da lista', () => {
  it('Banco Alfa: ciclo próprio → forte (S1a)', () => {
    expect(t('Banco Alfa <fatura@bancoalfa.com.br>', 'Sua fatura Alfa Visa fechou').nivel).toBe('forte');
  });
  it('Coop Beta: boleto sem ciclo → fraco', () => {
    expect(t('Coop Beta <contato@coopbeta.coop.br>', 'Boleto da mensalidade de outubro').nivel).toBe('fraco');
  });
  it('Fintech Gama: valor com centavos + vencimento → forte (S8)', () => {
    expect(t('Gama <no-reply@gamapay.com>', 'Vencimento amanhã: R$ 89,90')).toMatchObject({ nivel: 'forte', sinais: ['S8'] });
  });
  it('Loja Delta: sem juros → veto', () => {
    expect(t('Loja Delta <ofertas@lojadelta.com.br>', 'Fatura em 12x sem juros — aproveite').nivel).toBe('nao');
  });
});

describe('triagem — sinais fortes', () => {
  it.each([
    ['Nubank <todomundo@nubank.com.br>', 'A fatura do seu cartão Nu Empresas está fechada', 'S1a'],
    ['Santander <faturaporemail@santander.com.br>', 'Fatura por e-mail - Setembro/2026', 'S1b'],
    ['Neoenergia <cliente@faturaneoenergiabrasilia.com.br>', 'Fatura Digital 🧾 | 3288653', 'S1b'],
    ['Nubank <todomundo@nubank.com.br>', 'Novo boleto emitido no seu CPF', 'S2'],
    ['Loja W <contato@lojaw.com.br>', 'Seu carnê chegou', 'S2'],
    ['Porto Consórcio <portoconsorcio@portoseguro.com.br>', 'Informativo Consórcio Porto Bank', 'S3'],
    ['Sam\'s Club <fatura_digital@cartaosamsclub.com.br>', 'Confira!', 'S3'],
  ])('%s / %s → forte por %s', (r, a, sinal) => {
    expect(t(r, a)).toMatchObject({ nivel: 'forte', sinais: [sinal] });
  });
  it('marcador força forte e anula veto', () => {
    expect(t('Nubank <todomundo@nubank.com.br>', 'Extrato da sua conta do Nubank', true)).toMatchObject({ nivel: 'forte', sinais: ['S4'] });
  });
  it('S1a sobrevive a cauda de marketing (veto brando)', () => {
    expect(t('Nubank <todomundo@nubank.com.br>', 'Sua fatura chegou. Saiba como pagar').nivel).toBe('forte');
    expect(t('Nubank <todomundo@nubank.com.br>', 'Sua fatura fechou — conheça o Nubank Ultravioleta').nivel).toBe('forte');
  });
  it('veto brando derruba S2/S3', () => {
    expect(t('Banco Z <contato@bancoz.com.br>', 'Boleto emitido — descubra o app').nivel).toBe('nao');
  });
  it('assunto em NFD dá o mesmo resultado', () => {
    expect(t('Nubank <todomundo@nubank.com.br>', 'A fatura do seu cartão está fechada').nivel).toBe('forte');
  });
  it('S3/S7 usam o endereço extraído, não o From cru', () => {
    expect(t('Pefisa <pagamento@pefisa.com.br>', 'Sua Fatura CELEBRE! ELO MAIS')).toMatchObject({ nivel: 'fraco', sinais: expect.arrayContaining(['S6', 'S3f']) });
  });
});

describe('triagem — vetos duros', () => {
  it.each([
    'Seu extrato da conta Nu Empresas', 'O cadastro do seu Débito automático foi cadastrado', 'Seu recibo de pedido',
    'Seu pedido foi enviado', 'Pesquisa de satisfação', 'Convite especial', 'Ganhe pontos', 'Sorteio de R$ 100 mil',
    'Cashback liberado', 'iPhone 18: 50% OFF', 'Fatura em 12x sem juros', 'Simule seu financiamento', 'Empréstimo pré-aprovado',
    'Fatura contestada — estamos analisando', 'Sua fatura em análise', 'Disputa aberta', 'Boleto: como funciona?',
    'Fatura digital: saiba como aderir', 'Escolha como receber sua conta de luz', 'Cadastre-se na fatura por e-mail',
    'Adesão à fatura digital', 'Fatura do mês: prefira o débito automático', 'Agora você pode pagar boletos',
    'Sua senha vence em 3 dias', 'Código de verificação: 483920', 'Código de segurança', 'Alerta de segurança: novo acesso',
    'Renove seu seguro auto', 'Sua fatura está disponível: aproveite 20% de desconto', 'Cupom de R$ 10', 'Ofertas da semana',
    'Promoção: R$ 20 de desconto vence hoje', 'Oferta: R$ 0 de anuidade — vence hoje', 'Pagamento de boleto agendado',
    'Estorno realizado na sua conta', 'Depósito recebido', 'Pagamento recebido',
  ])('"%s" → nao', (assunto) => {
    expect(t('Banco Z <contato@bancoz.com.br>', assunto).nivel).toBe('nao');
  });
  it.each(['novidades@nubank.com.br', 'news@email.sualuz.com.br', 'newsletter@x.com', 'marketing@x.com', 'promo@x.com', 'ofertas@x.com', 'comunicacao@x.com'])(
    'remetente %s → nao', (end) => { expect(t(`X <${end}>`, 'Sua fatura chegou').nivel).toBe('nao'); },
  );
  it('comprovante de pagamento → nao (settled)', () => {
    expect(t('Banco Z <contato@bancoz.com.br>', 'Comprovante de pagamento da fatura').nivel).toBe('nao');
  });
});

describe('triagem — adversariais de assunto nunca são forte', () => {
  it.each([
    ['Google <no-reply@accounts.google.com>', 'Sua conta Google está pendente de verificação'],
    ['Spotify <no-reply@spotify.com>', 'Sua conta Spotify: nova senha disponível'],
    ['Banco Z <contato@bancoz.com.br>', 'Parcelamento da fatura agora disponível no app'],
    ['Nubank <todomundo@nubank.com.br>', 'Parcele sua fatura em 12x'],
    ['Nubank <todomundo@nubank.com.br>', 'Dica: como entender sua fatura'],
    ['Açougue <contato@acougue.com.br>', 'Carne de primeira toda semana'],
    ['Banco Z <contato@bancoz.com.br>', 'Entenda o que é a linha digitável'],
    ['Escola X <financeiro@escolax.com.br>', 'Reunião de pais'],
    ['Clínica Y <faturamento@clinicay.com.br>', 'Confirmação de agendamento'],
    ['Banco Z <contato@bancoz.com.br>', 'Ganhe R$ 50 de bônus até o vencimento'],
    ['Banco Z <contato@bancoz.com.br>', 'Seu limite subiu para R$ 5.000'],
    ['Nubank <todomundo@nubank.com.br>', 'Pix recebido de Fulano'],
    ['Nubank <todomundo@nubank.com.br>', 'Você recebeu um Pix de Fulano'],
    ['Nubank <todomundo@nubank.com.br>', 'Resumo das suas compras'],
    ['Enel <cliente@enel.com.br>', 'Aviso de interrupção de energia programada'],
    ['Loja <contato@lojafav.com.br>', 'Fatura digital da sua loja favorita'],
    ['SaaS <suporte@saas.com>', 'Sua cobrança foi ajustada'],
    ['RH <rh@empresa.com.br>', 'Prestação de contas — viagem'],
  ])('%s / %s', (r, a) => {
    expect(t(r, a).nivel).not.toBe('forte');
  });
});

describe('triagem — sinais fracos e substantivo de cobrança', () => {
  it.each(['Guia IPTU 2026', 'IPVA disponível', 'DAS do mês', 'Sua conta chegou', 'Sua conta de luz', 'Seguro auto', 'Linha digitável do mês', 'Código de barras atualizado', 'Cobrança de setembro', 'Consórcio contemplado', 'Financiamento aprovado', 'Empréstimo liberado', 'Prestação 3', 'Parcelas do curso', 'Anuidade 2026', 'Vencimento hoje'])(
    '"%s" → fraco (S6)', (a) => {
      const r = t('Empresa <contato@empresa-qualquer.com.br>', a);
      expect(r.nivel).toBe('fraco');
      expect(r.sinais).toContain('S6');
    },
  );
  it('DAS minúsculo não é S6', () => {
    expect(t('Empresa <contato@empresa-qualquer.com.br>', 'Resumo das compras').sinais).not.toContain('S6');
  });
  it('S1b sem período e sem veto → fraco', () => {
    expect(t('Loja <contato@lojafav.com.br>', 'Fatura digital da sua loja favorita').nivel).toBe('fraco');
  });
  it.each(['leroymerlinpay', 'faturaneoenergiabrasilia', 'bancoalfa', 'gamapay', 'cartaosamsclub', 'nubank'])('S7 casa %s', (rotulo) => {
    expect(t(`X <x@${rotulo}.com>`, 'Olá').sinais).toContain('S7');
  });
  it.each(['nomadglobal', 'google', 'spotify', 'gastrobar', 'muffin'])('S7 não casa %s', (rotulo) => {
    expect(t(`X <x@${rotulo}.com>`, 'Olá').nivel).toBe('nao');
  });
  it('assuntoTemSubstantivoCobranca reflete S6/S1/S2', () => {
    expect(t('X <x@x.com>', 'Fatura da Starlink').assuntoTemSubstantivoCobranca).toBe(true);
    expect(t('X <x@nubank.com.br>', 'Olá').assuntoTemSubstantivoCobranca).toBe(false);
  });
});
```

- [ ] **Step 3: Rodar e ver falhar** — módulo não encontrado.

- [ ] **Step 4: Implementar** — `finance-email-detector.ts`:

```ts
import { extrairEndereco, localPart, rotulosDominio } from '../../common/email-address.util';
import { normalizar, wb } from '../../common/text-match.util';
import { isSettledPaymentSubject } from './invoice-subject-patterns';

export type NivelTriagem = 'nao' | 'forte' | 'fraco';
export interface ResultadoTriagem {
  nivel: NivelTriagem;
  sinais: string[];
  motivo: string | null;
  assuntoTemSubstantivoCobranca: boolean;
}

// ---------- Vetos ----------
/** Duros: nunca criam lançamento, nem com S1a. Marketing, segurança, pagamento já feito, movimentações
 *  que NÃO são cobrança (pix/depósito/estorno recebido, agendado). */
const VETOS_DUROS: RegExp[] = [
  wb('\\bextratos?\\b'),
  wb('d[eé]bito autom[aá]tico .{0,30}(conclu[ií]d|cadastrad|ativad)'),
  wb('recibo de pedido'),
  wb('pedido .{0,20}(faturado|enviado|entregue)'),
  wb('\\bseu pedido\\b'),
  wb('\\bpesquisa\\b'),
  wb('\\bconvite\\b'),
  wb('\\bganhe\\b'),
  wb('\\bsorteio\\b'),
  wb('\\bcashback\\b'),
  wb('\\d+ ?% ?(off|de desconto)'),
  wb('\\bsem juros\\b'),
  wb('\\bsimule\\b'),
  wb('pr[ée]-aprovad'),
  wb('\\bcontestad'),
  wb('contesta[çc][ãa]o'),
  wb('em an[áa]lise'),
  wb('\\bdisputa\\b'),
  wb('\\bcomo (funciona|aderir|receber)\\b'),
  wb('cadastre-se'),
  wb('\\bader(ir|ência|são)\\b'),
  wb('\\bprefira\\b'),
  wb('\\bagora voc[êe] pode\\b'),
  wb('\\bsenha\\b'),
  wb('\\bc[óo]digo de (verifica[çc][ãa]o|seguran[çc]a|acesso)\\b'),
  wb('\\balerta de seguran[çc]a\\b'),
  wb('\\brenove\\b'),
  wb('\\b(com|de) desconto\\b'),
  wb('\\bcupom\\b'),
  wb('\\bofertas?\\b'),
  wb('promo[çc][ãa]o'),
  wb('\\bagendad[oa]\\b'),
  wb('\\bestorno\\b'),
  wb('\\brecebid[oa]\\b'),
];
/** Brandos: cauda de marketing num aviso legítimo ("Sua fatura chegou. Saiba como pagar") não o anula —
 *  só derrubam quando S1a NÃO casa. */
const VETOS_BRANDOS: RegExp[] = [
  wb('\\bnovidades?\\b'), wb('\\bdescubra\\b'), wb('\\bconhe[çc]a\\b'), wb('\\bdica\\b'),
  wb('\\bsaiba\\b'), wb('\\bentenda\\b'), wb('\\bcomo entender\\b'), wb('\\baproveite\\b'),
];
const VETO_REMETENTE = /novidades\.|^news@|newsletter|^marketing@|promo|^ofertas?@|^comunicacao@/i;

// ---------- Sinais fortes ----------
const S1A = wb(
  '\\b(sua|a|nova)\\s+(fatura|cobran[çc]a|mensalidade|boleto|carn[êe])\\b.{0,45}\\b(fechou|fechada|chegou|dispon[ií]vel|gerada|emitida|vence|venceu|em atraso|pendente)\\b',
);
const MESES = 'janeiro|fevereiro|mar[çc]o|abril|maio|junho|julho|agosto|setembro|outubro|novembro|dezembro';
const S1B = wb(`\\bfatura\\s+(por e-?mail|digital|do m[êe]s|do cart[ãa]o)\\b.{0,20}[-–|:]\\s*(\\w+\\s*/\\s*\\d{4}|\\d{5,}|${MESES})`);
const S2: RegExp[] = [
  wb('\\bboletos?\\b.{0,45}\\b(emitid|gerad|dispon[ií]vel|chegou|venc)'),
  wb('\\bcarn[êe]\\b.{0,45}\\b(chegou|dispon[ií]vel|venc)'),
];
const S3 = /^(fatura|faturas|fatura_digital|faturaporemail|boleto|boletos|invoice|invoices|\w*consorcio)($|[._-])/i;
const S8_VALOR = /R\$\s?(\d{1,3}(\.\d{3})*|\d+),\d{2}/;
const S8_VENC = wb('\\bvenc');

// ---------- Sinais fracos ----------
export const SUBSTANTIVO_COBRANCA_RE = wb(
  '\\bfaturas?\\b|\\bboletos?\\b|\\bcobran[çc]a\\b|\\bcons[óo]rcio\\b|\\bfinanciamento\\b|\\bempr[ée]stimo\\b|\\bpresta[çc][ãa]o\\b|\\bvenc(e|imento)\\b|\\bmensalidade\\b|\\bparcelas?\\b|\\banuidade\\b|\\bconta de (luz|energia|[áa]gua|g[áa]s|internet|telefone)\\b|\\bseguro\\b|\\bsua conta chegou\\b|linha digit[áa]vel|c[óo]digo de barras',
);
const S6_CASE_SENSITIVE = wb('\\b(IPTU|IPVA|DARF|DAS)\\b', 'u');
const S3F = /^(pagamento|pagamentos|financeiro|faturamento|cobranca|cobrancas|billing|cartao|cartoes)($|[._-])/i;
const S7 = /^(banco|bank|cartao|cartoes|fatura|cobranca|financeira|credito|consorcio|seguros?|energia|telecom)|(pay|bank|card)$/i;

export function triagem(remetente: string, assunto: string, opts: { marcado: boolean }): ResultadoTriagem {
  const a = normalizar(assunto);
  const aLower = a.toLowerCase();
  const endereco = extrairEndereco(remetente);
  const local = endereco ? localPart(endereco) : '';
  const rotulos = endereco ? rotulosDominio(endereco) : [];
  const temSubstantivo = SUBSTANTIVO_COBRANCA_RE.test(aLower) || S6_CASE_SENSITIVE.test(a);
  const base = { assuntoTemSubstantivoCobranca: temSubstantivo };

  if (opts.marcado) return { ...base, nivel: 'forte', sinais: ['S4'], motivo: null };

  if (isSettledPaymentSubject(a)) return { ...base, nivel: 'nao', sinais: [], motivo: 'veto: pagamento já feito' };
  const duro = VETOS_DUROS.find((re) => re.test(aLower));
  if (duro) return { ...base, nivel: 'nao', sinais: [], motivo: `veto duro: ${duro.source}` };
  if (endereco && VETO_REMETENTE.test(endereco)) return { ...base, nivel: 'nao', sinais: [], motivo: 'veto: remetente de marketing' };

  if (S1A.test(aLower)) return { ...base, nivel: 'forte', sinais: ['S1a'], motivo: null };

  const brando = VETOS_BRANDOS.find((re) => re.test(aLower));
  if (brando) return { ...base, nivel: 'nao', sinais: [], motivo: `veto brando: ${brando.source}` };

  if (S1B.test(aLower)) return { ...base, nivel: 'forte', sinais: ['S1b'], motivo: null };
  if (S2.some((re) => re.test(aLower))) return { ...base, nivel: 'forte', sinais: ['S2'], motivo: null };
  if (S3.test(local)) return { ...base, nivel: 'forte', sinais: ['S3'], motivo: null };
  if (S8_VALOR.test(a) && S8_VENC.test(aLower)) return { ...base, nivel: 'forte', sinais: ['S8'], motivo: null };

  const fracos: string[] = [];
  if (temSubstantivo) fracos.push('S6');
  if (S3F.test(local)) fracos.push('S3f');
  if (rotulos.some((r) => S7.test(r))) fracos.push('S7');
  if (fracos.length > 0) return { ...base, nivel: 'fraco', sinais: fracos, motivo: null };

  return { ...base, nivel: 'nao', sinais: [], motivo: 'sem sinal' };
}
```

- [ ] **Step 5: Rodar até passar** — `npx jest src/financas/parser/finance-email-detector.spec.ts`. Se algum caso da amostra falhar, ajuste a **regex** citando a spec — nunca a fixture. Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add backend/src/financas/parser/finance-email-detector.ts backend/src/financas/parser/finance-email-detector.spec.ts backend/src/financas/parser/__fixtures__/amostra-real-2026-09.json
git commit -m "feat(financas): triagem genérica de e-mails de cobrança (forte/fraco, vetos duros e brandos)

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Extratores (valor, data, código de barras)

**Files:**
- Create: `backend/src/financas/parser/finance-extractors.ts`, `backend/src/financas/parser/finance-extractors.spec.ts`

**Interfaces:**
- Consumes: `wb` (Task 2).
- Produces:
  - `extrairValor(texto: string): { valor: number | null; anchored: boolean; ancoraCobranca: boolean }` — `ancoraCobranca` = âncora pertence a `ANCORAS_VALOR_COBRANCA` (E1).
  - `extrairDataVencimento(texto: string, recebidoEm: Date): { data: Date | null; anchored: boolean }`
  - `extrairCodigoBarras(texto: string): string | null`
  - `inferirAno(dia: number, mes: number, recebidoEm: Date): Date | null` (ano de `recebidoEm` ±1 que minimiza `|data − recebidoEm|`; `null` se data inválida)
  - `proximoDia(dia: number, recebidoEm: Date): Date | null` (próxima ocorrência ≤ 45 dias; `null` fora de 1–31 ou > 45 dias)
  - `DATE_ANCHORS: RegExp[]`, `ANCORAS_VALOR_COBRANCA: RegExp[]`, `ANCORAS_VALOR_EXTRACAO: RegExp[]`

- [ ] **Step 1: Testes**

```ts
import { extrairCodigoBarras, extrairDataVencimento, extrairValor, inferirAno, proximoDia } from './finance-extractors';

const rec = (iso: string) => new Date(iso);
const utc = (y: number, m: number, d: number) => new Date(Date.UTC(y, m - 1, d));

describe('extrairValor', () => {
  it('reads an anchored value without R$ (Leroy)', () => {
    expect(extrairValor('Vencimento: ..... 17/09\nValor total: ........ 520,61\nOPÇÃO 1: Pague em até 12 vezes de R$ 86,33')).toEqual({ valor: 520.61, anchored: true, ancoraCobranca: false });
  });
  it('reads "no valor de" (Santander) as extraction anchor, not cobrança anchor', () => {
    expect(extrairValor('está fechada no valor de R$ 111,46, com vencimento para o dia 10/08/2026.\n06 Parcelas de R$ 25,39')).toEqual({ valor: 111.46, anchored: true, ancoraCobranca: false });
  });
  it('flags a cobrança anchor', () => {
    expect(extrairValor('Valor a pagar: R$ 129,90')).toEqual({ valor: 129.9, anchored: true, ancoraCobranca: true });
  });
  it('keeps existing behaviour for collapsed table rows (mínimo before total on one line)', () => {
    expect(extrairValor('Pagamento mínimo R$ 123,45 Total da fatura R$ 1.234,56').valor).toBe(1234.56);
    expect(extrairValor('Valor a pagar após o vencimento R$ 1.500,00 Valor a pagar até o vencimento R$ 1.234,56').valor).toBe(1234.56);
  });
  it('never takes a value from an installment segment or line', () => {
    expect(extrairValor('Valor total:\nOPÇÃO 1: Pague em até 12 vezes de R$ 86,33').valor).toBeNull();
    expect(extrairValor('Total da fatura: 12x de R$ 100,00').valor).toBeNull();
  });
  it('next-line fallback works for label/value split, but not into another anchor', () => {
    expect(extrairValor('Valor total\nR$ 300,00').valor).toBe(300);
    expect(extrairValor('Valor total\nValor mínimo R$ 50,00').valor).toBeNull();
  });
  it('Subtotal: does not match total:', () => {
    expect(extrairValor('Subtotal: R$ 120,00\nFrete: R$ 10,00').anchored).toBe(false);
  });
  it('unanchored fallback still needs R$ and a single occurrence', () => {
    expect(extrairValor('Você pagou R$ 50,00')).toEqual({ valor: 50, anchored: false, ancoraCobranca: false });
    expect(extrairValor('R$ 50,00 e R$ 60,00').valor).toBeNull();
    expect(extrairValor('juros de 2,99% e taxa 14,30').valor).toBeNull();
  });
  it('zero becomes null', () => {
    expect(extrairValor('Total da fatura atual: R$ 0,00').valor).toBeNull();
  });
});

describe('inferirAno / proximoDia', () => {
  it('picks the year nearest to recebidoEm', () => {
    expect(inferirAno(10, 1, rec('2026-12-28T00:00:00Z'))).toEqual(utc(2027, 1, 10));
    expect(inferirAno(28, 12, rec('2027-01-05T00:00:00Z'))).toEqual(utc(2026, 12, 28));
    expect(inferirAno(15, 9, rec('2026-09-08T00:00:00Z'))).toEqual(utc(2026, 9, 15));
  });
  it('rejects invalid dates instead of rolling them', () => {
    expect(inferirAno(31, 2, rec('2026-02-01T00:00:00Z'))).toBeNull();
  });
  it('proximoDia: next occurrence within 45 days, else null', () => {
    expect(proximoDia(10, rec('2026-09-01T00:00:00Z'))).toEqual(utc(2026, 9, 10));
    expect(proximoDia(5, rec('2026-09-20T00:00:00Z'))).toEqual(utc(2026, 10, 5));
    expect(proximoDia(40, rec('2026-09-01T00:00:00Z'))).toBeNull();
    expect(proximoDia(0, rec('2026-09-01T00:00:00Z'))).toBeNull();
  });
});

describe('extrairDataVencimento', () => {
  const r = rec('2026-09-08T04:37:16Z');
  it('reads "vence no dia 15 de setembro" without a year', () => {
    expect(extrairDataVencimento('Sua fatura já está fechada, vence no dia 15 de setembro e você pode conferir', r)).toEqual({ data: utc(2026, 9, 15), anchored: true });
  });
  it('reads "Vencimento: 17/09" without a year', () => {
    expect(extrairDataVencimento('Vencimento: ..................... 17/09\nValor total: 520,61', rec('2026-09-15T12:04:12Z'))).toEqual({ data: utc(2026, 9, 17), anchored: true });
  });
  it('reads day-only "vence dia 10"', () => {
    expect(extrairDataVencimento('A mensalidade vence dia 10 — valor R$ 1.200,00', rec('2026-09-01T00:00:00Z'))).toEqual({ data: utc(2026, 9, 10), anchored: true });
    expect(extrairDataVencimento('vence dia 40', rec('2026-09-01T00:00:00Z'))).toEqual({ data: null, anchored: false });
  });
  it('prefers the full-date format when a year is present', () => {
    expect(extrairDataVencimento('Vencimento: 10/10/2025', rec('2026-09-01T00:00:00Z'))).toEqual({ data: utc(2025, 10, 10), anchored: true });
  });
  it('keeps the existing anchored formats (dd/mm/yyyy after "vencimento", next-line split)', () => {
    expect(extrairDataVencimento('Fechamento 28/09/2026 Vencimento 10/10/2026', r).data).toEqual(utc(2026, 10, 10));
    expect(extrairDataVencimento('Vencimento\n10/10/2026', r).data).toEqual(utc(2026, 10, 10));
  });
  it('dd/mm without year is NOT read from the whole-body fallback', () => {
    expect(extrairDataVencimento('Parcela 3/12 do seu curso', r)).toEqual({ data: null, anchored: false });
  });
  it('whole-body fallback still reads a full date, unanchored', () => {
    expect(extrairDataVencimento('Campanha válida até 31/12/2026', r)).toEqual({ data: utc(2026, 12, 31), anchored: false });
  });
});

describe('extrairCodigoBarras', () => {
  it('reads 47 and 48 digit lines', () => {
    expect(extrairCodigoBarras('x\n34191.79001 01043.510047 91020.150008 1 84410000012345\ny')).toBe('34191.79001 01043.510047 91020.150008 1 84410000012345');
    expect(extrairCodigoBarras('82660000001-2 23400012345-6 78900001234-5 60000000000-1')).toBe('82660000001-2 23400012345-6 78900001234-5 60000000000-1');
    expect(extrairCodigoBarras('nada')).toBeNull();
  });
});
```

- [ ] **Step 2: Rodar e ver falhar.**

- [ ] **Step 3: Implementar** — `finance-extractors.ts`:

```ts
import { wb } from '../../common/text-match.util';

// ---------- Valor ----------
/** Âncoras de COBRANÇA: provam que o número é um valor devido (evidência E1). */
export const ANCORAS_VALOR_COBRANCA: RegExp[] = [
  wb('\\bvalor a pagar\\b'), wb('\\btotal a pagar\\b'), wb('\\btotal da fatura\\b'), wb('\\bvalor da fatura\\b'),
  wb('\\bvalor do boleto\\b'), wb('\\bvalor da conta\\b'), wb('\\btotal da conta\\b'),
];
/** Âncoras só de EXTRAÇÃO: localizam o número, mas não provam cobrança ("Pix … no valor de"). */
export const ANCORAS_VALOR_EXTRACAO: RegExp[] = [
  wb('\\bvalor total\\b'), wb('\\bno valor de\\b'), wb('\\bvalor:'), wb('\\btotal:'),
];
const TODAS_ANCORAS_VALOR = [...ANCORAS_VALOR_COBRANCA, ...ANCORAS_VALOR_EXTRACAO];

const MOEDA_NUM = String.raw`((?:\d{1,3}(?:\.\d{3})*|\d+),\d{2})`;
/** Com prefixo R$ obrigatório (fallback não ancorado). */
const MOEDA_RS_RE = new RegExp(String.raw`R\$\s*${MOEDA_NUM}`);
const MOEDA_RS_G = new RegExp(String.raw`R\$\s*${MOEDA_NUM}`, 'g');
/** Prefixo R$ opcional — SÓ para texto ancorado. Exige que não venha colado a dígito/%. */
const MOEDA_OPCIONAL_RE = new RegExp(String.raw`(?:R\$\s*)?(?<![\d,.])${MOEDA_NUM}(?![\d%])`);
const PARCELAMENTO_RE = /\d+\s*(x|vezes)\s+de|parcelas?\s+de|m[ií]nimo/i;
const APOS_MINIMO_INICIO_RE = /^\s*(ap[óo]s|m[ií]nimo)\b/i;

function parseBr(raw: string): number {
  return parseFloat(raw.replace(/\./g, '').replace(',', '.'));
}
function zeroParaNull(v: number): number | null {
  return v > 0 ? v : null;
}

export function extrairValor(texto: string): { valor: number | null; anchored: boolean; ancoraCobranca: boolean } {
  const linhas = texto.split(/\r?\n/);
  for (const ancora of TODAS_ANCORAS_VALOR) {
    const ehCobranca = ANCORAS_VALOR_COBRANCA.includes(ancora);
    const global = new RegExp(ancora.source, ancora.flags.includes('g') ? ancora.flags : `${ancora.flags}g`);
    for (let i = 0; i < linhas.length; i++) {
      const linha = linhas[i];
      const matches = [...linha.matchAll(global)];
      if (matches.length === 0) continue;
      for (const m of matches) {
        const depois = linha.slice((m.index ?? 0) + m[0].length);
        if (APOS_MINIMO_INICIO_RE.test(depois)) continue;
        // Segmento até a primeira moeda: se houver parcelamento antes dela, o número é parcela.
        const primeiraMoeda = depois.match(MOEDA_OPCIONAL_RE);
        if (!primeiraMoeda || primeiraMoeda.index === undefined) continue;
        if (PARCELAMENTO_RE.test(depois.slice(0, primeiraMoeda.index + primeiraMoeda[0].length))) continue;
        return { valor: zeroParaNull(parseBr(primeiraMoeda[1])), anchored: true, ancoraCobranca: ehCobranca };
      }
      // Rótulo numa linha, valor na seguinte (HTML <div>label</div><div>valor</div>).
      const proxima = linhas[i + 1];
      if (proxima !== undefined && proxima.trim() !== '' && !PARCELAMENTO_RE.test(proxima)
        && !TODAS_ANCORAS_VALOR.some((a) => a.test(proxima))) {
        const m2 = proxima.match(MOEDA_OPCIONAL_RE);
        if (m2) return { valor: zeroParaNull(parseBr(m2[1])), anchored: true, ancoraCobranca: ehCobranca };
      }
    }
  }
  const todas = [...texto.matchAll(MOEDA_RS_G)];
  if (todas.length === 1) return { valor: zeroParaNull(parseBr(todas[0][1])), anchored: false, ancoraCobranca: false };
  return { valor: null, anchored: false, ancoraCobranca: false };
}

// ---------- Data ----------
/** Lista única, usada pela extração e pela evidência E2. A forma "vence em/no dia/dia" vira conector
 *  lido logo após a âncora. */
export const DATE_ANCHORS: RegExp[] = [
  wb('\\bdata de vencimento\\b'), wb('\\bvencimento\\b'), wb('\\bvence\\b'), wb('\\bpague at[ée]\\b'), wb('\\bpagar at[ée]\\b'),
];
const CONECTOR_RE = /^\s*(?:[:.\-–—]+\s*|(?:em|no dia|dia|para o dia)\s+)?\s*/i;
const MESES = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'];
const DATA_COMPLETA_RE = /(\d{1,2})\/(\d{1,2})\/(\d{4}|\d{2})/;
const DATA_ISO_RE = /(\d{4})-(\d{2})-(\d{2})/;
const DATA_EXTENSO_RE = new RegExp(String.raw`(\d{1,2})\s+de\s+(${MESES.join('|')})(?:\s+de\s+(\d{4}))?`, 'i');
const DATA_DDMM_RE = /(\d{1,2})\/(\d{1,2})(?![/\d])/;
const SO_DIA_RE = /^(\d{1,2})\b(?!\s*(?:\/|de\s))/;

function dataValida(y: number, m: number, d: number): Date | null {
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  const dt = new Date(Date.UTC(y, m - 1, d));
  return dt.getUTCMonth() === m - 1 && dt.getUTCDate() === d ? dt : null;
}

export function inferirAno(dia: number, mes: number, recebidoEm: Date): Date | null {
  const base = recebidoEm.getUTCFullYear();
  const candidatos = [base - 1, base, base + 1]
    .map((y) => dataValida(y, mes, dia))
    .filter((d): d is Date => d !== null);
  if (candidatos.length === 0) return null;
  return candidatos.reduce((melhor, d) =>
    Math.abs(d.getTime() - recebidoEm.getTime()) < Math.abs(melhor.getTime() - recebidoEm.getTime()) ? d : melhor);
}

export function proximoDia(dia: number, recebidoEm: Date): Date | null {
  if (dia < 1 || dia > 31) return null;
  const y = recebidoEm.getUTCFullYear(), m = recebidoEm.getUTCMonth() + 1;
  for (const [yy, mm] of [[y, m], m === 12 ? [y + 1, 1] : [y, m + 1]]) {
    const d = dataValida(yy, mm, dia);
    if (d && d.getTime() >= Date.UTC(y, m - 1, recebidoEm.getUTCDate())) {
      const dias = (d.getTime() - recebidoEm.getTime()) / 86_400_000;
      return dias <= 45 ? d : null;
    }
  }
  return null;
}

/** Formatos COMPLETOS (com ano) — permitidos em qualquer lugar. */
function dataCompleta(texto: string): Date | null {
  const n = texto.match(DATA_COMPLETA_RE);
  if (n) { const yyyy = n[3].length === 2 ? 2000 + Number(n[3]) : Number(n[3]); return dataValida(yyyy, Number(n[2]), Number(n[1])); }
  const iso = texto.match(DATA_ISO_RE);
  if (iso) return dataValida(Number(iso[1]), Number(iso[2]), Number(iso[3]));
  const ext = texto.match(DATA_EXTENSO_RE);
  if (ext && ext[3]) return dataValida(Number(ext[3]), MESES.indexOf(ext[2].toLowerCase()) + 1, Number(ext[1]));
  return null;
}
/** Formatos SEM ano — só depois de uma âncora. Ordem: completo > dd/mm > "dd de mês" > só dia. */
function dataAposAncora(depois: string, recebidoEm: Date): Date | null {
  const semConector = depois.replace(CONECTOR_RE, '');
  const completa = dataCompleta(semConector);
  if (completa) return completa;
  const ddmm = semConector.match(DATA_DDMM_RE);
  if (ddmm && semConector.indexOf(ddmm[0]) < 40) return inferirAno(Number(ddmm[1]), Number(ddmm[2]), recebidoEm);
  const ext = semConector.match(DATA_EXTENSO_RE);
  if (ext) return inferirAno(Number(ext[1]), MESES.indexOf(ext[2].toLowerCase()) + 1, recebidoEm);
  const soDia = semConector.match(SO_DIA_RE);
  if (soDia) return proximoDia(Number(soDia[1]), recebidoEm);
  return null;
}

export function extrairDataVencimento(texto: string, recebidoEm: Date): { data: Date | null; anchored: boolean } {
  const linhas = texto.split(/\r?\n/);
  for (const ancora of DATE_ANCHORS) {
    for (let i = 0; i < linhas.length; i++) {
      const m = linhas[i].match(ancora);
      if (!m || m.index === undefined) continue;
      const depois = linhas[i].slice(m.index + m[0].length);
      const d = dataAposAncora(depois, recebidoEm);
      if (d) return { data: d, anchored: true };
      const proxima = linhas[i + 1];
      if (proxima !== undefined && depois.trim() === '') {
        const d2 = dataAposAncora(proxima, recebidoEm);
        if (d2) return { data: d2, anchored: true };
      }
    }
  }
  const fallback = dataCompleta(texto);
  return fallback ? { data: fallback, anchored: false } : { data: null, anchored: false };
}

// ---------- Código de barras ----------
const BOLETO_47_RE = /^\d{5}\.\d{5}\s\d{5}\.\d{6}\s\d{5}\.\d{6}\s\d\s\d{14}$/m;
const CONCESSIONARIA_48_RE = /^\d{11}-\d\s\d{11}-\d\s\d{11}-\d\s\d{11}-\d$/m;
export function extrairCodigoBarras(texto: string): string | null {
  return texto.match(BOLETO_47_RE)?.[0] ?? texto.match(CONCESSIONARIA_48_RE)?.[0] ?? null;
}
```

- [ ] **Step 4: Rodar até passar.** Casos que costumam exigir ajuste fino: `MOEDA_OPCIONAL_RE` em "juros de 2,99%" (lookahead `(?![\d%])` cobre); "Vencimento: ..... 17/09" (o `CONECTOR_RE` consome `: .....`? — não: consome só `:` e espaços; a `DATA_DDMM_RE` é procurada no restante, com `indexOf < 40` para não pegar data distante). Ajuste a regex, não o teste.

- [ ] **Step 5: Commit**

```bash
git add backend/src/financas/parser/finance-extractors.ts backend/src/financas/parser/finance-extractors.spec.ts
git commit -m "feat(financas): extratores de valor/data com R$ opcional ancorado, data sem ano e sem parcelamento

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Evidência de cobrança E1–E6 e evidência negativa

**Files:**
- Create: `backend/src/financas/parser/finance-evidence.ts`, `backend/src/financas/parser/finance-evidence.spec.ts`

**Interfaces:**
- Consumes: `extrairValor`, `extrairDataVencimento`, `extrairCodigoBarras` (Task 5); `wb`, `normalizar` (Task 2); `isSettledPaymentSubject`.
- Produces:
  - `interface AnexoMeta { filename: string; mimeType: string; size: number; attachmentId: string }`
  - `type Evidencia = 'E1' | 'E2' | 'E3' | 'E4' | 'E5' | 'E6'`
  - `CABECA_EVIDENCIA = 1500`
  - `evidenciasDeCobranca(texto: string, anexos: AnexoMeta[], recebidoEm: Date): Set<Evidencia>`
  - `evidenciaSuficiente(ev: Set<Evidencia>, assuntoTemSubstantivoCobranca: boolean): boolean`
  - `temEvidenciaNegativa(texto: string, assunto: string): boolean`

- [ ] **Step 1: Testes**

```ts
import { evidenciasDeCobranca, evidenciaSuficiente, temEvidenciaNegativa } from './finance-evidence';

const r = new Date('2026-09-01T00:00:00Z');
const ev = (texto: string, anexos: { filename: string }[] = []) =>
  evidenciasDeCobranca(texto, anexos.map((a) => ({ ...a, mimeType: 'application/pdf', size: 1, attachmentId: 'x' })), r);

describe('evidenciasDeCobranca', () => {
  it('E1 only with a cobrança anchor and value > 0', () => {
    expect(ev('Valor a pagar: R$ 129,90')).toEqual(new Set(['E1']));
    expect(ev('Você recebeu um Pix no valor de R$ 500,00')).toEqual(new Set());
    expect(ev('Valor: R$ 500,00')).toEqual(new Set());
    expect(ev('Total da fatura atual: R$ 0,00')).toEqual(new Set());
  });
  it('E2 with DATE_ANCHORS, including day-only', () => {
    expect(ev('A mensalidade vence dia 10 — valor R$ 1.200,00')).toEqual(new Set(['E2']));
    expect(ev('Vencimento da apólice 15/10/2026')).toEqual(new Set(['E2']));
    expect(ev('vencimento em breve')).toEqual(new Set());
  });
  it('E3 barcode, E4 pix + currency same/next line, E5 attached phrase, E6 attachment name', () => {
    expect(ev('34191.79001 01043.510047 91020.150008 1 84410000012345')).toEqual(new Set(['E3']));
    expect(ev('Pix copia e cola\nR$ 89,90')).toEqual(new Set(['E4']));
    expect(ev('Pix copia e cola\n\n\nR$ 89,90')).toEqual(new Set());
    expect(ev('Sua fatura da Starlink está anexada')).toEqual(new Set(['E5']));
    expect(ev('Olá', [{ filename: 'Fatura_082026.PDF' }])).toEqual(new Set(['E6']));
  });
  it('ignores text past CABECA_EVIDENCIA', () => {
    expect(ev(`${'x'.repeat(1500)} Valor a pagar: R$ 10,00`)).toEqual(new Set());
  });
});

describe('evidenciaSuficiente', () => {
  it('E1/E3/E4/E5/E6 alone suffice; E2 alone only with a cobrança noun in the subject', () => {
    expect(evidenciaSuficiente(new Set(['E1']), false)).toBe(true);
    expect(evidenciaSuficiente(new Set(['E6']), false)).toBe(true);
    expect(evidenciaSuficiente(new Set(['E2']), true)).toBe(true);
    expect(evidenciaSuficiente(new Set(['E2']), false)).toBe(false);
    expect(evidenciaSuficiente(new Set(), true)).toBe(false);
  });
});

describe('temEvidenciaNegativa', () => {
  it.each([
    ['Recebemos seu pagamento. Obrigado!', ''],
    ['Pesquisa de satisfação: avalie seu atendimento', ''],
    ['Você recebeu um Pix de Fulano no valor de R$ 500,00', ''],
    ['Sua compra no valor de R$ 89,90 foi aprovada', ''],
    ['Depósito recebido', ''],
    ['Estorno realizado', ''],
    ['Olá\n\nO pagamento de boleto foi agendado', ''],
    ['Olá', 'Você recebeu um Pix de Fulano'],
  ])('"%s" / assunto "%s" → true', (texto, assunto) => {
    expect(temEvidenciaNegativa(texto, assunto)).toBe(true);
  });
  it('only looks at the first 3 non-empty lines', () => {
    expect(temEvidenciaNegativa('a\nb\nc\nRecebemos seu pagamento', '')).toBe(false);
  });
  it('a pending invoice is not negative', () => {
    expect(temEvidenciaNegativa('Sua fatura já está fechada, vence no dia 15 de setembro', 'A fatura do seu cartão está fechada')).toBe(false);
  });
});
```

- [ ] **Step 2: Rodar e ver falhar.**

- [ ] **Step 3: Implementar**

```ts
import { normalizar, wb } from '../../common/text-match.util';
import { extrairCodigoBarras, extrairDataVencimento, extrairValor } from './finance-extractors';
import { isSettledPaymentSubject } from './invoice-subject-patterns';

export interface AnexoMeta { filename: string; mimeType: string; size: number; attachmentId: string }
export type Evidencia = 'E1' | 'E2' | 'E3' | 'E4' | 'E5' | 'E6';
export const CABECA_EVIDENCIA = 1500;

const PIX_RE = wb('\\bpix copia e cola\\b|\\bchave pix\\b');
const MOEDA_RE = /R\$\s?(\d{1,3}(\.\d{3})*|\d+),\d{2}/;
const E5_RE = wb('\\bsua (fatura|conta)\\b.{0,30}\\b(est[áa]|segue) (anexa|anexada|em anexo)\\b');
const E6_RE = /fatura|invoice|boleto|cobranca/i;

export function evidenciasDeCobranca(texto: string, anexos: AnexoMeta[], recebidoEm: Date): Set<Evidencia> {
  const cabeca = normalizar(texto).slice(0, CABECA_EVIDENCIA);
  const ev = new Set<Evidencia>();
  const valor = extrairValor(cabeca);
  if (valor.valor !== null && valor.anchored && valor.ancoraCobranca) ev.add('E1');
  const data = extrairDataVencimento(cabeca, recebidoEm);
  if (data.data !== null && data.anchored) ev.add('E2');
  if (extrairCodigoBarras(cabeca) !== null) ev.add('E3');
  const linhas = cabeca.split(/\r?\n/);
  for (let i = 0; i < linhas.length; i++) {
    if (PIX_RE.test(linhas[i]) && (MOEDA_RE.test(linhas[i]) || MOEDA_RE.test(linhas[i + 1] ?? ''))) { ev.add('E4'); break; }
  }
  if (E5_RE.test(cabeca)) ev.add('E5');
  if (anexos.some((a) => E6_RE.test(a.filename))) ev.add('E6');
  return ev;
}

export function evidenciaSuficiente(ev: Set<Evidencia>, assuntoTemSubstantivoCobranca: boolean): boolean {
  if (['E1', 'E3', 'E4', 'E5', 'E6'].some((e) => ev.has(e as Evidencia))) return true;
  return ev.has('E2') && assuntoTemSubstantivoCobranca;
}

const NEGATIVAS: RegExp[] = [
  wb('\\b(pesquisa de satisfa[çc][ãa]o|avalie (seu|nosso|o) atendimento)\\b'),
  wb('\\brecebeu (um|uma) (pix|transfer[êe]ncia|dep[óo]sito)\\b'),
  wb('\\b(pix|transfer[êe]ncia|dep[óo]sito|compra|rendimento|pagamento|estorno) .{0,25}(recebid|aprovad|realizad|agendad|efetuad|conclu[ií]d)'),
  wb('\\bestorno\\b'),
];

/** Nas 3 primeiras linhas não vazias do texto OU no assunto. Exceto com marcador (decidido pelo chamador). */
export function temEvidenciaNegativa(texto: string, assunto: string): boolean {
  const cabeca = normalizar(texto).split(/\r?\n/).map((l) => l.trim()).filter(Boolean).slice(0, 3).join('\n');
  const alvo = `${normalizar(assunto)}\n${cabeca}`;
  if (cabeca.split('\n').some((l) => isSettledPaymentSubject(l))) return true;
  return NEGATIVAS.some((re) => re.test(alvo));
}
```

- [ ] **Step 4: Rodar até passar; commit**

```bash
git add backend/src/financas/parser/finance-evidence.ts backend/src/financas/parser/finance-evidence.spec.ts
git commit -m "feat(financas): evidência de cobrança E1–E6 e evidência negativa para candidatos fracos

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: `parse()` orientado a triagem + fixtures reais

**Files:**
- Modify: `backend/src/financas/parser/email-finance-regex-parser.service.ts` (reescrita; remove `matches`, `processEmail`, `INSTITUTION_MAP`, extratores privados)
- Modify: `backend/src/financas/parser/email-finance-regex-parser.service.spec.ts`
- Create fixtures em `__fixtures__/`: `nubank-fatura-fechada-real.txt`, `santander-fatura-por-email.txt`, `leroy-pefisa-celebre.txt`, `leroy-pefisa-celebre-minificado.txt`, `starlink-fatura.txt`, `porto-consorcio.txt`, `pefisa-em-atraso.txt`, `neoenergia-escolha-conta-luz.txt`, `pagamento-recebido.txt`, `adversarial-corpo/{pix-recebido,compra-aprovada,transferencia-realizada,rendimento-caixinha,cartao-entregue,resumo-compras,informativo-limite-zero}.txt`, `instituicao-desconhecida/{banco-alfa,coop-beta,fintech-gama}.txt`
- Modify: `backend/src/email-classification/heuristic-email-classifier.service.ts` — **não muda** (usa só `invoice-subject-patterns`).

**Interfaces:**
- Consumes: Tasks 3–6.
- Produces:
  - `FINANCE_PARSER_VERSION = 2`, `CABECA_TIPO = 600`
  - `interface ParsedLancamento { tipo: 'DESPESA' | 'FATURA_CARTAO'; descricao: string; instituicao: string; valor: number | null; dataVencimento: Date; dataEncontrada: boolean; codigoBarras: string | null }`
  - `parse(params: { remetente: string; assunto: string; corpo: string; recebidoEm: Date; triagem: ResultadoTriagem; anexos: AnexoMeta[] }): ParsedLancamento | null`
  - `complementarComTexto(parsed: ParsedLancamento, texto: string | null, recebidoEm: Date): ParsedLancamento`
  - `EmailFinanceRegexParserService` deixa de depender de `PrismaService` (construtor vazio).

- [ ] **Step 1: Criar fixtures reais** (texto legível; mascarar nome/CPF). Conteúdos mínimos fiéis:

`nubank-fatura-fechada-real.txt`:
```
Sua fatura foi fechada
Você pode pagar usando a sua conta do Nubank ou gerando um boleto diretamente no app.
Olá, Fulano Sua fatura já está fechada, vence no dia 15 de setembro e você pode conferir todos os detalhes no PDF anexo aqui no e-mail. Pagar sua fatura é bem simples e você pode fazer isso direto no aplicativo usando o saldo da sua conta do Nubank ou gerando um boleto.
Como pagar sua fatura
Importante: não esqueça de fazer o pagamento da sua fatura até a data de vencimento que é dia 15 de setembro.
```
`santander-fatura-por-email.txt`:
```
Sua fatura chegou!
FULANO,
A fatura mensal do seu cartão SANTANDER ELITE MASTERCARD, final 9636, está fechada no valor de R$ 111,46, com vencimento para o dia 10/08/2026. A partir de hoje, todas as compras realizadas com o seu cartão serão lançadas na próxima fatura.
Conheça algumas opções: 06 Parcelas de R$ 25,39 12 Parcelas de R$ 17,31
```
`leroy-pefisa-celebre.txt`:
```
Existem muitas opções para pagar. Escolha a melhor pra você!
Olá, Fulano.
A fatura do seu Cartão Celebre! Elo chegou!
Veja o resumo abaixo e confira o detalhamento da sua fatura no anexo.
Vencimento: ..................... 17/09
Valor total: ........................ 520,61
OPÇÃO 1: Pague em até 12 vezes de R$ 86,33
OPÇÃO 2: Pague em até 9 vezes de R$ 105,06
```
`leroy-pefisa-celebre-minificado.txt` — igual, mas **sem** linha vazia e com "Vencimento: ..................... 17/09 Valor total: ........................ 520,61" na mesma linha seguida da linha de opções.
`starlink-fatura.txt`:
```
INV-DF-BRA-21240238 Notificação de fatura
Agradecemos por fazer seu pedido da Starlink. Sua fatura está anexada.
Número da conta ACC-8647295 Número da fatura INV-DF-BRA-21240238
```
`porto-consorcio.txt`:
```
Porto Bank: O informativo do seu Consórcio está disponível!
Olá FULANO, Chegou o informativo do seu Consórcio Porto Bank, cota 0010 grupo AF272, no valor de R$ 1.345,51, com vencimento em 20/09/2026.
```
`pefisa-em-atraso.txt`:
```
Na Pefisa você tem diversas opções de pagamento.
Sr(a), FULANO, Ainda não identificamos o pagamento de sua fatura com vencimento em 17/07/2026, no valor de R$ 522,88. Regularize de forma simples.
```
`neoenergia-escolha-conta-luz.txt`:
```
Facilite seu dia a dia com a fatura digital
Olá! Você pode receber sua conta de energia de forma digital e escolher o canal que funciona melhor para você.
Com a Fatura Digital, sua conta pode ser enviada por e-mail ou WhatsApp.
```
`pagamento-recebido.txt`:
```
Recebemos seu pagamento
Olá! Confirmamos o pagamento da sua fatura de setembro no valor de R$ 1.234,56.
Vencimento da próxima fatura: 10/10/2026
```
`adversarial-corpo/pix-recebido.txt`: `Você recebeu um Pix de Fulano no valor de R$ 500,00\nO dinheiro já está na sua conta.`
`adversarial-corpo/compra-aprovada.txt`: `Compra aprovada\nSua compra no valor de R$ 89,90 foi aprovada em LOJA X.`
`adversarial-corpo/transferencia-realizada.txt`: `Transferência realizada\nValor: R$ 300,00\nPara: Fulano`
`adversarial-corpo/rendimento-caixinha.txt`: `Rendimento da caixinha\nValor total: R$ 5.012,34\nSeu dinheiro rendeu R$ 12,34 este mês.`
`adversarial-corpo/cartao-entregue.txt`: `Seu cartão foi entregue\nValidade 12/30\nAtive no app.`
`adversarial-corpo/resumo-compras.txt`: `Resumo das suas compras\nSubtotal: R$ 120,00\nFrete: R$ 10,00`
`adversarial-corpo/informativo-limite-zero.txt`: `Informativo de limite\nTotal da fatura atual: R$ 0,00\nVencimento: dia 10`
`instituicao-desconhecida/banco-alfa.txt`: `Sua fatura Alfa Visa fechou\nConfira no app.`
`instituicao-desconhecida/coop-beta.txt`: `Boleto da mensalidade de outubro\n34191.79001 01043.510047 91020.150008 1 84410000012345\nValor do boleto: R$ 250,00`
`instituicao-desconhecida/fintech-gama.txt`: `Vencimento amanhã\nValor a pagar: R$ 89,90\nPague pelo app.`

- [ ] **Step 2: Reescrever o spec do parser** — substituir `email-finance-regex-parser.service.spec.ts` por:

```ts
import { readFileSync } from 'fs';
import { join } from 'path';
import { EmailFinanceRegexParserService, FINANCE_PARSER_VERSION } from './email-finance-regex-parser.service';
import { triagem } from './finance-email-detector';
import type { AnexoMeta } from './finance-evidence';

const fx = (name: string) => readFileSync(join(__dirname, '__fixtures__', name), 'utf-8');
const utc = (y: number, m: number, d: number) => new Date(Date.UTC(y, m - 1, d));
const pdf = (filename: string): AnexoMeta => ({ filename, mimeType: 'application/pdf', size: 1000, attachmentId: 'a1' });

describe('EmailFinanceRegexParserService.parse', () => {
  const service = new EmailFinanceRegexParserService();
  const parse = (remetente: string, assunto: string, corpo: string, recebidoEm: Date, anexos: AnexoMeta[] = [], marcado = false) =>
    service.parse({ remetente, assunto, corpo, recebidoEm, triagem: triagem(remetente, assunto, { marcado }), anexos });

  it('exports the parser version', () => expect(FINANCE_PARSER_VERSION).toBe(2));

  describe('e-mails reais', () => {
    it('Nubank fatura fechada: forte, valor null, data inferida do "15 de setembro"', () => {
      const r = parse('Nubank <todomundo@nubank.com.br>', 'A fatura do seu cartão Nubank está fechada', fx('nubank-fatura-fechada-real.txt'), new Date('2026-09-08T04:37:16Z'), [pdf('Nubank_2026-09-15.pdf')]);
      expect(r).toMatchObject({ tipo: 'FATURA_CARTAO', instituicao: 'Nubank', valor: null, dataVencimento: utc(2026, 9, 15), dataEncontrada: true, codigoBarras: null });
    });
    it('Santander: cartão no corpo → FATURA_CARTAO, "no valor de" extrai 111,46', () => {
      const r = parse('Santander <faturaporemail@santander.com.br>', 'Fatura por e-mail - Agosto/2026', fx('santander-fatura-por-email.txt'), new Date('2026-08-04T21:30:05Z'));
      expect(r).toMatchObject({ tipo: 'FATURA_CARTAO', instituicao: 'Santander', valor: 111.46, dataVencimento: utc(2026, 8, 10) });
    });
    it.each(['leroy-pefisa-celebre.txt', 'leroy-pefisa-celebre-minificado.txt'])('Leroy/Pefisa (%s): 520,61 e 17/09, nunca a parcela', (f) => {
      const r = parse('Leroy Merlin Pay <noreply@leroymerlinpay.pefisa.com.br>', 'A fatura do seu Cartão Celebre! Elo chegou!', fx(f), new Date('2026-09-15T12:04:12Z'));
      expect(r).toMatchObject({ tipo: 'FATURA_CARTAO', instituicao: 'Pefisa', valor: 520.61, dataVencimento: utc(2026, 9, 17) });
      expect(r?.valor).not.toBe(86.33);
    });
    it('Starlink: fraco aceito por E5/E6', () => {
      const r = parse('Starlink <no-reply@starlink.com>', 'Fatura da Starlink', fx('starlink-fatura.txt'), new Date('2026-08-27T01:31:34Z'), [pdf('fatura-starlink.pdf')]);
      expect(r).toMatchObject({ tipo: 'DESPESA', instituicao: 'Starlink', valor: null });
    });
    it('Porto: forte por S3, valor e vencimento do corpo', () => {
      const r = parse('Porto Consórcio <portoconsorcio@portoseguro.com.br>', 'Informativo Consórcio Porto Bank', fx('porto-consorcio.txt'), new Date('2026-09-15T01:04:36Z'));
      expect(r).toMatchObject({ tipo: 'DESPESA', valor: 1345.51, dataVencimento: utc(2026, 9, 20) });
    });
    it('Pefisa em atraso: fraco aceito por E2 (assunto tem "fatura")', () => {
      const r = parse('Pefisa <pagamento@pefisa.com.br>', 'Sua Fatura CELEBRE! ELO MAIS', fx('pefisa-em-atraso.txt'), new Date('2026-07-24T11:13:35Z'));
      expect(r).toMatchObject({ valor: 522.88, dataVencimento: utc(2026, 7, 17) });
    });
    it('Neoenergia "escolha como receber": veto na triagem → null', () => {
      expect(parse('Neoenergia <cliente@neoenergiabrasilia.com.br>', 'Escolha como receber sua conta de luz', fx('neoenergia-escolha-conta-luz.txt'), new Date())).toBeNull();
    });
    it('pagamento recebido no corpo derruba um forte; marcador ignora a negativa', () => {
      const rem = 'Nubank <todomundo@nubank.com.br>', ass = 'A fatura do seu cartão está fechada';
      expect(parse(rem, ass, fx('pagamento-recebido.txt'), new Date())).toBeNull();
      expect(parse(rem, ass, fx('pagamento-recebido.txt'), new Date(), [], true)).not.toBeNull();
    });
  });

  describe('instituições desconhecidas criam; adversariais não', () => {
    it.each([
      ['Banco Alfa <fatura@bancoalfa.com.br>', 'Sua fatura Alfa Visa fechou', 'instituicao-desconhecida/banco-alfa.txt', 'FATURA_CARTAO', null],
      ['Coop Beta <contato@coopbeta.coop.br>', 'Boleto da mensalidade de outubro', 'instituicao-desconhecida/coop-beta.txt', 'DESPESA', 250],
      ['Gama <no-reply@gamapay.com>', 'Vencimento amanhã: R$ 89,90', 'instituicao-desconhecida/fintech-gama.txt', 'DESPESA', 89.9],
    ])('%s cria', (rem, ass, f, tipo, valor) => {
      expect(parse(rem, ass, fx(f), new Date('2026-09-01T00:00:00Z'))).toMatchObject({ tipo, valor });
    });
    it.each([
      ['Você recebeu um Pix de Fulano', 'adversarial-corpo/pix-recebido.txt'],
      ['Compra aprovada', 'adversarial-corpo/compra-aprovada.txt'],
      ['Transferência realizada', 'adversarial-corpo/transferencia-realizada.txt'],
      ['Rendimento da caixinha', 'adversarial-corpo/rendimento-caixinha.txt'],
      ['Seu cartão foi entregue', 'adversarial-corpo/cartao-entregue.txt'],
      ['Resumo das suas compras', 'adversarial-corpo/resumo-compras.txt'],
      ['Informativo de limite', 'adversarial-corpo/informativo-limite-zero.txt'],
    ])('%s de nubank (fraco por S7) → null', (ass, f) => {
      expect(parse('Nubank <todomundo@nubank.com.br>', ass, fx(f), new Date('2026-09-01T00:00:00Z'))).toBeNull();
    });
    it('escola: "vence dia 10" aceito por E2 com "mensalidade" no assunto', () => {
      const r = parse('Escola X <financeiro@escolax.com.br>', 'Mensalidade de outubro', 'A mensalidade vence dia 10 — valor R$ 1.200,00. Boleto disponível no portal.', new Date('2026-09-25T00:00:00Z'));
      expect(r).toMatchObject({ tipo: 'DESPESA', dataVencimento: utc(2026, 10, 10) });
    });
    it('telecom desconhecida: "Sua conta chegou" + valor a pagar + vencimento → DESPESA', () => {
      const r = parse('Telecom Z <contato@telecomz.com.br>', 'Sua conta chegou', 'Sua conta chegou\nVencimento 20/09\nValor a pagar R$ 129,90\nPague no cartão de crédito', new Date('2026-09-01T00:00:00Z'));
      expect(r).toMatchObject({ tipo: 'DESPESA', valor: 129.9, dataVencimento: utc(2026, 9, 20) });
    });
  });

  describe('regressões preservadas', () => {
    const recebidoEm = utc(2026, 9, 1);
    it('Nubank com valor (fixture antiga)', () => {
      expect(parse('Nubank <fatura@nubank.com.br>', 'Sua fatura fechou', fx('nubank-fatura-fechou-com-valor.txt'), recebidoEm)).toMatchObject({ tipo: 'FATURA_CARTAO', valor: 1234.56, dataVencimento: utc(2026, 10, 10) });
    });
    it('Itaú boleto 47 dígitos', () => {
      expect(parse('Itaú <boletos@itau.com.br>', 'Boleto disponível', fx('itau-boleto-linha-digitavel.txt'), recebidoEm)).toMatchObject({ codigoBarras: '34191.79001 01043.510047 91020.150008 1 84410000012345', valor: 452.1, tipo: 'DESPESA' });
    });
    it('Enel 48 dígitos', () => {
      expect(parse('Enel <faturas@enel.com.br>', 'Sua conta de luz chegou', fx('enel-conta-luz-48-digitos.txt'), recebidoEm)?.codigoBarras).toBe('82660000001-2 23400012345-6 78900001234-5 60000000000-1');
    });
    it('marketing de fatura de remetente desconhecido não cria', () => {
      expect(parse('X <contato@bancoz.com.br>', 'Parcelamento da fatura agora disponível no app', 'Parcele a partir de R$ 99,90. Campanha válida até 31/12/2026.', recebidoEm)).toBeNull();
      expect(parse('X <contato@bancoz.com.br>', 'Nova função: fatura em PDF já disponível', 'Baixe no app.', recebidoEm)).toBeNull();
    });
    it('conta de luz que anuncia "pague no cartão" continua DESPESA', () => {
      expect(parse('Vivo <faturas@vivo.com.br>', 'Sua fatura Vivo chegou: pague no cartão de crédito', 'Valor a pagar R$ 99,90 Vencimento 10/10/2026', recebidoEm)?.tipo).toBe('DESPESA');
    });
  });

  describe('complementarComTexto', () => {
    const service2 = new EmailFinanceRegexParserService();
    const base = { tipo: 'FATURA_CARTAO' as const, descricao: 'x', instituicao: 'Nubank', valor: null, dataVencimento: utc(2026, 9, 8), dataEncontrada: false, codigoBarras: null };
    it('fills only missing fields', () => {
      const r = service2.complementarComTexto(base, 'Total da fatura R$ 1.234,56\nVencimento 15/09/2026', new Date('2026-09-08T00:00:00Z'));
      expect(r).toMatchObject({ valor: 1234.56, dataVencimento: utc(2026, 9, 15), dataEncontrada: true });
      const r2 = service2.complementarComTexto({ ...base, valor: 10, dataEncontrada: true }, 'Total da fatura R$ 1.234,56\nVencimento 15/09/2026', new Date());
      expect(r2).toMatchObject({ valor: 10, dataVencimento: utc(2026, 9, 8) });
    });
    it('null text is a no-op', () => {
      expect(service2.complementarComTexto(base, null, new Date())).toEqual(base);
    });
  });
});
```

- [ ] **Step 3: Rodar e ver falhar** (assinaturas mudaram).

- [ ] **Step 4: Reescrever o serviço**

```ts
import { Injectable } from '@nestjs/common';
import { normalizar, wb } from '../../common/text-match.util';
import { ResultadoTriagem } from './finance-email-detector';
import { AnexoMeta, evidenciaSuficiente, evidenciasDeCobranca, temEvidenciaNegativa } from './finance-evidence';
import { extrairCodigoBarras, extrairDataVencimento, extrairValor } from './finance-extractors';
import { resolverInstituicao } from './institution-map';
import { isCardInvoiceSubject } from './invoice-subject-patterns';

/** Sobe a cada mudança de regra; `EmailSummary.parserFinancasVersao < FINANCE_PARSER_VERSION` é reprocessado. */
export const FINANCE_PARSER_VERSION = 2;
export const CABECA_TIPO = 600;

export type TipoLancamentoParser = 'DESPESA' | 'FATURA_CARTAO';
export interface ParsedLancamento {
  tipo: TipoLancamentoParser;
  descricao: string;
  instituicao: string;
  valor: number | null;
  dataVencimento: Date;
  dataEncontrada: boolean;
  codigoBarras: string | null;
}
export interface ParseParams {
  remetente: string; assunto: string; corpo: string; recebidoEm: Date; triagem: ResultadoTriagem; anexos: AnexoMeta[];
}

const FATURA_LIFECYCLE_RE = wb('\\b(sua|a)\\s+faturas?\\s.{0,15}(fechou|fechada|dispon[ií]vel|gerada|emitida|chegou|vence em breve)');
const CARTAO_PERTO_DE_FATURA_RE = wb('\\bcart(ão|ao|[õo]es)\\b.{0,40}\\bfatura\\b|\\bfatura\\b.{0,40}\\bcart(ão|ao|[õo]es)\\b');
const BANDEIRA_PERTO_DE_FATURA_RE = wb('\\b(visa|mastercard|master|amex|hipercard)\\b.{0,40}\\bfatura\\b|\\bfatura\\b.{0,40}\\b(visa|mastercard|master|amex|hipercard)\\b');

@Injectable()
export class EmailFinanceRegexParserService {
  parse(p: ParseParams): ParsedLancamento | null {
    if (p.triagem.nivel === 'nao') return null;
    const marcado = p.triagem.sinais.includes('S4');
    const corpo = normalizar(p.corpo);
    if (!marcado && temEvidenciaNegativa(corpo, p.assunto)) return null;
    if (p.triagem.nivel === 'fraco') {
      const ev = evidenciasDeCobranca(corpo, p.anexos, p.recebidoEm);
      if (!evidenciaSuficiente(ev, p.triagem.assuntoTemSubstantivoCobranca)) return null;
    }

    const inst = resolverInstituicao(p.remetente, p.assunto);
    const { valor } = extrairValor(corpo);
    const data = extrairDataVencimento(corpo, p.recebidoEm);
    const codigoBarras = extrairCodigoBarras(corpo);

    return {
      tipo: this.decidirTipo(p.assunto, corpo, inst.tipoPadrao),
      descricao: p.assunto.trim(),
      instituicao: inst.nome,
      valor,
      dataVencimento: data.data ?? p.recebidoEm,
      dataEncontrada: data.data !== null,
      codigoBarras,
    };
  }

  /** Preenche só o que falta (valor null / data não encontrada) com texto do PDF anexo. */
  complementarComTexto(parsed: ParsedLancamento, texto: string | null, recebidoEm: Date): ParsedLancamento {
    if (!texto) return parsed;
    const t = normalizar(texto);
    const out = { ...parsed };
    if (out.valor === null) out.valor = extrairValor(t).valor;
    if (!out.dataEncontrada) {
      const d = extrairDataVencimento(t, recebidoEm);
      if (d.data) { out.dataVencimento = d.data; out.dataEncontrada = true; }
    }
    if (out.codigoBarras === null) out.codigoBarras = extrairCodigoBarras(t);
    return out;
  }

  private decidirTipo(assunto: string, corpo: string, tipoPadrao: 'CARTAO' | 'OUTRO' | undefined): TipoLancamentoParser {
    if (tipoPadrao === 'OUTRO') return 'DESPESA';
    const a = normalizar(assunto);
    const cabeca = corpo.slice(0, CABECA_TIPO);
    if (isCardInvoiceSubject(a)) return 'FATURA_CARTAO';
    if (CARTAO_PERTO_DE_FATURA_RE.test(cabeca)) return 'FATURA_CARTAO';
    if (tipoPadrao === 'CARTAO' && FATURA_LIFECYCLE_RE.test(a)) return 'FATURA_CARTAO';
    if (BANDEIRA_PERTO_DE_FATURA_RE.test(a) || BANDEIRA_PERTO_DE_FATURA_RE.test(cabeca)) return 'FATURA_CARTAO';
    return 'DESPESA';
  }
}
```

- [ ] **Step 5: Ajustar consumidores compilando** — `email-sync.service.ts` ainda chama `financeParser.matches/processEmail`. Para manter o build verde **nesta task**, deixe temporariamente em `email-sync.service.ts` o bloco do parser comentado com `// TODO Task 12: substituir por FinanceEmailProcessor` e remova a chamada (o Task 12 remove o TODO). Atualize `email-sync.service.spec.ts` removendo `financeParser` do `buildDeps`/`buildService` se necessário para compilar. `financas.module.ts` continua provendo `EmailFinanceRegexParserService` (sem Prisma agora).

- [ ] **Step 6: Rodar** — `npx jest src/financas/parser` → PASS; `npx tsc --noEmit -p tsconfig.json` → sem erro.

- [ ] **Step 7: Commit**

```bash
git add backend/src/financas backend/src/email-sync
git commit -m "feat(financas): parse() orientado a triagem, complementarComTexto e fixtures reais/adversariais

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Classificação de erros do Gmail

**Files:**
- Modify: `backend/src/gmail/gmail-error.util.ts`
- Create: `backend/src/gmail/gmail-error.util.spec.ts` (se já existir, acrescentar `describe`)

**Interfaces:**
- Produces: `type ClasseErroGmail = 'transitorio-conta' | 'transitorio-mensagem' | 'permanente'`; `classificarErroGmail(err: unknown): ClasseErroGmail`.

- [ ] **Step 1: Testes**

```ts
import { GaxiosError } from 'gaxios';
import { classificarErroGmail } from './gmail-error.util';

function gaxios(status?: number, extra: Record<string, unknown> = {}) {
  const err = new GaxiosError('x', { url: 'https://gmail' } as any, status ? ({ status, data: {} } as any) : undefined);
  if (status) (err as any).code = status;
  Object.assign(err, extra);
  return err;
}

describe('classificarErroGmail', () => {
  it.each([
    [gaxios(429), 'transitorio-conta'],
    [gaxios(401), 'transitorio-conta'],
    [gaxios(403), 'transitorio-conta'],
    [gaxios(503), 'transitorio-mensagem'],
    [gaxios(500), 'transitorio-mensagem'],
    [gaxios(404), 'permanente'],
    [gaxios(400), 'permanente'],
    [gaxios(undefined, { code: 'ENOTFOUND' }), 'transitorio-conta'],
    [gaxios(undefined, { code: 'ECONNRESET' }), 'transitorio-conta'],
    [gaxios(undefined, { error: { name: 'AbortError' } }), 'transitorio-conta'],
    [gaxios(undefined, { cause: { code: 'ETIMEDOUT' } }), 'transitorio-conta'],
    [gaxios(undefined), 'transitorio-conta'],
    [new TypeError('bug'), 'permanente'],
    [{ code: 'P2002' }, 'permanente'],
  ])('%p → %s', (err, esperado) => {
    expect(classificarErroGmail(err)).toBe(esperado);
  });
});
```

- [ ] **Step 2: Rodar e ver falhar.** (Se `import { GaxiosError } from 'gaxios'` não resolver, use `require('googleapis-common/node_modules/gaxios')` no teste — verifique com `ls node_modules/gaxios`.)

- [ ] **Step 3: Implementar** (acrescentar ao final de `gmail-error.util.ts`):

```ts
export type ClasseErroGmail = 'transitorio-conta' | 'transitorio-mensagem' | 'permanente';

const CODES_REDE = new Set(['ECONNRESET', 'ETIMEDOUT', 'ECONNREFUSED', 'EAI_AGAIN', 'ENOTFOUND', 'EPIPE']);
const NOMES_TIMEOUT = new Set(['AbortError', 'TimeoutError']);

/** Decide o que o reprocessamento faz com uma falha. Lê a forma REAL do gaxios 7: um timeout chega com
 *  `err.name === 'Error'` e `err.error.name === 'AbortError'`; erros de rede trazem `code` string; HTTP
 *  traz `status` numérico. Exceção que não veio do gaxios (parser, Prisma) é nossa → permanente. */
export function classificarErroGmail(error: unknown): ClasseErroGmail {
  const err = (error ?? {}) as Record<string, any>;
  const ehGaxios = typeof err === 'object' && ('config' in err || 'response' in err || err?.constructor?.name === 'GaxiosError');
  if (!ehGaxios) return 'permanente';

  const status = statusHttpDoErroGmail(error);
  if (status === 401 || status === 403 || status === 429) return 'transitorio-conta';
  const codes = [err.code, err.error?.code, err.cause?.code].filter((c) => typeof c === 'string') as string[];
  const nomes = [err.name, err.error?.name, err.cause?.name].filter((n) => typeof n === 'string') as string[];
  if (codes.some((c) => CODES_REDE.has(c)) || nomes.some((n) => NOMES_TIMEOUT.has(n))) return 'transitorio-conta';
  if (status === undefined) return 'transitorio-conta';
  if (status >= 500) return 'transitorio-mensagem';
  return 'permanente';
}
```

- [ ] **Step 4: Rodar até passar; commit**

```bash
git add backend/src/gmail/gmail-error.util.ts backend/src/gmail/gmail-error.util.spec.ts
git commit -m "feat(gmail): classificarErroGmail — transitório de conta/mensagem vs permanente

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Gmail client — `labelIds`, corpo com anexos, HTML em text/plain

**Files:**
- Modify: `backend/src/gmail/gmail-api-client.service.ts`
- Modify: `backend/src/gmail/gmail-api-client.service.spec.ts`

**Interfaces:**
- Produces:
  - `FetchedEmail.labelIds: string[]`
  - `interface CorpoComAnexos { texto: string; ehPreview: boolean; anexos: AnexoMeta[] }`
  - `fetchFullBodyComAnexos(refreshToken: string, gmailMessageId: string): Promise<CorpoComAnexos>`
  - `fetchFullBody(...)` mantido como wrapper que devolve `{ texto, ehPreview }` (os 3 consumidores atuais não mudam).
  - `static pareceHtml(texto: string): boolean`

- [ ] **Step 1: Testes** (acrescentar ao spec existente; siga o padrão de mock de `google.gmail` já usado ali — veja como `fetchFullBody` é testado hoje e copie a fábrica de `payload`):

```ts
describe('fetchFullBodyComAnexos', () => {
  it('converts a text/plain part that is actually HTML', async () => {
    const html = '<html><body><table><tr><td>Vencimento: 17/09<br>Valor total: 520,61</td></tr></table></body></html>';
    const payload = { mimeType: 'text/plain', body: { data: Buffer.from(html).toString('base64url') } };
    const r = await clientComPayload(payload).fetchFullBodyComAnexos('rt', 'm1');
    expect(r.texto).toContain('Vencimento: 17/09\nValor total: 520,61');
    expect(r.anexos).toEqual([]);
  });
  it.each(['﻿<html>', 'Preheader de texto\n<html>', '<p>x</p>', '<body>', '<!-- x --><html>'])('detects %p as HTML', (t) => {
    expect(GmailApiClient.pareceHtml(t)).toBe(true);
  });
  it('does not convert genuine plain text nor a tag past 300 chars', () => {
    expect(GmailApiClient.pareceHtml('Olá, segue sua fatura.')).toBe(false);
    expect(GmailApiClient.pareceHtml(`${'x'.repeat(301)}<html>`)).toBe(false);
  });
  it('lists attachment metadata without downloading, including octet-stream .PDF', async () => {
    const payload = {
      mimeType: 'multipart/mixed',
      parts: [
        { mimeType: 'text/plain', body: { data: Buffer.from('oi').toString('base64url') } },
        { mimeType: 'application/octet-stream', filename: 'Fatura_082026.PDF', body: { attachmentId: 'att1', size: 12345 } },
        { mimeType: 'image/png', filename: 'logo.png', body: { attachmentId: 'att2', size: 10 } },
      ],
    };
    const r = await clientComPayload(payload).fetchFullBodyComAnexos('rt', 'm1');
    expect(r.anexos).toEqual([
      { filename: 'Fatura_082026.PDF', mimeType: 'application/octet-stream', size: 12345, attachmentId: 'att1' },
      { filename: 'logo.png', mimeType: 'image/png', size: 10, attachmentId: 'att2' },
    ]);
  });
});

describe('fetchMessages labelIds', () => {
  it('carries labelIds on FetchedEmail', async () => {
    // usar a fábrica existente de fetchInitialUnread com labelIds: ['INBOX', 'Label_7']
    // expect(emails[0].labelIds).toEqual(['INBOX', 'Label_7'])
  });
});
```

Escreva `clientComPayload(payload)` no spec: mocka `google.gmail` para `users.messages.get` devolver `{ data: { payload, snippet: 's' } }` (mesma técnica do spec atual).

- [ ] **Step 2: Rodar e ver falhar.**

- [ ] **Step 3: Implementar**

Em `FetchedEmail` acrescente `labelIds: string[]`; em `fetchMessages` passe `labelIds`. Acrescente:

```ts
import type { AnexoMeta } from '../financas/parser/finance-evidence';
export interface CorpoComAnexos { texto: string; ehPreview: boolean; anexos: AnexoMeta[] }

const HTML_TAG_RE = /<(!doctype|html|head|body|table|div|p|center|br|span|font)\b|<!--/i;

/** Remetentes reais (Pefisa/Leroy) mandam HTML dentro da parte text/plain. Olha os 300 primeiros chars
 *  (sem BOM/espaços), em qualquer posição — um preheader de texto antes de <html> não engana. */
static pareceHtml(texto: string): boolean {
  return HTML_TAG_RE.test(texto.replace(/^﻿/, '').trimStart().slice(0, 300));
}

async fetchFullBodyComAnexos(refreshToken: string, gmailMessageId: string): Promise<CorpoComAnexos> {
  const gmail = this.gmailFor(refreshToken);
  const message = await gmail.users.messages.get({ userId: 'me', id: gmailMessageId, format: 'full' });
  const anexos = this.listarAnexos(message.data.payload);

  const textoPlano = this.extractPlainTextBody(message.data.payload);
  if (textoPlano !== null && textoPlano.trim() !== '') {
    const texto = GmailApiClient.pareceHtml(textoPlano) ? GmailApiClient.htmlParaTextoLegivel(textoPlano) : textoPlano;
    if (texto.trim() !== '') return { texto, ehPreview: false, anexos };
  }
  const html = this.extractHtmlBody(message.data.payload);
  if (html !== null) {
    const textoConvertido = GmailApiClient.htmlParaTextoLegivel(html);
    if (textoConvertido !== '') return { texto: textoConvertido, ehPreview: false, anexos };
  }
  return { texto: message.data.snippet ?? '', ehPreview: true, anexos };
}

/** Contrato antigo, mantido para o leitor de e-mail e o rascunho de resposta. */
async fetchFullBody(refreshToken: string, gmailMessageId: string): Promise<{ texto: string; ehPreview: boolean }> {
  const { texto, ehPreview } = await this.fetchFullBodyComAnexos(refreshToken, gmailMessageId);
  return { texto, ehPreview };
}

private listarAnexos(payload: gmail_v1.Schema$MessagePart | undefined): AnexoMeta[] {
  if (!payload) return [];
  const proprio: AnexoMeta[] = payload.filename && payload.body?.attachmentId
    ? [{ filename: payload.filename, mimeType: payload.mimeType ?? '', size: payload.body.size ?? 0, attachmentId: payload.body.attachmentId }]
    : [];
  return [...proprio, ...(payload.parts ?? []).flatMap((p) => this.listarAnexos(p))];
}
```

Remova o corpo antigo de `fetchFullBody` (agora wrapper).

- [ ] **Step 4: Rodar** — `npx jest src/gmail src/email-sync src/email-reply` → PASS (os consumidores usam o wrapper). Commit:

```bash
git add backend/src/gmail
git commit -m "feat(gmail): corpo com metadados de anexos, labelIds em FetchedEmail e HTML dentro de text/plain

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: PDF anexo (`fetchPdfAttachmentText`) e `withTimeout`

**Files:**
- Create: `backend/src/common/with-timeout.ts`, `backend/src/common/with-timeout.spec.ts`
- Modify: `backend/src/gmail/gmail-api-client.service.ts`, `.spec.ts`

**Interfaces:**
- Produces:
  - `class TimeoutError extends Error`; `withTimeout<T>(p: Promise<T>, ms: number): Promise<T>`
  - `fetchPdfAttachmentText(refreshToken: string, gmailMessageId: string, anexo: AnexoMeta): Promise<string | null>`
  - `escolherPdf(anexos: AnexoMeta[]): AnexoMeta | null` (estática): primeiro com `mimeType === 'application/pdf'` ou `filename` `.pdf`/`.PDF`, `size ≤ PDF_MAX_BYTES`.

- [ ] **Step 1: Testes de `withTimeout`**

```ts
import { TimeoutError, withTimeout } from './with-timeout';
describe('withTimeout', () => {
  it('resolves when fast', async () => { await expect(withTimeout(Promise.resolve(1), 50)).resolves.toBe(1); });
  it('rejects with TimeoutError when slow', async () => {
    await expect(withTimeout(new Promise((r) => setTimeout(r, 200)), 20)).rejects.toBeInstanceOf(TimeoutError);
  });
});
```

Implementação:

```ts
export class TimeoutError extends Error { constructor(ms: number) { super(`Tempo esgotado após ${ms} ms`); this.name = 'TimeoutError'; } }
export function withTimeout<T>(p: Promise<T>, ms: number): Promise<T> {
  let t: NodeJS.Timeout;
  return Promise.race([
    p.finally(() => clearTimeout(t)),
    new Promise<never>((_, reject) => { t = setTimeout(() => reject(new TimeoutError(ms)), ms); }),
  ]);
}
```

- [ ] **Step 2: Testes de PDF** (acrescentar ao spec do client). Gere um PDF mínimo válido com texto no próprio teste — pdf-parse v2 lê este arquivo:

```ts
const PDF_MINIMO = Buffer.from(`%PDF-1.4
1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj
3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 300 100]/Contents 4 0 R/Resources<</Font<</F1 5 0 R>>>>>>endobj
4 0 obj<</Length 60>>stream
BT /F1 12 Tf 10 50 Td (Total da fatura R$ 1.234,56) Tj ET
endstream
endobj
5 0 obj<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>endobj
trailer<</Root 1 0 R>>`);

describe('fetchPdfAttachmentText', () => {
  const anexo = { filename: 'f.pdf', mimeType: 'application/pdf', size: PDF_MINIMO.length, attachmentId: 'att1' };
  it('extracts text from a PDF attachment', async () => {
    const client = clientComAttachment(PDF_MINIMO.toString('base64url'));
    await expect(client.fetchPdfAttachmentText('rt', 'm1', anexo)).resolves.toContain('Total da fatura');
  });
  it('returns null for an unreadable PDF', async () => {
    const client = clientComAttachment(Buffer.from('nao e pdf').toString('base64url'));
    await expect(client.fetchPdfAttachmentText('rt', 'm1', anexo)).resolves.toBeNull();
  });
  it('escolherPdf picks by mimeType or extension within size cap', () => {
    expect(GmailApiClient.escolherPdf([{ filename: 'x.PDF', mimeType: 'application/octet-stream', size: 10, attachmentId: 'a' }])?.attachmentId).toBe('a');
    expect(GmailApiClient.escolherPdf([{ filename: 'big.pdf', mimeType: 'application/pdf', size: 6 * 1024 * 1024, attachmentId: 'b' }])).toBeNull();
    expect(GmailApiClient.escolherPdf([{ filename: 'logo.png', mimeType: 'image/png', size: 1, attachmentId: 'c' }])).toBeNull();
  });
  it('propagates a gaxios error from attachments.get (classified by the caller)', async () => {
    const client = clientComAttachmentErro(Object.assign(new Error('boom'), { response: { status: 503 }, code: 503 }));
    await expect(client.fetchPdfAttachmentText('rt', 'm1', anexo)).rejects.toBeDefined();
  });
});
```

`clientComAttachment(dataBase64url)` mocka `users.messages.attachments.get` → `{ data: { data: dataBase64url } }`.

- [ ] **Step 3: Implementar**

```ts
import { FormatError, InvalidPDFException, PasswordException, PDFParse } from 'pdf-parse';
import { TimeoutError, withTimeout } from '../common/with-timeout';

export const PDF_MAX_BYTES = 5 * 1024 * 1024;
export const PDF_PAGINAS = 3;
export const PDF_TIMEOUT_MS = 10_000;

static escolherPdf(anexos: AnexoMeta[]): AnexoMeta | null {
  return anexos.find((a) => (a.mimeType === 'application/pdf' || /\.pdf$/i.test(a.filename)) && a.size <= PDF_MAX_BYTES) ?? null;
}

/** Texto das 3 primeiras páginas do PDF anexo. Erros do Gmail (attachments.get) PROPAGAM para o chamador
 *  classificar; problemas do PDF em si (senha, corrompido, timeout) viram null. pdf-parse 2.x: API de classe
 *  (`rag/document-processor.service.ts` usa a API 1.x e está incompatível — dívida separada). */
async fetchPdfAttachmentText(refreshToken: string, gmailMessageId: string, anexo: AnexoMeta): Promise<string | null> {
  const gmail = this.gmailFor(refreshToken);
  const att = await gmail.users.messages.attachments.get({ userId: 'me', messageId: gmailMessageId, id: anexo.attachmentId });
  if (!att.data.data) return null;
  const buffer = Buffer.from(att.data.data, 'base64url');
  const parser = new PDFParse({ data: new Uint8Array(buffer) });
  try {
    const { text } = await withTimeout(parser.getText({ first: PDF_PAGINAS }), PDF_TIMEOUT_MS);
    return text;
  } catch (e) {
    if (e instanceof PasswordException || e instanceof InvalidPDFException || e instanceof FormatError || e instanceof TimeoutError) return null;
    // pdf-parse lança subclasses variadas para lixo binário; qualquer erro não-gaxios é "PDF ilegível".
    if (!(e as { config?: unknown }).config && !(e as { response?: unknown }).response) return null;
    throw e;
  } finally {
    await parser.destroy().catch(() => undefined);
  }
}
```

Se `import { PDFParse } from 'pdf-parse'` falhar em CJS/ts-jest, use `const { PDFParse, PasswordException, InvalidPDFException, FormatError } = require('pdf-parse') as typeof import('pdf-parse');` com `// eslint-disable-next-line @typescript-eslint/no-require-imports`.

- [ ] **Step 4: Rodar até passar; commit**

```bash
git add backend/src/common/with-timeout.ts backend/src/common/with-timeout.spec.ts backend/src/gmail
git commit -m "feat(gmail): texto do PDF anexo via pdf-parse v2 com limite de tamanho, páginas e timeout

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 11: Marcador Gmail (`listarIdsComMarcador`)

**Files:**
- Modify: `backend/src/gmail/gmail-api-client.service.ts`, `.spec.ts`

**Interfaces:**
- Produces: `MARCADOR_NOME = 'Sincro/Finanças'`; `listarIdsComMarcador(refreshToken: string): Promise<{ labelId: string | null; ids: Set<string> }>`.

- [ ] **Step 1: Testes**

```ts
describe('listarIdsComMarcador', () => {
  it('resolves the label (NFC, case-insensitive) and lists message ids', async () => {
    const client = clientComLabels(
      [{ id: 'Label_7', name: 'sincro/finanças' }],
      [{ id: 'm1' }, { id: 'm2' }],
    );
    await expect(client.listarIdsComMarcador('rt')).resolves.toEqual({ labelId: 'Label_7', ids: new Set(['m1', 'm2']) });
    // messages.list chamado com { userId: 'me', labelIds: ['Label_7'], q: 'newer_than:90d', maxResults: 100 }
  });
  it('returns an empty set without extra calls when the label does not exist', async () => {
    const client = clientComLabels([{ id: 'Label_1', name: 'Outro' }], []);
    await expect(client.listarIdsComMarcador('rt')).resolves.toEqual({ labelId: null, ids: new Set() });
    // messages.list não chamado
  });
});
```

- [ ] **Step 2: Implementar**

```ts
export const MARCADOR_NOME = 'Sincro/Finanças';
const MARCADOR_JANELA = 'newer_than:90d';
const MARCADOR_MAX = 100;

async listarIdsComMarcador(refreshToken: string): Promise<{ labelId: string | null; ids: Set<string> }> {
  const gmail = this.gmailFor(refreshToken);
  const labels = await gmail.users.labels.list({ userId: 'me' });
  const alvo = MARCADOR_NOME.normalize('NFC').toLowerCase();
  const label = (labels.data.labels ?? []).find((l) => (l.name ?? '').normalize('NFC').toLowerCase() === alvo);
  if (!label?.id) return { labelId: null, ids: new Set() };
  const lista = await gmail.users.messages.list({ userId: 'me', labelIds: [label.id], q: MARCADOR_JANELA, maxResults: MARCADOR_MAX });
  const ids = new Set((lista.data.messages ?? []).map((m) => m.id).filter((id): id is string => typeof id === 'string'));
  return { labelId: label.id, ids };
}
```

- [ ] **Step 3: Rodar até passar; commit**

```bash
git add backend/src/gmail
git commit -m "feat(gmail): ids de mensagens com o marcador Sincro/Finanças

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 12: `FinanceEmailProcessor`

**Files:**
- Create: `backend/src/financas/parser/finance-email-processor.service.ts`, `.spec.ts`
- Modify: `backend/src/financas/financas.module.ts` (provê e exporta `FinanceEmailProcessor`)

**Interfaces:**
- Consumes: `triagem` (T4), `EmailFinanceRegexParserService.parse/complementarComTexto` (T7), `GmailApiClient.fetchFullBodyComAnexos/escolherPdf/fetchPdfAttachmentText` (T9–10), `classificarErroGmail` (T8), `PrismaService`.
- Produces:
  - `interface EmailParaProcessar { gmailMessageId: string; remetente: string; assunto: string; recebidoEm: Date }`
  - `interface ResultadoProcessamento { transitorio: boolean; classe: ClasseErroGmail | null; acao: 'criado' | 'atualizado' | 'removido' | 'nada' | 'erro' }`
  - `processar(userId: string, refreshToken: string, email: EmailParaProcessar, opts: { marcado: boolean }): Promise<ResultadoProcessamento>` — **nunca lança**.
  - `removerLancamentoDaMaquina(userId: string, emailMessageId: string): Promise<void>`

- [ ] **Step 1: Testes**

```ts
import { FinanceEmailProcessor } from './finance-email-processor.service';
import { EmailFinanceRegexParserService } from './email-finance-regex-parser.service';

function deps() {
  const prisma = {
    lancamentoFinanceiro: {
      findUnique: jest.fn().mockResolvedValue(null),
      create: jest.fn(),
      updateMany: jest.fn(),
      deleteMany: jest.fn(),
    },
  };
  const gmail = {
    fetchFullBodyComAnexos: jest.fn().mockResolvedValue({ texto: '', ehPreview: false, anexos: [] }),
    fetchPdfAttachmentText: jest.fn().mockResolvedValue(null),
  };
  return { prisma, gmail, processor: new FinanceEmailProcessor(prisma as any, gmail as any, new EmailFinanceRegexParserService()) };
}
const nubank = { gmailMessageId: 'm1', remetente: 'Nubank <todomundo@nubank.com.br>', assunto: 'A fatura do seu cartão Nubank está fechada', recebidoEm: new Date('2026-09-08T04:37:16Z') };

describe('FinanceEmailProcessor.processar', () => {
  it('nao → remove lançamento da máquina, sem buscar corpo', async () => {
    const d = deps();
    const r = await d.processor.processar('u1', 'rt', { ...nubank, assunto: 'Extrato da sua conta do Nubank' }, { marcado: false });
    expect(r).toMatchObject({ transitorio: false, acao: 'removido' });
    expect(d.gmail.fetchFullBodyComAnexos).not.toHaveBeenCalled();
    expect(d.prisma.lancamentoFinanceiro.deleteMany).toHaveBeenCalledWith({ where: { userId: 'u1', emailMessageId: 'm1', origem: 'EMAIL_PARSER', status: 'PENDENTE_REVISAO' } });
  });
  it('forte sem lançamento → create PENDENTE_REVISAO/EMAIL_PARSER', async () => {
    const d = deps();
    d.gmail.fetchFullBodyComAnexos.mockResolvedValue({ texto: 'Sua fatura já está fechada, vence no dia 15 de setembro', ehPreview: false, anexos: [] });
    const r = await d.processor.processar('u1', 'rt', nubank, { marcado: false });
    expect(r.acao).toBe('criado');
    expect(d.prisma.lancamentoFinanceiro.create).toHaveBeenCalledWith({ data: expect.objectContaining({ userId: 'u1', emailMessageId: 'm1', status: 'PENDENTE_REVISAO', origem: 'EMAIL_PARSER', tipo: 'FATURA_CARTAO', valor: null, dataVencimento: new Date(Date.UTC(2026, 8, 15)) }) });
  });
  it('lançamento pendente da máquina existente → updateMany condicionado', async () => {
    const d = deps();
    d.prisma.lancamentoFinanceiro.findUnique.mockResolvedValue({ id: 'l1', origem: 'EMAIL_PARSER', status: 'PENDENTE_REVISAO' });
    d.gmail.fetchFullBodyComAnexos.mockResolvedValue({ texto: 'Total da fatura R$ 520,61\nVencimento 17/09/2026', ehPreview: false, anexos: [] });
    const r = await d.processor.processar('u1', 'rt', nubank, { marcado: false });
    expect(r.acao).toBe('atualizado');
    expect(d.prisma.lancamentoFinanceiro.updateMany).toHaveBeenCalledWith({
      where: { userId: 'u1', emailMessageId: 'm1', origem: 'EMAIL_PARSER', status: 'PENDENTE_REVISAO' },
      data: expect.objectContaining({ valor: 520.61 }),
    });
  });
  it('lançamento confirmado → não toca', async () => {
    const d = deps();
    d.prisma.lancamentoFinanceiro.findUnique.mockResolvedValue({ id: 'l1', origem: 'EMAIL_PARSER', status: 'CONFIRMADO' });
    const r = await d.processor.processar('u1', 'rt', nubank, { marcado: false });
    expect(r.acao).toBe('nada');
    expect(d.prisma.lancamentoFinanceiro.updateMany).not.toHaveBeenCalled();
    expect(d.prisma.lancamentoFinanceiro.create).not.toHaveBeenCalled();
  });
  it('parse null (fraco sem evidência) → remove', async () => {
    const d = deps();
    const r = await d.processor.processar('u1', 'rt', { ...nubank, assunto: 'Resumo das suas compras' }, { marcado: false });
    expect(r.acao).toBe('removido');
  });
  it('consulta o PDF só quando falta valor ou data, e complementa', async () => {
    const d = deps();
    const anexo = { filename: 'Nubank.pdf', mimeType: 'application/pdf', size: 10, attachmentId: 'a1' };
    d.gmail.fetchFullBodyComAnexos.mockResolvedValue({ texto: 'Sua fatura já está fechada, vence no dia 15 de setembro', ehPreview: false, anexos: [anexo] });
    d.gmail.fetchPdfAttachmentText.mockResolvedValue('Total da fatura R$ 1.234,56');
    await d.processor.processar('u1', 'rt', nubank, { marcado: false });
    expect(d.gmail.fetchPdfAttachmentText).toHaveBeenCalledWith('rt', 'm1', anexo);
    expect(d.prisma.lancamentoFinanceiro.create).toHaveBeenCalledWith({ data: expect.objectContaining({ valor: 1234.56 }) });
  });
  it('não consulta o PDF quando o corpo já tem valor e data', async () => {
    const d = deps();
    d.gmail.fetchFullBodyComAnexos.mockResolvedValue({ texto: 'Total da fatura R$ 10,00\nVencimento 10/10/2026', ehPreview: false, anexos: [{ filename: 'x.pdf', mimeType: 'application/pdf', size: 1, attachmentId: 'a' }] });
    await d.processor.processar('u1', 'rt', nubank, { marcado: false });
    expect(d.gmail.fetchPdfAttachmentText).not.toHaveBeenCalled();
  });
  it('erro 503 do Gmail → transitorio-mensagem, nada gravado', async () => {
    const d = deps();
    d.gmail.fetchFullBodyComAnexos.mockRejectedValue(Object.assign(new Error('x'), { response: { status: 503 }, code: 503, config: {} }));
    const r = await d.processor.processar('u1', 'rt', nubank, { marcado: false });
    expect(r).toMatchObject({ transitorio: true, classe: 'transitorio-mensagem', acao: 'erro' });
    expect(d.prisma.lancamentoFinanceiro.create).not.toHaveBeenCalled();
  });
  it('erro 404 → permanente, remove lançamento da máquina', async () => {
    const d = deps();
    d.gmail.fetchFullBodyComAnexos.mockRejectedValue(Object.assign(new Error('x'), { response: { status: 404 }, code: 404, config: {} }));
    const r = await d.processor.processar('u1', 'rt', nubank, { marcado: false });
    expect(r).toMatchObject({ transitorio: false, classe: 'permanente', acao: 'removido' });
    expect(d.prisma.lancamentoFinanceiro.deleteMany).toHaveBeenCalled();
  });
  it('exceção do parser → permanente, acao erro', async () => {
    const d = deps();
    d.gmail.fetchFullBodyComAnexos.mockRejectedValue(new TypeError('bug'));
    const r = await d.processor.processar('u1', 'rt', nubank, { marcado: false });
    expect(r).toMatchObject({ transitorio: false, classe: 'permanente', acao: 'erro' });
  });
  it('P2002 no create → tratado como corrida benigna', async () => {
    const d = deps();
    d.gmail.fetchFullBodyComAnexos.mockResolvedValue({ texto: 'x', ehPreview: false, anexos: [] });
    d.prisma.lancamentoFinanceiro.create.mockRejectedValue({ code: 'P2002' });
    const r = await d.processor.processar('u1', 'rt', nubank, { marcado: false });
    expect(r).toMatchObject({ transitorio: false, acao: 'nada' });
  });
});
```

- [ ] **Step 2: Implementar**

```ts
import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { GmailApiClient } from '../../gmail/gmail-api-client.service';
import { ClasseErroGmail, classificarErroGmail, gmailMensagemNaoEncontrada } from '../../gmail/gmail-error.util';
import { EmailFinanceRegexParserService, ParsedLancamento } from './email-finance-regex-parser.service';
import { triagem } from './finance-email-detector';

export interface EmailParaProcessar { gmailMessageId: string; remetente: string; assunto: string; recebidoEm: Date }
export interface ResultadoProcessamento {
  transitorio: boolean;
  classe: ClasseErroGmail | null;
  acao: 'criado' | 'atualizado' | 'removido' | 'nada' | 'erro';
}

const FILTRO_MAQUINA = { origem: 'EMAIL_PARSER' as const, status: 'PENDENTE_REVISAO' as const };

/** Ponto único: e-mails novos e reprocessamento passam por aqui. Nunca lança — devolve a classe do erro
 *  para o chamador decidir o carimbo de versão. */
@Injectable()
export class FinanceEmailProcessor {
  private readonly logger = new Logger(FinanceEmailProcessor.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly gmail: GmailApiClient,
    private readonly parser: EmailFinanceRegexParserService,
  ) {}

  async processar(userId: string, refreshToken: string, email: EmailParaProcessar, opts: { marcado: boolean }): Promise<ResultadoProcessamento> {
    try {
      const t = triagem(email.remetente, email.assunto, { marcado: opts.marcado });
      if (t.nivel === 'nao') { await this.removerLancamentoDaMaquina(userId, email.gmailMessageId); return this.ok('removido'); }

      const { texto, anexos } = await this.gmail.fetchFullBodyComAnexos(refreshToken, email.gmailMessageId);
      let parsed = this.parser.parse({ remetente: email.remetente, assunto: email.assunto, corpo: texto, recebidoEm: email.recebidoEm, triagem: t, anexos });
      if (!parsed) { await this.removerLancamentoDaMaquina(userId, email.gmailMessageId); return this.ok('removido'); }

      if (parsed.valor === null || !parsed.dataEncontrada) {
        const pdf = GmailApiClient.escolherPdf(anexos);
        if (pdf) {
          const textoPdf = await this.gmail.fetchPdfAttachmentText(refreshToken, email.gmailMessageId, pdf);
          parsed = this.parser.complementarComTexto(parsed, textoPdf, email.recebidoEm);
        }
      }
      return await this.gravar(userId, email.gmailMessageId, parsed);
    } catch (error) {
      const classe = classificarErroGmail(error);
      if (classe === 'permanente' && gmailMensagemNaoEncontrada(error)) {
        await this.removerLancamentoDaMaquina(userId, email.gmailMessageId);
        return { transitorio: false, classe, acao: 'removido' };
      }
      const log = classe === 'permanente' ? 'error' : 'warn';
      this.logger[log](`Finance processing failed for message ${email.gmailMessageId} (${classe})`, error as Error);
      return { transitorio: classe !== 'permanente', classe, acao: 'erro' };
    }
  }

  async removerLancamentoDaMaquina(userId: string, emailMessageId: string): Promise<void> {
    await this.prisma.lancamentoFinanceiro.deleteMany({ where: { userId, emailMessageId, ...FILTRO_MAQUINA } });
  }

  private async gravar(userId: string, emailMessageId: string, parsed: ParsedLancamento): Promise<ResultadoProcessamento> {
    const campos = {
      tipo: parsed.tipo, descricao: parsed.descricao, instituicao: parsed.instituicao, valor: parsed.valor,
      dataVencimento: parsed.dataVencimento, dataCompetencia: parsed.dataVencimento, codigoBarras: parsed.codigoBarras,
    };
    const existente = await this.prisma.lancamentoFinanceiro.findUnique({ where: { userId_emailMessageId: { userId, emailMessageId } } });
    if (existente) {
      if (existente.origem !== 'EMAIL_PARSER' || existente.status !== 'PENDENTE_REVISAO') return this.ok('nada');
      await this.prisma.lancamentoFinanceiro.updateMany({ where: { userId, emailMessageId, ...FILTRO_MAQUINA }, data: campos });
      return this.ok('atualizado');
    }
    try {
      await this.prisma.lancamentoFinanceiro.create({ data: { userId, emailMessageId, status: 'PENDENTE_REVISAO', origem: 'EMAIL_PARSER', ...campos } });
      return this.ok('criado');
    } catch (error) {
      if ((error as { code?: string } | null)?.code === 'P2002') return this.ok('nada');
      throw error;
    }
  }

  private ok(acao: ResultadoProcessamento['acao']): ResultadoProcessamento {
    return { transitorio: false, classe: null, acao };
  }
}
```

Em `financas.module.ts`: adicionar `FinanceEmailProcessor` a `providers` e `exports` (manter `EmailFinanceRegexParserService` em providers).

- [ ] **Step 3: Rodar até passar; commit**

```bash
git add backend/src/financas
git commit -m "feat(financas): FinanceEmailProcessor — ponto único de triagem, parse, PDF e escrita idempotente

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 13: `EmailSyncService` — passos 0, A e B

**Files:**
- Modify: `backend/src/email-sync/email-sync.service.ts`, `.spec.ts`

**Interfaces:**
- Consumes: `FinanceEmailProcessor.processar` (T12), `GmailApiClient.listarIdsComMarcador` (T11), `FINANCE_PARSER_VERSION` (T7), `FetchedEmail.labelIds` (T9).
- Produces: `syncUser` inalterado na assinatura; novo método privado `reprocessarPendentes(userId, refreshToken, marcador)`; `LOTE_REPROCESSAMENTO = 50`.

- [ ] **Step 1: Testes** — atualizar `buildDeps`: trocar `financeParser` por `financeProcessor = { processar: jest.fn().mockResolvedValue({ transitorio: false, classe: null, acao: 'nada' }) }`; acrescentar em `gmailApiClient` `listarIdsComMarcador: jest.fn().mockResolvedValue({ labelId: null, ids: new Set() })`; em `prisma.emailSummary` acrescentar `update: jest.fn()`, `updateMany: jest.fn()`, `findMany: jest.fn().mockResolvedValue([])`; em `prisma` acrescentar `$executeRaw: jest.fn()`. Ajustar `buildService` para o novo construtor. Novos testes:

```ts
describe('EmailSyncService — finanças', () => {
  const email = { gmailMessageId: 'm1', remetente: 'Nubank <todomundo@nubank.com.br>', assunto: 'A fatura do seu cartão Nubank está fechada', corpo: 's', recebidoEm: new Date(), labelIds: ['INBOX'] };
  function comNovo(deps: ReturnType<typeof buildDeps>) {
    deps.prisma.gmailConnection.findUnique.mockResolvedValue({ userId: 'u1', lastHistoryId: null });
    deps.gmailApiClient.fetchInitialUnread.mockResolvedValue({ emails: [email], historyId: 'h1' });
  }

  it('(A) carimba versão e labelIds no summary novo', async () => {
    const deps = buildDeps(); comNovo(deps);
    await buildService(deps).syncUser('u1');
    expect(deps.financeProcessor.processar).toHaveBeenCalledWith('u1', 'rt-123', expect.objectContaining({ gmailMessageId: 'm1' }), { marcado: false });
    expect(deps.prisma.emailSummary.create).toHaveBeenCalledWith({ data: expect.objectContaining({ labelIds: ['INBOX'], parserFinancasVersao: 2, parserFinancasTentativas: 0 }) });
  });
  it('(A) falha transitória grava versão null e tentativas 1', async () => {
    const deps = buildDeps(); comNovo(deps);
    deps.financeProcessor.processar.mockResolvedValue({ transitorio: true, classe: 'transitorio-mensagem', acao: 'erro' });
    await buildService(deps).syncUser('u1');
    expect(deps.prisma.emailSummary.create).toHaveBeenCalledWith({ data: expect.objectContaining({ parserFinancasVersao: null, parserFinancasTentativas: 1 }) });
  });
  it('(0) marcador: passa marcado=true e re-enfileira quem não tinha o label', async () => {
    const deps = buildDeps(); comNovo(deps);
    deps.gmailApiClient.listarIdsComMarcador.mockResolvedValue({ labelId: 'Label_7', ids: new Set(['m1', 'm9']) });
    await buildService(deps).syncUser('u1');
    expect(deps.prisma.$executeRaw).toHaveBeenCalledTimes(1);
    expect(deps.financeProcessor.processar).toHaveBeenCalledWith('u1', 'rt-123', expect.anything(), { marcado: true });
    expect(deps.prisma.emailSummary.create).toHaveBeenCalledWith({ data: expect.objectContaining({ labelIds: ['INBOX', 'Label_7'] }) });
  });
  it('(0) falha transitória no marcador não derruba o ciclo', async () => {
    const deps = buildDeps(); comNovo(deps);
    deps.gmailApiClient.listarIdsComMarcador.mockRejectedValue(Object.assign(new Error('x'), { code: 503, response: { status: 503 }, config: {} }));
    await expect(buildService(deps).syncUser('u1')).resolves.toBeDefined();
    expect(deps.financeProcessor.processar).toHaveBeenCalledWith('u1', 'rt-123', expect.anything(), { marcado: false });
  });
  it('(B) reprocessa pendentes ordenados, carimba sucesso e zera tentativas', async () => {
    const deps = buildDeps();
    deps.prisma.gmailConnection.findUnique.mockResolvedValue({ userId: 'u1', lastHistoryId: 'h0' });
    deps.gmailApiClient.fetchIncremental.mockResolvedValue({ emails: [], historyId: 'h1', historyExpired: false });
    deps.prisma.emailSummary.findMany.mockResolvedValue([{ id: 's1', gmailMessageId: 'm1', remetente: 'r', assunto: 'a', recebidoEm: new Date(), labelIds: [] }]);
    await buildService(deps).syncUser('u1');
    expect(deps.prisma.emailSummary.findMany).toHaveBeenCalledWith({
      where: { userId: 'u1', OR: [{ parserFinancasVersao: null }, { parserFinancasVersao: { lt: 2 } }] },
      orderBy: [{ parserFinancasTentativas: 'asc' }, { recebidoEm: 'desc' }],
      take: 50,
    });
    expect(deps.prisma.emailSummary.update).toHaveBeenCalledWith({ where: { id: 's1' }, data: { parserFinancasVersao: 2, parserFinancasTentativas: 0, labelIds: [] } });
  });
  it('(B) transitório-mensagem incrementa e segue; transitório-conta incrementa e interrompe', async () => {
    const deps = buildDeps();
    deps.prisma.gmailConnection.findUnique.mockResolvedValue({ userId: 'u1', lastHistoryId: 'h0' });
    deps.gmailApiClient.fetchIncremental.mockResolvedValue({ emails: [], historyId: 'h1', historyExpired: false });
    deps.prisma.emailSummary.findMany.mockResolvedValue([
      { id: 's1', gmailMessageId: 'm1', remetente: 'r', assunto: 'a', recebidoEm: new Date(), labelIds: [], parserFinancasTentativas: 0 },
      { id: 's2', gmailMessageId: 'm2', remetente: 'r', assunto: 'a', recebidoEm: new Date(), labelIds: [], parserFinancasTentativas: 0 },
      { id: 's3', gmailMessageId: 'm3', remetente: 'r', assunto: 'a', recebidoEm: new Date(), labelIds: [], parserFinancasTentativas: 0 },
    ]);
    deps.financeProcessor.processar
      .mockResolvedValueOnce({ transitorio: true, classe: 'transitorio-mensagem', acao: 'erro' })
      .mockResolvedValueOnce({ transitorio: true, classe: 'transitorio-conta', acao: 'erro' });
    await buildService(deps).syncUser('u1');
    expect(deps.financeProcessor.processar).toHaveBeenCalledTimes(2);
    expect(deps.prisma.emailSummary.update).toHaveBeenNthCalledWith(1, { where: { id: 's1' }, data: { parserFinancasTentativas: { increment: 1 } } });
    expect(deps.prisma.emailSummary.update).toHaveBeenNthCalledWith(2, { where: { id: 's2' }, data: { parserFinancasTentativas: { increment: 1 } } });
  });
  it('(B) erro permanente carimba', async () => {
    const deps = buildDeps();
    deps.prisma.gmailConnection.findUnique.mockResolvedValue({ userId: 'u1', lastHistoryId: 'h0' });
    deps.gmailApiClient.fetchIncremental.mockResolvedValue({ emails: [], historyId: 'h1', historyExpired: false });
    deps.prisma.emailSummary.findMany.mockResolvedValue([{ id: 's1', gmailMessageId: 'm1', remetente: 'r', assunto: 'a', recebidoEm: new Date(), labelIds: [] }]);
    deps.financeProcessor.processar.mockResolvedValue({ transitorio: false, classe: 'permanente', acao: 'erro' });
    await buildService(deps).syncUser('u1');
    expect(deps.prisma.emailSummary.update).toHaveBeenCalledWith({ where: { id: 's1' }, data: { parserFinancasVersao: 2, parserFinancasTentativas: 0, labelIds: [] } });
  });
});
```

Ajuste os testes existentes que asseveravam `financeParser.matches/processEmail` para o novo `financeProcessor.processar`.

- [ ] **Step 2: Implementar** — em `email-sync.service.ts`:

Construtor: trocar `financeParser: EmailFinanceRegexParserService` por `financeProcessor: FinanceEmailProcessor`. Imports: `FinanceEmailProcessor`, `FINANCE_PARSER_VERSION`, `classificarErroGmail`, `Prisma` (de `@prisma/client`). Dentro de `syncUser`, depois de obter `refreshToken`:

```ts
    const marcador = await this.resolverMarcador(userId, refreshToken);
```

No loop de novos e-mails, substituir o bloco do parser por:

```ts
      const marcado = marcador.ids.has(email.gmailMessageId);
      const fin = await this.financeProcessor.processar(userId, refreshToken, email, { marcado });
      const labelIds = marcado && marcador.labelId && !email.labelIds.includes(marcador.labelId)
        ? [...email.labelIds, marcador.labelId] : email.labelIds;
```

e no `emailSummary.create` acrescentar `labelIds, parserFinancasVersao: fin.transitorio ? null : FINANCE_PARSER_VERSION, parserFinancasTentativas: fin.transitorio ? 1 : 0`.

Depois do loop (antes do `gmailConnection.update`), chamar `await this.reprocessarPendentes(userId, refreshToken, marcador);`. Novos métodos:

```ts
  private async resolverMarcador(userId: string, refreshToken: string): Promise<{ labelId: string | null; ids: Set<string> }> {
    try {
      const marcador = await this.gmailApiClient.listarIdsComMarcador(refreshToken);
      if (marcador.labelId && marcador.ids.size > 0) {
        // Re-enfileira só quem ainda não tinha o marcador persistido (idempotente por evento).
        await this.prisma.$executeRaw`
          UPDATE resumos_email SET parser_financas_versao = NULL
          WHERE user_id = ${userId} AND gmail_message_id = ANY(${Array.from(marcador.ids)}::text[])
            AND NOT (label_ids @> ARRAY[${marcador.labelId}]::text[])`;
      }
      return marcador;
    } catch (error) {
      this.logger.warn(`Marcador ${MARCADOR_NOME} indisponível neste ciclo (${classificarErroGmail(error)}); seguindo sem ele`, error as Error);
      return { labelId: null, ids: new Set() };
    }
  }

  /** Passo (B): e-mails já sincronizados que o parser atual ainda não avaliou. Fila ordenada por
   *  tentativas para uma mensagem venenosa afundar sem bloquear; transitório NUNCA carimba. */
  private async reprocessarPendentes(userId: string, refreshToken: string, marcador: { labelId: string | null; ids: Set<string> }): Promise<void> {
    const pendentes = await this.prisma.emailSummary.findMany({
      where: { userId, OR: [{ parserFinancasVersao: null }, { parserFinancasVersao: { lt: FINANCE_PARSER_VERSION } }] },
      orderBy: [{ parserFinancasTentativas: 'asc' }, { recebidoEm: 'desc' }],
      take: LOTE_REPROCESSAMENTO,
    });
    for (const s of pendentes) {
      const marcado = marcador.ids.has(s.gmailMessageId);
      const fin = await this.financeProcessor.processar(userId, refreshToken, { gmailMessageId: s.gmailMessageId, remetente: s.remetente, assunto: s.assunto, recebidoEm: s.recebidoEm }, { marcado });
      if (fin.transitorio) {
        await this.prisma.emailSummary.update({ where: { id: s.id }, data: { parserFinancasTentativas: { increment: 1 } } });
        if (fin.classe === 'transitorio-conta') { this.logger.warn(`Reprocessamento interrompido para ${userId}: Gmail indisponível`); break; }
        continue;
      }
      const labelIds = marcado && marcador.labelId && !s.labelIds.includes(marcador.labelId) ? [...s.labelIds, marcador.labelId] : s.labelIds;
      await this.prisma.emailSummary.update({ where: { id: s.id }, data: { parserFinancasVersao: FINANCE_PARSER_VERSION, parserFinancasTentativas: 0, labelIds } });
    }
  }
```

Constante no topo: `const LOTE_REPROCESSAMENTO = 50;` e import de `MARCADOR_NOME` do client. Remover o `TODO Task 12` e o import de `EmailFinanceRegexParserService`. `EmailSyncModule` já importa `FinancasModule` (que agora exporta `FinanceEmailProcessor`).

- [ ] **Step 3: Rodar** — `npx jest src/email-sync` → PASS; `npx tsc --noEmit -p tsconfig.json`.

- [ ] **Step 4: Commit**

```bash
git add backend/src/email-sync backend/src/financas/financas.module.ts
git commit -m "feat(email-sync): marcador Sincro/Finanças, carimbo de versão e reprocessamento sem perda

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 14: Verificação final, lint e limpeza

**Files:**
- Modify: `backend/src/financas/parser/invoice-subject-patterns.ts` (só doc-comment: `isCardInvoiceSubject` agora serve ao classificador e à decisão de tipo).
- Delete: fixtures antigas que nenhum teste usa (`email-remetente-desconhecido.txt`, `cartao-desconhecido-fatura.txt`, `email-com-multiplos-valores-ambiguos.txt`, `data-por-extenso.txt`) **somente se** `grep -rn "<nome>" backend/src` não achar uso.

- [ ] **Step 1: Suíte completa** — `cd backend && npx jest` → 0 falhas. Se `heuristic-email-classifier.service.spec.ts` ou `email-reply` quebrarem, é porque importaram algo removido do parser — corrija o import, não o comportamento.
- [ ] **Step 2: Build e lint** — `npx tsc --noEmit -p tsconfig.json && npm run lint` → sem erros.
- [ ] **Step 3: Migration** — `npx prisma migrate diff --from-migrations prisma/migrations --to-schema-datamodel prisma/schema.prisma --shadow-database-url "$SHADOW_DATABASE_URL" --script` deve devolver script vazio (schema e migrations coerentes). Sem shadow DB disponível, registrar como item manual do deploy.
- [ ] **Step 4: Protótipo × implementação** — rodar `npx ts-node --compiler-options '{"module":"commonjs"}' -e "..."` chamando `triagem()` real sobre a fixture `amostra-real-2026-09.json` e imprimir contagem: esperado 12/12 candidatos, 0/12 fortes indevidos.
- [ ] **Step 5: Commit final**

```bash
git add -A backend/src backend/prisma
git commit -m "chore(financas): limpeza de fixtures órfãs e verificação final da detecção v2

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage** — Detecção (T4), Extração (T5, T7), Evidência (T6), Corpo/HTML (T9), PDF (T10), Marcador + re-enfileiramento idempotente (T11, T13), Reprocessamento + classificação de erros + fila sem perda (T8, T13), Modelagem (T1), `INSTITUTION_MAP` enriquecimento (T3), fixtures reais/fictícias/adversariais (T4, T7), testes existentes cuja expectativa muda (T7 "regressões preservadas" + "marketing… não cria"). Fora do plano por decisão da spec: mobile, janela inicial, paginação do history.list, LLM.

**Placeholders** — nenhum "TBD"; o único passo condicional é o T14 Step 3 (shadow DB), declarado como manual quando indisponível.

**Type consistency** — `ResultadoTriagem.assuntoTemSubstantivoCobranca` (T4) é o que `evidenciaSuficiente` (T6) recebe via `parse()` (T7). `AnexoMeta` nasce em T6 e é reexportado para o client em T9. `ParsedLancamento.dataEncontrada` (T7) é o gatilho do PDF em T12. `ResultadoProcessamento.transitorio/classe` (T12) é o que T13 lê. `FetchedEmail.labelIds` (T9) é lido em T13. `classificarErroGmail` (T8) é usado em T12 e T13.
