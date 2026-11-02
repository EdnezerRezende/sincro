# Checklist: Sincro na Google Play

Gerado a partir da versão interativa. Legenda: **Você**, **Claude** (eu faço no código) ou **Juntos**.

## Fase de teste

Objetivo: app na Google Play em teste, com todas as funções funcionando para os testadores e build/deploy automáticos.

### Já feito

- [x] **Claude**: Anúncios AdMob atrás de feature toggle, desligados por padrão
- [x] **Claude**: Política de privacidade e página de exclusão de conta publicadas no build web  
  privacidade.html, excluir-conta.html, app-ads.txt
- [x] **Claude**: Botão "Excluir conta" no app  
  Feito em outra sessão (commit 45f54a2).
- [x] **Claude**: Nome do app no celular trocado de "sincro_mobile" para "Sincro" (Android e iOS)
- [x] **Claude**: Script de release gera também o .aab para a Play  
  ./scripts/release-firebase.sh -b patch --aab --dry-run
- [x] **Claude**: Textos da ficha da loja e justificativas das permissões  
  docs/play-store/ficha-da-loja.md
- [x] **Você**: AdMob: pagamentos, mensagens de consentimento e limite de frequência
- [x] **Você**: Play Console: declarações de anúncios e ID de publicidade

### 1. Servidor (sandbox)

- [x] **Você**: Rodar ./deploy.sh na VPS com a master atual  
  Feito pelo deploy automático, que agora roda a cada merge na master.
- [x] **Você**: Abrir no navegador /privacidade.html, /excluir-conta.html e /app-ads.txt  
  O deploy automático confere as três a cada execução.
- [x] **Você**: Confirmar que o backup diário do Postgres está no cron da VPS  
  Confirmado em 01/11: dumps diários às 03:00 em infra/backups, 7 dias de retenção.  
  crontab -l deve listar infra/backup-postgres.sh. No plano do sandbox essa tarefa ainda aparece como pendente.
- [x] **Você**: Ligar ADS_ENABLED=true no backend/.env da VPS e recriar o backend (decidido em 01/11: monetização já na fase de teste)  
  Feito em 01/11, com o celular do Ednezer cadastrado como dispositivo de teste. Cada novo testador precisa ser cadastrado também.  
  Só liga depois da aprovação do AdMob (fase de produção).

### 2. Conta e app na Play Console

- [x] **Você**: Conferir o tipo da conta de desenvolvedor  
  Conta pessoal (ID 7942397505800602815): a produção só libera depois do teste fechado com 12 testadores por 14 dias.
- [ ] **Você**: Criar o app: nome "Sincro: rotina e bem-estar", idioma pt-BR, app gratuito
- [ ] **Você**: Ativar a Assinatura de apps do Google Play (Play App Signing)  
  Padrão para apps novos. A chave do seu Mac vira a chave de upload.
- [ ] **Você**: Copiar as impressões digitais SHA-1 e SHA-256 da chave de assinatura do app  
  Play Console → Teste e lançamento → Configuração → Integridade do app → Assinatura de apps.
- [ ] **Você**: Adicionar essas impressões no Firebase (Configurações do projeto → app Android)  
  Sem isso o login com Google e a conexão do Gmail falham no app baixado da loja (erro 10).
- [ ] **Claude**: Atualizar o google-services.json no repositório  
  Depois do passo anterior, baixe o arquivo novo e me envie.

### 3. Ficha da loja e Conteúdo do app

- [ ] **Você**: Colar os textos da ficha principal  
  docs/play-store/ficha-da-loja.md
- [ ] **Juntos**: Imagem de destaque 1024×500  
  Posso gerar uma a partir da identidade visual do app.
- [ ] **Você**: Tirar de 2 a 8 capturas de tela do celular  
  Sugestão: Home, Caixa de Entrada, Finanças, Biofeedback, Cartões, Emergência. Use uma conta de teste com dados fictícios.
- [x] **Você**: Criar uma conta de teste para o revisor do Google e informar em Acesso ao app  
  Conta criada; o onboarding fica para o revisor fazer (ele pode preencher anamnese e contato, só não pode criar conta).
- [x] **Você**: Preencher: política de privacidade, segurança dos dados, exclusão de dados  
  Feito na sessão de 24–29/09. Ao ligar os anúncios ou o WhatsApp, revisar a Segurança dos dados.  
  URLs e tabela prontas no ficha-da-loja.md.
- [x] **Você**: Preencher: classificação etária, público-alvo (18+), recursos financeiros, apps de saúde  
  Classificação: Conteúdo online = Sim (IA). Recursos financeiros: "não oferece". Saúde: estresse/relaxamento, saúde mental, emergência, serviços de saúde.
- [ ] **Você**: Preencher a declaração de permissões do Health Connect  
  Justificativas prontas no ficha-da-loja.md.
- [x] **Claude**: Garantir que a tela de justificativa do Health Connect abre a política de privacidade  
  PrivacyPolicyActivity abre /privacidade.html no Android 13- (ACTION_SHOW_PERMISSIONS_RATIONALE) e 14+ (alias). Falta testar num aparelho com Health Connect.

### 4. Gmail e Google Cloud

- [ ] **Você**: Tela de consentimento OAuth em modo Teste, com o e-mail de cada testador cadastrado  
  Em modo Teste, só até 100 usuários cadastrados conseguem conectar o Gmail.
- [ ] **Você**: Adicionar o domínio do sandbox em Domínios autorizados

### 5. Primeira versão em teste

