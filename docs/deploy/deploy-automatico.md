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

```bash
ssh-copy-id -i ~/.ssh/sincro_deploy.pub ubuntu@<ip-da-vps>
# confirme que entra sem senha:
ssh -i ~/.ssh/sincro_deploy ubuntu@<ip-da-vps> 'cd ~/sincro && git status -sb'
```

O segundo comando também confirma o caminho do repositório na VPS. Se não for `~/sincro`,
anote o caminho certo para o passo 4.

Confira também que, na VPS, o repositório está na branch `master` e que `git pull` funciona sem
pedir senha. Hoje o `./deploy.sh` manual já faz isso, então deve estar ok.

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
| `VPS_USER` | usuário do SSH, normalmente `ubuntu` |
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
| `Permission denied (publickey)` | A chave pública não está em `~/.ssh/authorized_keys` do usuário certo na VPS, ou o `VPS_SSH_KEY` foi colado incompleto. |
| `Host key verification failed` | O `VPS_KNOWN_HOSTS` não corresponde ao servidor. Rode o `ssh-keyscan` de novo. |
| `Not possible to fast-forward` | A cópia do repositório na VPS tem commits ou alterações locais. Entre na VPS e resolva com `git status`. |
| `/api/health não respondeu 200` | A API não subiu. Na VPS: `docker compose -f docker-compose.yml -f docker-compose.sandbox.yml logs --tail 100 backend`. |

## Revogar o acesso

Apague a linha `github-actions-deploy-sincro` do `~/.ssh/authorized_keys` da VPS e remova os
segredos do environment `sandbox` no GitHub.
