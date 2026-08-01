# Sincro — Onboarding, Anamnese e Rede de Apoio (Fase 1)

## Contexto

O Sincro é um app voltado para adultos autistas nível 1 de suporte, com foco em reduzir a carga
executiva e a ansiedade do dia a dia em cinco frentes: gestão de e-mails/agenda, finanças
generativas, biofeedback via smartwatch, conexão com profissionais de saúde mental e rede de
apoio, e comunidade/alívio sensorial. A base de pesquisa está em
`docs/App para Autistas_ Finanças e Bem-Estar.pdf`.

Esses cinco pilares são subsistemas independentes, cada um com integrações externas próprias
(Gmail/Graph API, Open Finance, HealthKit/Health Connect, diretório de profissionais). Este
documento especifica **apenas o primeiro sub-projeto**: a base de identidade, perfil sensorial e
rede de contatos de confiança que os demais pilares vão consumir.

## Objetivo desta fase

Ao final desta fase, o app deve permitir que o usuário:

1. Crie uma conta e faça login (Firebase Authentication).
2. Preencha um perfil sensorial/executivo curto via wizard de múltipla escolha.
3. Cadastre contatos de confiança (familiares e/ou profissionais que já possui) com consentimento
   explícito para receberem alertas.
4. Use o botão "Avisar Rede de Apoio", que prepara uma mensagem e abre o WhatsApp para envio.
5. Edite ou apague seu perfil sensorial e seus contatos a qualquer momento.

## Fora de escopo

Os itens abaixo pertencem a sub-projetos futuros e não são implementados nesta fase:

- Gestão de e-mails e agenda (leitura de Gmail/Outlook, rascunhos de resposta via IA).
- Finanças generativas (Open Finance, DDA, alertas de contas, saldo livre).
- Biofeedback via smartwatch (HR/VFC, detecção de estresse, filtragem de atividade física).
- Busca/recomendação de profissionais por geolocalização (a "Rede de Apoio" desta fase é limitada
  a cadastro manual de contatos que o usuário já possui).
- Comunidade e conteúdo de alívio sensorial (grounding cards, peer support).

## Stack técnica

| Camada | Escolha |
|---|---|
| App mobile | Flutter (iOS/Android) |
| Backend/API | Node.js com NestJS |
| Autenticação | Firebase Authentication |
| Banco de dados | PostgreSQL com extensão `pgvector` (hospedagem definida na fase de plano técnico — candidatos: Neon ou Postgres do Supabase usado apenas como banco) |
| Isolamento de tenant | Garantido na camada de aplicação (não há RLS nativo, já que a autenticação é externa ao Postgres) |

### Integração Firebase Auth + Postgres

O Firebase Auth é responsável apenas por identidade (login social, e-mail/senha, telefone, MFA).
O NestJS valida o ID token do Firebase em cada requisição via `firebase-admin` SDK e extrai o
`firebase_uid`. Esse UID é a chave de ligação com a tabela `usuarios` no Postgres. Nenhum dado de
negócio fica no Firebase — tudo vive no Postgres.

**Isolamento de tenant:** um `AuthGuard` do NestJS injeta o `user_id` (derivado do token validado)
no contexto da requisição. Os repositórios recebem esse `user_id` por injeção de dependência e o
utilizam em toda cláusula `WHERE` — o valor nunca é lido de parâmetros vindos do client (body,
query string ou params de rota), eliminando a possibilidade de um usuário acessar dados de outro
por manipulação de request.

## Fluxo de onboarding

```
[Cadastro/Login (Firebase)] → [Anamnese Wizard] → [Cadastro Rede de Confiança] → [Tela Home provisória]
```

A "Tela Home provisória" é uma tela de boas-vindas com o botão de emergência já funcional. As
seções HOJE/FINANÇAS aparecem como placeholder "em breve", pois pertencem a fases futuras.

## Anamnese Wizard

Formulário curto por etapas, com no máximo 2-3 perguntas por tela, todas de clique único
(botões/chips/sliders) — sem texto livre obrigatório em nenhuma etapa.

**Etapa 1 — Perfil de Notificação**
- Tolerância a notificações: `Silenciosas` / `Só em horários específicos` / `Padrão`.
- Se "horários específicos": seletor de faixa (ex.: 8h–20h).

