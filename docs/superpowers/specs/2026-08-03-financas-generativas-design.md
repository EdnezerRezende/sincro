# Sincro — Finanças Generativas

## Contexto

O Sincro é um app voltado para adultos autistas nível 1 de suporte, com foco em reduzir a carga
executiva e a ansiedade do dia a dia. Fase 1 (onboarding, anamnese, rede de apoio) e Gestão
Executiva — Triagem de E-mail estão implementadas e revisadas. O spec original
(`docs/superpowers/specs/2026-08-01-onboarding-anamnese-rede-apoio-design.md`) lista "Finanças
Generativas" como o segundo dos cinco próximos sub-projetos, com o escopo "Open Finance/DDA,
saldo livre, alertas não punitivos".

Diferente do pilar de e-mail (fatiado em fases menores), este documento cobre o pilar de Finanças
Generativas por inteiro: conexão de contas via Open Finance, cálculo de saldo livre e alertas não
punitivos de contas a vencer — decisão explícita para entregar o pilar de uma vez.

## Objetivo desta fase

Ao final desta fase, o usuário deve poder:

1. Conectar uma ou mais instituições financeiras (conta corrente/poupança e/ou cartão de
   crédito) via Open Finance, a partir de um novo card na Home.
2. Ver, nesse card e numa tela de detalhe, o **saldo livre** e a lista de contas/faturas
   conectadas.
3. Ver boletos (via DDA) e faturas de cartão a vencer.
4. Receber uma notificação push agregada e não punitiva quando alguma conta entrar na janela de
   3 dias antes do vencimento, respeitando a preferência `toleranciaNotificacao` já coletada na
   anamnese.
5. Definir/editar o "dia de recebimento" usado no cálculo do saldo livre, nas Configurações.
6. Desconectar qualquer instituição e apagar todos os dados derivados a qualquer momento.

## Fora de escopo

- Iniciação de pagamento (pagar boleto pelo app) — esta fase é somente leitura, consistente com a
  postura do app de nunca agir sem confirmação explícita.
- Categorização de gastos ou orçamento por categoria.
- Previsão de gastos recorrentes sem boleto/fatura associado (ex.: assinatura cobrada só no
  extrato, sem registro DDA).
- Diferenciação por `plano` (`simples`/`pro`) — disponível igual para todos os usuários nesta
  fase, mesma postura do pilar de e-mail de não implementar cobrança ainda.
- Dados de investimento — a Pluggy também os oferece, mas ficam de fora; só conta
  corrente/poupança e cartão de crédito.
- Suporte a agregador diferente da Pluggy.

## Arquitetura

### Conexão com Open Finance (Pluggy)

- O backend gera um **Connect Token** por sessão de conexão, chamando a API da Pluggy com
  `client_id`/`client_secret` (guardados só no backend, nunca expostos ao app) —
  `POST /financas/connect-token`.
- O app abre uma **WebView** (`webview_flutter`) carregando o widget Pluggy Connect com esse
  token, dentro de uma tela do próprio Sincro — o usuário nunca sai visualmente do app. A
  autenticação com o banco acontece inteiramente dentro do widget; o Sincro nunca vê nem
  armazena credenciais bancárias.
- Ao concluir, o widget retorna um `itemId` via callback JS dentro da WebView. O app envia esse
  `itemId` ao backend (`POST /financas/conexoes`), que busca as contas e cartões associados via
  API da Pluggy e persiste.
- **Risco conhecido:** alguns bancos bloqueiam autenticação dentro de WebView por detecção
  anti-automação. Mitigação: se a Pluggy retornar o erro específico desse tipo, a tela mostra uma
  mensagem oferecendo abrir o mesmo fluxo num navegador externo (`url_launcher`) como
  alternativa — usado só como fallback, não como caminho padrão.
- O usuário pode conectar múltiplas instituições; cada conexão vira uma linha própria e o saldo
  livre soma todas.

### Sincronização

- Endpoint `POST /financas/webhooks/pluggy` recebe eventos da Pluggy (assinatura validada via
  header), identifica o `itemId` afetado e dispara a atualização daquele item (contas, faturas,
  boletos).
- Sync sob demanda: ao abrir a tela de Finanças, o app mostra os dados em cache imediatamente e
  dispara um refresh em background (sem bloquear a tela com spinner) — consistente com a
  filosofia calma do app.
- Boletos DDA são obtidos via o produto de Boletos/DDA da Pluggy, associados ao usuário (CPF) e
  não a uma conta específica.
- **Trade-off assumido:** ao contrário do pilar de e-mail (polling periódico simples), esta fase
  usa webhook + sync sob demanda porque a Pluggy oferece webhooks nativamente e os dados
  financeiros mudam de forma mais irregular (evento no banco) do que a chegada de e-mails.
  Requer um endpoint público e tratamento de eventos fora de ordem/duplicados (idempotência por
  `itemId` + timestamp do evento).

### Cálculo do saldo livre

Recalculado a cada leitura (`GET /financas/resumo`), nunca armazenado:

```
saldo_livre = Σ(saldo das contas corrente/poupança conectadas)
              − Σ(faturas de cartão de crédito abertas)
              − Σ(boletos DDA com vencimento dentro do ciclo atual)

ciclo atual = hoje → próxima ocorrência de usuarios.dia_recebimento
              (se não definido, assume o último dia do mês corrente)
```

`dia_recebimento` (1–31, opcional) é perguntado de forma simples ao conectar a primeira conta
("em que dia do mês você costuma receber?"), e editável depois em Configurações.

