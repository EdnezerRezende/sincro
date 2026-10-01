# Build Android automático

Workflow: `.github/workflows/android-release.yml` (GitHub → Actions → **Android release**).

| Quando | O que acontece |
|---|---|
| Merge na `master` que mexe em `mobile/`, depois do CI verde | Gera AAB e APK assinados, envia o APK aos testadores do Firebase e o AAB à faixa **Teste interno** da Play |
| **Run workflow** (manual) | O mesmo, escolhendo a faixa da Play (`internal`, `alpha` = teste fechado, `beta` = teste aberto, `production`) e se envia ao Firebase |

Cada destino só é usado quando os segredos dele existem. AAB e APK sempre ficam disponíveis para
baixar na página da execução (seção *Artifacts*, por 30 dias).

**Versão:** o `versionName` vem do `pubspec.yaml` (ex.: `1.0.14`) e o `versionCode` é
`1000 + número da execução`. Depois de começar a usar o workflow, não envie à Play um AAB gerado
no Mac com `release-firebase.sh`: o código dele seria menor e a Play recusaria.

---

## Configuração

Tudo em GitHub → **Settings** → **Environments** → **New environment** → nome `android-release`.

### 1. Assinatura (obrigatório)

Use a mesma chave que o `release-firebase.sh` já usa no seu Mac. No terminal, dentro do
repositório:

```bash
cd mobile/android
cat key.properties                         # mostra as senhas e o alias
base64 -i app/release-key.jks | pbcopy     # copia o keystore em base64
```

| Secret | Valor |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | o que o `base64 ... \| pbcopy` copiou (cole com Cmd+V) |
| `ANDROID_KEYSTORE_PASSWORD` | `storePassword` do `key.properties` |
| `ANDROID_KEY_PASSWORD` | `keyPassword` do `key.properties` |
| `ANDROID_KEY_ALIAS` | `keyAlias` do `key.properties` |

⚠️ Guarde uma cópia do `release-key.jks` e das senhas fora do Mac (por exemplo, num gerenciador
de senhas). Com a Assinatura de apps do Google Play ela vira só a chave de *upload* e pode ser
trocada pelo suporte se for perdida, mas o processo leva dias.

Só com estes 4 segredos o workflow já gera AAB e APK assinados para baixar.

### 2. Firebase App Distribution (opcional)

Substitui o `firebase login` do seu Mac por uma conta de serviço.

1. [console.cloud.google.com](https://console.cloud.google.com) → projeto **sincro-3ac01** →
   **IAM e administrador** → **Contas de serviço** → **Criar conta de serviço**.
2. Nome: `github-app-distribution`. Papel: **Administrador do Firebase App Distribution**.
3. Na conta criada → **Chaves** → **Adicionar chave** → **JSON**. Um arquivo é baixado.
4. Secret `FIREBASE_SERVICE_ACCOUNT_JSON`: o conteúdo inteiro desse arquivo
   (`pbcopy < ~/Downloads/<arquivo>.json`). Depois apague o arquivo baixado.

### 3. Google Play (depois do primeiro envio manual)

A API da Play só aceita envios de um app que já recebeu **um AAB enviado à mão** na Play Console.
Faça primeiro esse envio (o AAB pode ser o artefato de uma execução deste workflow).

1. No mesmo projeto do Google Cloud: **APIs e serviços** → **Biblioteca** → ative a
   **Google Play Android Developer API**.
2. Crie outra conta de serviço, `github-play-publisher` (sem papel no Cloud), e baixe a chave
   JSON como no passo 2.
3. Play Console → **Usuários e permissões** → **Convidar novos usuários** → e-mail da conta de
   serviço (`github-play-publisher@sincro-3ac01.iam.gserviceaccount.com`) → em **Permissões do
   app**, adicione o Sincro com **Lançar apps em faixas de teste**. Inclua **Lançar na produção**
   só quando quiser publicar em produção pelo GitHub.
4. Secret `PLAY_SERVICE_ACCOUNT_JSON`: o conteúdo do JSON.

### Variables (opcionais)

| Nome | Padrão |
|---|---|
| `API_BASE_URL` | `https://sincro-sandbox.duckdns.org/api` |
| `GOOGLE_WEB_CLIENT_ID` | o mesmo do `release-firebase.sh` |
| `FIREBASE_GROUPS` | `testadores-sandbox` |
| `PLAY_TRACK` | `internal` (faixa usada nos envios automáticos) |

---

## Caminho até a produção (conta pessoal)

A conta de desenvolvedor do Sincro é **pessoal** (ID 7942397505800602815). Contas pessoais
criadas a partir de novembro de 2023 só liberam a produção depois de:

1. **Teste fechado** com pelo menos **12 testadores** que aceitaram o convite e ficaram inscritos
   por **14 dias seguidos**.
2. Um pedido de **acesso à produção** na Play Console (Painel → *Solicitar acesso à produção*), com
   respostas sobre o teste.

Sequência sugerida:

| Etapa | Faixa no workflow | Quem instala |
|---|---|---|
| Teste interno | `internal` (automático) | até 100 pessoas da sua lista, sem revisão |
| Teste fechado (12 × 14 dias) | `alpha` (manual) | lista de testadores; conta para a exigência |
| Produção | `production` (manual, entra como rascunho) | público, após aprovação do acesso |

## Se algo falhar

| Mensagem | O que fazer |
|---|---|
| `Keystore, senha ou alias inválidos` | Confira os 4 segredos `ANDROID_*` com o `key.properties`. |
| `Package not found` ou `APK specifies a version code that has already been used` (Play) | O app ainda não recebeu o primeiro envio manual, ou um AAB com código maior foi enviado à mão. |
| `The caller does not have permission` (Play) | A conta de serviço não foi convidada na Play Console com permissão no Sincro. |
| Erro de permissão no Firebase | A conta de serviço precisa do papel **Administrador do Firebase App Distribution**. |
