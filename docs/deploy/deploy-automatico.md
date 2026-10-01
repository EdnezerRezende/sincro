# Deploy automático do sandbox

Depois de configurado, cada merge na `master` faz o seguinte, sem ninguém entrar na VPS:

1. O **CI** (`.github/workflows/ci.yml`) roda os testes do backend e do app.
2. Se o CI passar, o **Deploy sandbox** (`.github/workflows/deploy-sandbox.yml`) entra na VPS
   por SSH e executa `./deploy.sh` (`git pull` e `docker compose up --build`).
3. O deploy só termina com sucesso quando `https://<domínio>/api/health` responde 200 e as
   páginas `privacidade.html`, `excluir-conta.html` e `app-ads.txt` estão no ar.

Para disparar à mão: GitHub → **Actions** → **Deploy sandbox** → **Run workflow**.

Enquanto os segredos abaixo não existirem, o workflow apenas mostra um aviso e não faz nada.

---

## Configuração (uma vez só)

### 1. Criar uma chave SSH só para o deploy (no seu Mac)

```bash
ssh-keygen -t ed25519 -C "github-actions-deploy-sincro" -f ~/.ssh/sincro_deploy -N ""
```

São gerados dois arquivos: `~/.ssh/sincro_deploy` (privada, vai para o GitHub) e
`~/.ssh/sincro_deploy.pub` (pública, vai para a VPS). Use uma chave nova, não a sua chave
pessoal: se um dia precisar revogar o acesso do GitHub, basta apagar uma linha na VPS.

### 2. Autorizar a chave na VPS

A VPS (Oracle Linux) não aceita senha: para instalar a chave nova, entre com a chave que você já
usa. O usuário é **`opc`**.

```bash
cat ~/.ssh/sincro_deploy.pub | ssh -o PubkeyAcceptedKeyTypes=+ssh-rsa \
  -i "/caminho/da/sua/chave-atual.key" \
  opc@<ip-da-vps> \
  'mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && echo CHAVE_INSTALADA'
```

O `ssh-copy-id` sozinho falha com `Permission denied`, porque ele não sabe qual chave usar para
entrar.

Teste só com a chave nova, do mesmo jeito que o GitHub vai fazer:

```bash
ssh -i ~/.ssh/sincro_deploy -o IdentitiesOnly=yes -o BatchMode=yes opc@<ip-da-vps> 'cd ~/sincro && git status -sb'
```

Se não mostrar o status do git, o repositório não está em `~/sincro`. Anote o caminho certo para
o passo 4.

Se a chave aparece em `~/.ssh/authorized_keys` mas o acesso continua negado, o SELinux pode estar
bloqueando o arquivo. Rode `restorecon -Rv ~/.ssh` na VPS.

### 3. Pegar a impressão digital do servidor (no seu Mac)

```bash
ssh-keyscan <ip-da-vps>
```

Copie todas as linhas da saída. Elas fazem o GitHub recusar a conexão se alguém se passar pelo seu
servidor.

### 4. Cadastrar no GitHub

GitHub → repositório **sincro** → **Settings** → **Environments** → **New environment** →
nome `sandbox`. Dentro dele:

**Environment secrets**

| Nome | Valor |
|---|---|
| `VPS_HOST` | IP da VPS (ou o domínio) |
| `VPS_USER` | usuário do SSH: `opc` na VPS atual (Oracle Linux) |
| `VPS_SSH_KEY` | conteúdo inteiro de `~/.ssh/sincro_deploy` (com as linhas `-----BEGIN` e `-----END`) |
| `VPS_KNOWN_HOSTS` | saída do `ssh-keyscan` do passo 3 |

Para copiar a chave privada no Mac: `pbcopy < ~/.ssh/sincro_deploy`.

**Environment variables** (opcionais, só se forem diferentes do padrão)

| Nome | Padrão |
|---|---|
| `VPS_APP_DIR` | `~/sincro` |
| `VPS_PORT` | `22` |
| `SANDBOX_URL` | `https://sincro-sandbox.duckdns.org` |

### 5. Testar

GitHub → **Actions** → **Deploy sandbox** → **Run workflow** → branch `master`.

---

## Se algo falhar

| Mensagem | O que fazer |
|---|---|
| `Permission denied (publickey)` | Rode o teste do passo 2 no seu Mac. Se falhar lá também, a chave não foi instalada (ou falta o `restorecon`). Se funcionar no Mac, confira `VPS_USER` (`opc`) e cole de novo o `VPS_SSH_KEY` com `pbcopy < ~/.ssh/sincro_deploy`. |
| `Host key verification failed` | O `VPS_KNOWN_HOSTS` não corresponde ao servidor. Rode o `ssh-keyscan` de novo. |
| `Not possible to fast-forward` | A cópia do repositório na VPS tem commits ou alterações locais. Entre na VPS e resolva com `git status`. |
| `/api/health não respondeu 200` | A API não subiu. Na VPS: `docker compose -f docker-compose.yml -f docker-compose.sandbox.yml logs --tail 100 backend`. |

## Revogar o acesso

Apague a linha `github-actions-deploy-sincro` do `~/.ssh/authorized_keys` da VPS e remova os
segredos do environment `sandbox` no GitHub.