**Etapa 2 — Gatilhos Conhecidos**
- Chips selecionáveis com gatilhos comuns pré-definidos (ex.: "Abrir o app do banco", "Ligações
  não agendadas", "Mudança de última hora na agenda", "Ambientes barulhentos").
- Campo opcional de texto curto: "Outro gatilho (opcional)".

**Etapa 3 — Estilo de Comunicação Preferido**
- Tom das mensagens: `Direto e curto` / `Levemente mais explicativo`. Esse valor alimenta o tom
  que os pilares futuros (finanças, e-mails) usarão para gerar mensagens da IA.

**Etapa 4 — Resumo e Confirmação**
- Revisão de todas as seleções, com opção de voltar e editar qualquer etapa antes de confirmar.

O resultado é armazenado como um registro `perfis_sensoriais` (JSONB) vinculado ao `user_id`, e
não como colunas rígidas por campo — essas preferências vão crescer conforme os pilares futuros
(ex.: limiares de estresse do smartwatch) reaproveitem o mesmo registro. O campo `versao` permite
evoluir o schema interno do JSONB sem migration a cada novo campo.

## Rede de Apoio

**Cadastro de contato:**

| Campo | Descrição |
|---|---|
| Nome | Nome do contato |
| Relação | `Psicólogo` / `Psiquiatra` / `T.O.` / `Familiar` / `Outro` |
| WhatsApp | Número de telefone |
| Prioridade | Ordem de exibição no acionamento de emergência |

- Não há limite rígido de contatos, mas a UI destaca até 3 como "prioritários".
- O botão de emergência funciona sem contatos cadastrados, mas exibe um aviso discreto e
  persistente incentivando o cadastro de ao menos 1 contato.

**Consentimento explícito (LGPD):** ao cadastrar cada contato, o app exibe o texto: *"Você
autoriza o Sincro a preparar mensagens de alerta para [Nome] em momentos de crise. Você sempre
confirma antes do envio."* — checkbox obrigatório por contato, com timestamp de aceite
(`consentimento_aceito_em`) armazenado.

**Fluxo do botão "Avisar Rede de Apoio":**

```
[Botão "Avisar Rede de Apoio"] → [Escolher contato prioritário] → [Mensagem pré-preenchida exibida,
editável] → [Abrir WhatsApp (wa.me) com o texto] → [Usuário confirma envio dentro do próprio WhatsApp]
```

Mensagem padrão (editável antes do envio): *"Oi [Nome], estou passando por um momento difícil
agora e queria avisar. Não precisa ligar se não for possível."* O envio é feito via link `wa.me`
— o app nunca envia mensagens automaticamente sem confirmação do usuário dentro do próprio
WhatsApp, e não depende de aprovação de conta business/API paga.

## Modelo de dados

```sql
CREATE TABLE usuarios (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  firebase_uid VARCHAR(128) UNIQUE NOT NULL,
  nome VARCHAR(100) NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE perfis_sensoriais (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES usuarios(id),
  dados JSONB NOT NULL,          -- tolerância de notificação, gatilhos, tom preferido
  versao INT DEFAULT 1,          -- permite evoluir o schema sem migration por campo
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE contatos_confianca (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES usuarios(id),
  nome VARCHAR(100) NOT NULL,
  relacao VARCHAR(30) NOT NULL,   -- 'PSICOLOGO','PSIQUIATRA','T.O.','FAMILIAR','OUTRO'
  whatsapp VARCHAR(20) NOT NULL,
  prioridade INT DEFAULT 0,
  consentimento_aceito_em TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);
```

## Segurança e LGPD

- **Criptografia em repouso** para colunas sensíveis (perfil sensorial, contatos de saúde) via
  `pgcrypto` no Postgres, ou criptografia gerenciada pelo provedor de hospedagem quando escolhido
  na fase de plano técnico.
- **Base legal de consentimento:** tela de consentimento geral no onboarding (uso de dados
  pessoais e de saúde sensíveis, conforme LGPD) + consentimento específico por contato de
  confiança.
- **Direito de exclusão:** endpoint para o usuário apagar perfil sensorial e contatos a qualquer
  momento.
- **Escopo mínimo de dados:** nenhuma informação de negócio é armazenada no Firebase; o Postgres
  guarda apenas o necessário para os fluxos descritos aqui.

## Testes

- Testes unitários nos serviços NestJS (validação de anamnese, regras de consentimento).
- Testes de integração cobrindo o fluxo completo via API: onboarding → anamnese → cadastro de
  contato → geração da mensagem de emergência.
- Testes de widget no Flutter para o wizard (navegação entre etapas, validação de campos
  obrigatórios).
- Fora de escopo nesta fase: testes de carga (base de usuários ainda pequena).

## Próximos sub-projetos (fora desta spec)

1. Gestão Executiva (e-mails/agenda) — Gmail/Graph API, rascunhos gerados por IA, extração de
   compromissos.
2. Finanças Generativas — Open Finance/DDA, saldo livre, alertas não punitivos.
3. Biofeedback & Crise — integração com smartwatch (HealthKit/Health Connect), filtragem de
   falsos positivos, alertas de descompressão.
4. Conexão Profissional — busca/recomendação de profissionais neuroafirmativos por geolocalização.
5. Comunidade & Alívio Sensorial — grounding cards, peer support, conteúdo validado pela
   comunidade.

Cada um desses pilares deve passar pelo próprio ciclo de spec → plano → implementação.
