# Sincro — Gestão Executiva: Triagem de E-mail (Fase 1 deste pilar)

## Contexto

O Sincro é um app voltado para adultos autistas nível 1 de suporte, com foco em reduzir a carga
executiva e a ansiedade do dia a dia. A Fase 1 (onboarding, anamnese, rede de apoio) está
implementada e revisada. O spec original (`docs/superpowers/specs/2026-08-01-onboarding-anamnese-rede-apoio-design.md`)
lista "Gestão Executiva (e-mails/agenda)" como o primeiro dos cinco próximos sub-projetos.

Este documento especifica **apenas a primeira fatia** desse pilar: conectar o Gmail e mostrar um
resumo calmo da caixa de entrada. Geração de rascunhos de resposta e extração de compromissos
para a agenda ficam para iterações futuras deste mesmo pilar, cada uma com seu próprio ciclo
spec → plano → implementação.

## Objetivo desta fase

Ao final desta fase, o usuário deve poder:

1. Conectar sua conta Gmail a partir de um novo card na Home.
2. Ver, nesse card e numa tela de detalhe, quantos e-mails "precisam de atenção" vs. "podem
   esperar" — sem precisar abrir o Gmail.
3. Receber uma notificação push agregada (nunca uma por e-mail) quando houver algo novo que
   precise de atenção, respeitando a preferência de notificação já coletada na anamnese.
4. Desconectar o Gmail e apagar todos os dados derivados a qualquer momento.

## Fora de escopo

- Geração de rascunhos de resposta por IA.
- Extração de compromissos/eventos para a agenda.
- Suporte a Outlook/Microsoft Graph API (fica para uma iteração futura, reaproveitando a mesma
  arquitetura de classificação plugável).
- Qualquer ação de enviar, arquivar, marcar como lido ou modificar e-mails no Gmail em si — esta
  fase é somente leitura.
- Sistema de pagamento/checkout para o plano "pro". O campo `plano` existe para permitir a
  diferenciação de classificação, mas não há fluxo de compra, upgrade ou downgrade nesta fase.
- Fila de jobs dedicada (BullMQ/Redis) — a sincronização em background roda no processo do
  próprio backend via `@nestjs/schedule`, consistente com a postura da Fase 1 de não otimizar
  para escala antes de ter uma base de usuários que justifique.

## Planos: simples vs. pro

O Sincro pretende oferecer um plano gratuito ("simples") e um plano pago ("pro"). Esta fase
**não** implementa cobrança — apenas prepara o terreno:

- Novo campo `usuarios.plano` (`VARCHAR`, default `'simples'`), ajustável manualmente por ora
  (sem UI de upgrade).
- A classificação de e-mail é implementada atrás de uma interface (`EmailClassifier`), com duas
  implementações concretas selecionadas pelo `plano` do usuário — ver seção "Classificação".

## Arquitetura

### Conexão com o Gmail

A conexão com o Gmail é uma autorização OAuth2 do Google **separada** do login do Sincro (que
continua sendo Firebase Auth por e-mail/senha). O usuário já autenticado no app conecta o Gmail
a partir de um botão "Conectar Gmail" no novo card da Home.

- **Escopo solicitado:** `gmail.readonly` apenas — least privilege, sem permissão de enviar ou
  modificar. Consistente com o app nunca agir sem confirmação do usuário (mesmo princípio do
  botão de emergência da Fase 1).
- **Fluxo mobile:** o app usa o pacote `google_sign_in` do Flutter apenas para obter o
  authorization code do consentimento OAuth. O **backend** troca esse code pelos tokens
  (`access_token`/`refresh_token`) via `googleapis` e é o único lugar que fala com a Gmail API —
  o app nunca guarda nem usa tokens do Google diretamente.
- **Armazenamento:** o `refresh_token` é criptografado em repouso (`pgcrypto`, mesmo padrão
  previsto para colunas sensíveis no spec da Fase 1) e guardado em `conexoes_gmail`, escopado por
  `user_id`.
- **Revogação:** ao desconectar, o backend revoga o token junto ao Google
  (`POST https://oauth2.googleapis.com/revoke`) além de apagar os dados locais — não é só um
  soft-delete.

### Sincronização em background

- `@nestjs/schedule` (`@Cron`) roda a cada 15–30 minutos, iterando todos os usuários com Gmail
  conectado.
- Sincronização **incremental** via `users.history.list` da Gmail API, usando o `last_history_id`
  salvo por conexão — evita reprocessar a caixa inteira a cada ciclo. Na primeira conexão (sem
  `historyId` ainda), faz uma busca inicial limitada aos e-mails não lidos dos últimos 7 dias,
  com um teto de 50 mensagens, em vez de importar o histórico completo.
- Se o `historyId` salvo estiver expirado/inválido (a Gmail API pode invalidar após ~7 dias sem
  sync), o serviço detecta o erro específico da API e refaz uma busca inicial, sem falhar
  silenciosamente.
- Cada mensagem nova passa pelo `EmailClassifier` correspondente ao `plano` do usuário e gera um
  registro em `resumos_email` — o corpo do e-mail nunca é persistido, só passa em memória durante
  a classificação.
- **Trade-off assumido:** rodar em processo (não numa fila dedicada) não escala horizontalmente
  nem tem retry/backoff automático. Aceitável para o tamanho atual do projeto; a lógica de
  negócio (sync, classificação, notificação) fica isolada da camada de disparo, então trocar para
  uma fila depois não exige reescrever nada, só trocar o que aciona `EmailSyncService`.