- [ ] **Você**: Gerar o AAB: ./scripts/release-firebase.sh -b patch --aab --dry-run  
  O arquivo sai em mobile/build/app/outputs/bundle/release/app-release.aab
- [ ] **Você**: Enviar para Teste interno e adicionar os testadores (até 100, sem revisão demorada)
- [ ] **Você**: Teste fechado com 12 testadores por 14 dias (obrigatório na conta pessoal)  
  Faixa alpha no workflow Android release. Depois, Painel da Play Console → Solicitar acesso à produção.
- [ ] **Você**: Ler o Relatório de pré-lançamento da Play e me mandar os erros

### 6. Build e deploy automáticos

- [x] **Claude**: CI no GitHub Actions: lint e testes do backend e do app a cada PR  
  .github/workflows/ci.yml
- [x] **Claude**: Corrigir os testes que estavam quebrados na master  
  7 no backend e 10 no app.
- [x] **Claude**: Deploy automático do backend e do app web na VPS a cada merge na master  
  .github/workflows/deploy-sandbox.yml, com verificação em /api/health
- [x] **Você**: Criar a chave de deploy e os segredos no environment sandbox do GitHub  
  Passo a passo em docs/deploy/deploy-automatico.md. Depois, rodar Actions → Deploy sandbox → Run workflow.
- [x] **Claude**: Build Android automático: AAB para o Teste interno da Play e APK para o Firebase  
  .github/workflows/android-release.yml
- [ ] **Você**: Criar os segredos de assinatura e as contas de serviço (Firebase e Play) no environment android-release  
  Passo a passo em docs/deploy/build-android.md. A conta de serviço da Play só depois do primeiro AAB enviado à mão.
- [x] **Claude**: Reativar o Sentry no app  
  sentry_flutter 10.2 (Flutter 3.47), sem PII. O build da Play usa a variável `SENTRY_DSN_MOBILE` do environment android-release.
- [ ] **Você**: Criar o projeto Flutter no Sentry e salvar o DSN em `SENTRY_DSN_MOBILE` (Variables do environment android-release)
- [ ] **Você**: Segurança dos dados: marcar Registros de falhas e Diagnóstico (coletados, não compartilhados, finalidade Análise)

### 4.1 WhatsApp (bloqueado pela Meta, não bloqueia a Play)

- [x] **Claude**: Vínculo do número, webhook e tela no app  
  Separado no branch local `feat/whatsapp` (commit bd5e5b8), fora da master: a linha em Configurações não tinha trava e quebraria a revisão.
- [ ] **Você**: Aguardar a verificação da empresa na Central de Segurança da Meta (Business ID 1444556850028550)
- [ ] **Você**: Gerar número de teste e token de usuário de sistema; preencher as `WHATSAPP_*` no .env da VPS
- [ ] **Claude**: Esconder a linha "Finanças pelo WhatsApp" atrás de feature flag e trazer o branch para a master
- [ ] **Juntos**: Registrar o webhook `/api/whatsapp/webhook`, assinar `messages` e rodar `backend/scripts/smoke-whatsapp.cjs`
- [ ] **Você**: Atualizar a Segurança dos dados (Número de telefone, Outras mensagens) ao publicar o recurso
- [ ] **Claude**: Rodar no Figma `06_assets/sincro/figma_sincro_whatsapp_2026-09-24.js` (vault) para as telas do WhatsApp

## Fase de produção

Para abrir o app ao público. Nada disso bloqueia a fase de teste.

### 7. Infraestrutura

- [ ] **Você**: Registrar um domínio próprio (ex.: sincro.app.br)  
  Substitui o duckdns nas URLs da loja, do AdMob, do OAuth e na API_BASE_URL.
- [ ] **Juntos**: Ambiente de produção separado do sandbox  
  Banco, .env e segredos próprios. Hoje o banco se chama sincro_dev.
- [ ] **Claude**: Separar sandbox e produção no app (flavors com IDs de pacote diferentes)  
  Permite ter os dois instalados e evita testador escrevendo em produção.
- [ ] **Juntos**: Backups fora da VPS (OCI Object Storage) e um teste de restauração  
  Hoje o backup fica na mesma máquina.
- [ ] **Você**: Monitor de disponibilidade (ex.: UptimeRobot) e Sentry com DSN de produção
- [ ] **Você**: Chaves de produção da Anthropic e da OpenAI, com limite de gasto

### 8. Google e jurídico

- [ ] **Você**: Pedir a verificação do app no Google Cloud (escopos restritos do Gmail)  
  Inclui vídeo de demonstração e avaliação de segurança CASA, paga e renovada todo ano. Leva semanas; comece cedo.
- [ ] **Claude**: Escrever os Termos de Uso  
  O app ainda não tem.
- [ ] **Você**: Revisão jurídica da política de privacidade e dos termos

### 9. Lançamento

- [ ] **Você**: Publicar em produção com lançamento gradual (20%, 50%, 100%)
- [ ] **Você**: Vincular o app à loja no AdMob e aguardar a aprovação
- [ ] **Você**: Ligar ADS_ENABLED=true no .env de produção
- [ ] **Claude**: Automatizar a promoção do Teste interno para produção, com aprovação manual
- [ ] **Você**: Acompanhar Android vitals, avaliações e o painel do AdMob na primeira semana

### 10. Depois (opcional)

- [ ] **Juntos**: Plano pago sem anúncios com Google Play Billing  
  O backend já trata ADS_FREE_PLANS.
- [ ] **Juntos**: Versão iOS: conta Apple Developer, HealthKit, App Store
