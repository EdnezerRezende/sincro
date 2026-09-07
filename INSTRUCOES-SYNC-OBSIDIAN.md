# Instrucoes para ativar sincronizacao automatica -> Obsidian
# Destino: /Users/ed/Library/CloudStorage/OneDrive-Pessoal/Documentos/obsidian/segundo-cerebro/sincro-sync

## 1. Criar diretorio de hooks
mkdir -p /Users/ed/Desenvolvimento/projetos/sincro/.claude/hooks

## 2. Copiar script
cp sync-obsidian-script.sh .claude/hooks/sync-to-obsidian.sh
chmod +x .claude/hooks/sync-to-obsidian.sh

## 3. Hooks git (executar dentro do repo)
cp .claude/hooks/sync-to-obsidian.sh .git/hooks/post-rewrite
cp .claude/hooks/sync-to-obsidian.sh .git/hooks/post-checkout
chmod +x .git/hooks/post-rewrite .git/hooks/post-checkout

## 4. Monitor OneDrive/docs (lançar no terminal / launchd)
# Opcao A (fswatch):
# fswatch -o /Users/ed/Library/CloudStorage/OneDrive-Pessoal/Documentos | while read; do /Users/ed/Desenvolvimento/projetos/sincro/.claude/hooks/sync-to-obsidian.sh; done
# Opcao B (launchd - cria /Users/ed/Library/LaunchAgents/obsidian-sync.plist)