## Modelo de dados

```sql
ALTER TABLE usuarios ADD COLUMN dia_recebimento INT;

CREATE TABLE conexoes_financeiras (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES usuarios(id),
  pluggy_item_id VARCHAR(100) NOT NULL,
  instituicao VARCHAR(255) NOT NULL,
  status VARCHAR(20) NOT NULL, -- 'ATIVA' | 'ERRO' | 'AGUARDANDO_CREDENCIAIS'
  criado_em TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, pluggy_item_id)
);

CREATE TABLE contas_financeiras (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conexao_id UUID NOT NULL REFERENCES conexoes_financeiras(id),
  pluggy_account_id VARCHAR(100) NOT NULL,
  tipo VARCHAR(20) NOT NULL, -- 'CORRENTE' | 'POUPANCA' | 'CARTAO_CREDITO'
  nome VARCHAR(255) NOT NULL,
  saldo_ou_fatura NUMERIC(14, 2) NOT NULL,
  vencimento_fatura DATE, -- só para 'CARTAO_CREDITO'
  notificado_em TIMESTAMPTZ, -- só para 'CARTAO_CREDITO'
  atualizado_em TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (conexao_id, pluggy_account_id)
);

CREATE TABLE boletos_dda (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES usuarios(id),
  codigo_barras VARCHAR(100) NOT NULL,
  valor NUMERIC(14, 2) NOT NULL,
  vencimento DATE NOT NULL,
  pago BOOLEAN NOT NULL DEFAULT false,
  notificado_em TIMESTAMPTZ,
  criado_em TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, codigo_barras)
);
```

`vencimento_fatura`/`notificado_em` marcam, respectivamente, quando uma fatura de cartão vence e
quando um item já disparou alerta — evitando notificação duplicada.

## Alertas não punitivos

- Um job diário (`@nestjs/schedule`, mesmo mecanismo do pilar de e-mail) varre `boletos_dda` e
  faturas de cartão (`contas_financeiras` com `tipo = 'CARTAO_CREDITO'`) com vencimento nos
  **próximos 3 dias** e `notificado_em` nulo.
- Se houver algum item nessa janela, dispara **uma única notificação agregada** via Firebase
  Cloud Messaging (ex.: "Você tem 2 contas vencendo nos próximos dias") — nunca uma por item.
- Respeita `dados.toleranciaNotificacao` do perfil sensorial, mesmo comportamento do pilar de
  e-mail:
  - `SILENCIOSAS` → nunca envia push; o resumo fica disponível só ao abrir o app.
  - `HORARIO_ESPECIFICO` → só envia dentro da janela configurada.
  - `PADRAO` → envia assim que o job encontrar algo novo.
- **Tom não punitivo:** sem cor de alarme/vermelho como padrão visual, sem linguagem de cobrança
  ("atrasado!", "urgente!"); itens já vencidos aparecem como "venceu há X dias", informativo, não
  destacado como erro.
- Cada item marca `notificado_em` ao entrar no alerta, para não repetir.

## Mobile: UI

- **Home:** novo card "💰 Finanças":
  - Se nenhuma instituição conectada: CTA "Conectar conta".
  - Se conectado: saldo livre em destaque, navegando para a tela de detalhe.
- **Tela de detalhe** (`/financas`, nova): saldo livre no topo, lista de contas/cartões
  conectados com saldo/fatura, lista de boletos e faturas a vencer ordenada por data. Pull-to-
  refresh dispara sync sob demanda. Sem ações de pagamento nesta fase — somente leitura.
- **Configurações:** campo para definir/editar `dia_recebimento`, e opção de desconectar cada
  instituição individualmente, com confirmação antes (mesmo padrão de apagar perfil
  sensorial/contato/Gmail).

## Segurança e LGPD

- O backend nunca recebe credenciais bancárias — tratadas inteiramente dentro do widget Pluggy
  Connect.
- Nenhum dado de cartão (número, CVV) é armazenado; a Pluggy não os retorna via Open Finance.
- O webhook valida a assinatura da Pluggy para impedir gatilhos de sync forjados.
- Tenant isolation: todo acesso a `conexoes_financeiras`/`contas_financeiras`/`boletos_dda`
  escopado por `user_id` resolvido do token Firebase verificado, nunca de um parâmetro vindo do
  client — mesmo padrão da Fase 1 e do pilar de e-mail.
- **Direito de exclusão:** `DELETE /financas/conexoes/:id` chama a API da Pluggy para deletar o
  item correspondente e apaga todas as linhas derivadas (`contas_financeiras`,
  `conexoes_financeiras`) daquela conexão. Desconectar a última instituição também remove os
  `boletos_dda` do usuário, já que eles não pertencem a uma conexão específica (ligados ao CPF
  via DDA).

## Testes

- **Backend:**
  - Unitário: cálculo de saldo livre (múltiplas contas, fronteiras do ciclo — dia de recebimento
    já passou no mês / ainda não chegou / não definido); validação de assinatura do webhook.
  - Tenant isolation: teste garantindo que sync e alertas nunca misturam dados entre usuários.
- **Mobile:** testes de repositório (fake Dio adapter, mesmo padrão da Fase 1) para o card da
  Home e a tela de detalhe.
- **E2E:** um teste cobrindo conectar instituição (cliente Pluggy mockado) → webhook de sync
  (mockado) → saldo livre disponível via `GET /financas/resumo` → desconexão apagando todos os
  dados, seguindo o padrão de `backend/test/onboarding-flow.e2e-spec.ts`.