### Classificação plugável

```typescript
interface EmailClassifier {
  classify(email: { remetente: string; assunto: string; corpo: string }): Promise<{
    categoria: 'PRECISA_ATENCAO' | 'PODE_ESPERAR';
    resumoCurto: string;
  }>;
}
```

- **`HeuristicEmailClassifier`** (plano `simples`): regras diretas — não lido + remetente
  conhecido/prioritário + palavras-chave (ex.: "urgente", "prazo", "vencimento") → categoria.
  `resumoCurto` é uma versão truncada do assunto, sem geração de texto.
- **`LlmEmailClassifier`** (plano `pro`): chama um modelo de linguagem passando o e-mail e o
  `dados.tomPreferido` do perfil sensorial do usuário (já coletado na anamnese via
  `SensoryProfileService`), retornando categoria e um resumo real gerado, no tom preferido do
  usuário.
- A escolha de qual implementação usar é feita no serviço de sync, lendo `usuarios.plano`.

## Modelo de dados

```sql
CREATE TABLE conexoes_gmail (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES usuarios(id) UNIQUE,
  refresh_token_criptografado TEXT NOT NULL,
  gmail_email VARCHAR(255) NOT NULL,
  last_history_id VARCHAR(50),
  ultima_sincronizacao TIMESTAMPTZ,
  criado_em TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE resumos_email (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES usuarios(id),
  gmail_message_id VARCHAR(100) NOT NULL,
  remetente VARCHAR(255) NOT NULL,
  assunto VARCHAR(500) NOT NULL,
  resumo_curto TEXT NOT NULL,
  categoria VARCHAR(20) NOT NULL, -- 'PRECISA_ATENCAO' | 'PODE_ESPERAR'
  recebido_em TIMESTAMPTZ NOT NULL,
  lido_no_app BOOLEAN NOT NULL DEFAULT false,
  criado_em TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, gmail_message_id)
);

ALTER TABLE usuarios ADD COLUMN plano VARCHAR(20) NOT NULL DEFAULT 'simples';
```

`resumo_curto` e `categoria` são o único derivado do conteúdo do e-mail que o Sincro guarda — o
corpo original nunca toca o banco.

## Notificações

- Ao fim de cada ciclo de sync, se houver ao menos um e-mail novo classificado como
  `PRECISA_ATENCAO`, o backend dispara **uma única notificação agregada** via Firebase Cloud
  Messaging (ex.: "3 e-mails precisam da sua atenção") — nunca uma notificação por e-mail.
- Respeita `dados.toleranciaNotificacao` do perfil sensorial (já coletado na anamnese):
  - `SILENCIOSAS` → nunca envia push; o resumo só aparece quando o usuário abrir o app.
  - `HORARIO_ESPECIFICO` → só envia push dentro da janela configurada; fora dela, o resumo fica
    disponível no app mas sem push.
  - `PADRAO` → envia push assim que o ciclo de sync encontrar algo novo.
- Requer registrar o token FCM do device: novo endpoint `POST /users/me/fcm-token`. O backend já
  tem o `firebase-admin` SDK desde a Fase 1 (usado para verificar tokens de auth); esta fase
  passa a usar também o módulo de messaging do mesmo SDK.

## Mobile: UI

- **Home:** o placeholder "Finanças e e-mails chegam em breve" (Task 14 da Fase 1) vira um card
  "📬 Caixa de Entrada":
  - Se não conectado: CTA "Conectar Gmail".
  - Se conectado: contagem de e-mails que precisam de atenção, navegando para a tela de resumo.
- **Tela de resumo** (`/inbox`, nova): lista os `resumos_email` mais recentes, agrupados por
  categoria (precisa de atenção primeiro), com pull-to-refresh para sincronizar sob demanda além
  do ciclo em background. Sem ações de responder/arquivar nesta fase — somente leitura.
- **Desconectar:** opção nas Configurações (tela criada na Task 15 da Fase 1) para desconectar o
  Gmail, com confirmação antes (mesmo padrão de apagar perfil sensorial/contato).

## Segurança e LGPD

- `refresh_token_criptografado`: criptografado em repouso via `pgcrypto`.
- Escopo mínimo: `gmail.readonly` apenas.
- Nenhum corpo de e-mail é persistido — só metadados derivados em `resumos_email`.
- Tenant isolation: todo acesso a `conexoes_gmail`/`resumos_email` escopado por `user_id`
  resolvido do token Firebase verificado, nunca de um parâmetro vindo do client — mesmo padrão
  aplicado em toda a Fase 1.
- **Direito de exclusão:** `DELETE /gmail-connection` apaga a conexão e todos os `resumos_email`
  do usuário, e revoga o token junto ao Google.

## Testes

- **Backend:**
  - Unitário: `HeuristicEmailClassifier` (determinístico, sem mocks externos);
    `LlmEmailClassifier` (mock do provedor de IA); `EmailSyncService` (mock da Gmail API,
    cobrindo sync incremental, primeira conexão, e `historyId` inválido).
  - Tenant isolation: teste garantindo que o ciclo de sync nunca mistura dados entre usuários.
- **Mobile:** testes de repositório (fake Dio adapter, mesmo padrão da Fase 1) para o card da
  Home e a tela de resumo.
- **E2E:** um teste cobrindo conectar Gmail (mockado) → ciclo de sync (mockado) → resumo
  disponível via `GET /resumos-email`, seguindo o padrão de
  `backend/test/onboarding-flow.e2e-spec.ts`.
