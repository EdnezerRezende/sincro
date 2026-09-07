#!/bin/zsh
# sync-to-obsidian.sh — roda apos git post-rewrite/post-checkout E pelo monitor
OBSIDIAN="/Users/ed/Library/CloudStorage/OneDrive-Pessoal/Documentos/obsidian/segundo-cerebro"
REPO="/Users/ed/Desenvolvimento/projetos/sincro"
ONEDRIVE="/Users/ed/Library/CloudStorage/OneDrive-Pessoal/Documentos"
mkdir -p "$OBSIDIAN/sincro-sync"
# repo docs
rsync -a --include='README*' --include='*.md' --include='docs/**' --exclude='*' "$REPO/" "$OBSIDIAN/sincro-sync/" 2>/dev/null || true
# one drive docs modificados
find "$ONEDRIVE" -maxdepth 2 -name '*.md' -newer "$OBSIDIAN/sincro-sync/.last-sync" 2>/dev/null | while read f; do cp "$f" "$OBSIDIAN/sincro-sync/" 2>/dev/null || true; done
touch "$OBSIDIAN/sincro-sync/.last-sync"
echo "[$(date '+%Y-%m-%d %H:%M')] sync-ok" >> "$OBSIDIAN/sincro-sync/log.txt"
