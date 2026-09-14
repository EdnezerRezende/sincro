#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Prumo — planejamento + economia de contexto/tokens para construir software com Claude Code.

Motor 100% offline, só biblioteca-padrão do Python. Não acessa a internet, não
instala nada, não chama nenhuma API. Guarda tudo em .prumo/ na RAIZ do projeto.

A IA (Claude Code) conversa e escreve; este motor faz só a parte exata:
- raiox    : mede o peso do projeto e sugere um conjunto ENXUTO de arquivos p/ a tarefa
- plano    : guarda a spec+plano de uma tarefa (objetivo, arquivos-alvo, passos, aceite, fora-de-escopo)
- passo    : caminha o plano um passo verificável por vez
- claudemd : audita o CLAUDE.md do projeto (a memória que economiza token toda sessão)
- checar   : porta de pré-voo — a tarefa está pronta pra soltar a IA sem queimar token?
- sessao   : diário de sessões + painel de onde o token vaza

Uso: python3 prumo.py <comando> [opções]
"""
import sys, os, json, csv, re, unicodedata, argparse
from datetime import datetime, date

# ----------------------------------------------------------------------------
# Raiz do projeto e pasta .prumo
# ----------------------------------------------------------------------------

def raiz_projeto():
    """Acha a raiz do projeto: CLAUDE_PROJECT_DIR, ou sobe procurando .prumo/.git/.claude, senão cwd."""
    env = os.environ.get("CLAUDE_PROJECT_DIR")
    if env and os.path.isdir(env):
        return os.path.abspath(env)
    d = os.getcwd()
    while True:
        for marca in (".prumo", ".git", ".claude"):
            if os.path.isdir(os.path.join(d, marca)):
                return d
        pai = os.path.dirname(d)
        if pai == d:
            break
        d = pai
    return os.getcwd()

RAIZ = raiz_projeto()
DIR = os.path.join(RAIZ, ".prumo")
DIR_PLANOS = os.path.join(DIR, "planos")
ARQ_SESSOES = os.path.join(DIR, "sessoes.csv")
ARQ_CONFIG = os.path.join(DIR, "config.md")

def garante_dirs():
    os.makedirs(DIR_PLANOS, exist_ok=True)

# ----------------------------------------------------------------------------
# Utilidades de texto
# ----------------------------------------------------------------------------

def sem_acento(s):
    if not s:
        return ""
    return "".join(c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn").lower()

STOP = set("a o e de da do das dos que com para por um uma no na nos nas os as em ao aos "
           "se sua seu meu minha the of to and in for on is it este esta isso pra".split())

def tokeniza(s):
    s = sem_acento(s)
    palavras = re.findall(r"[a-z0-9_]+", s)
    return [p for p in palavras if len(p) > 1 and p not in STOP]

def slugify(s):
    s = sem_acento(s).strip()
    s = re.sub(r"[^a-z0-9]+", "-", s).strip("-")
    return s[:50] or "tarefa"

def hoje_iso():
    return date.today().isoformat()

# ----------------------------------------------------------------------------
# Config (lê o formato "- **Rótulo:** valor" gravado pelo setup)
# ----------------------------------------------------------------------------

def ler_config():
    cfg = {}
    if not os.path.exists(ARQ_CONFIG):
        return cfg
    with open(ARQ_CONFIG, encoding="utf-8") as f:
        for linha in f:
            m = re.match(r"\s*[-*]?\s*\*\*(.+?):?\*\*\s*(.*)", linha)
            if m:
                rot = sem_acento(m.group(1).strip().rstrip(":"))
                cfg[rot] = m.group(2).strip()
    return cfg

def cfg_get(cfg, *chaves, padrao=""):
    for c in chaves:
        c = sem_acento(c)
        for k, v in cfg.items():
            if c in k and v:
                return v
    return padrao

# ----------------------------------------------------------------------------
# RAIO-X do projeto (peso de contexto + conjunto enxuto de arquivos)
# ----------------------------------------------------------------------------

IGNORAR_DIRS = {".git", "node_modules", ".venv", "venv", "env", "__pycache__", "dist",
                "build", "out", ".next", ".nuxt", "target", "vendor", ".prumo", ".claude",
                "coverage", ".cache", ".idea", ".vscode", "Pods", ".gradle", "bin", "obj"}
IGNORAR_EXT = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".ico", ".pdf", ".zip",
               ".gz", ".tar", ".mp4", ".mov", ".mp3", ".wav", ".woff", ".woff2", ".ttf",
               ".otf", ".eot", ".lock", ".min.js", ".min.css", ".map", ".bin", ".exe",
               ".so", ".dylib", ".class", ".pyc", ".db", ".sqlite"}
EXT_CODIGO = {".py", ".js", ".ts", ".jsx", ".tsx", ".vue", ".svelte", ".go", ".rs", ".java",
              ".kt", ".php", ".rb", ".cs", ".cpp", ".c", ".h", ".swift", ".dart", ".sql",
              ".html", ".css", ".scss", ".json", ".yaml", ".yml", ".toml", ".md", ".sh"}

def eh_ignoravel_ext(nome):
    baixo = nome.lower()
    for e in IGNORAR_EXT:
        if baixo.endswith(e):
            return True
    return False

def varre_projeto():
    """Retorna lista de (path_relativo, linhas, bytes) dos arquivos de código do projeto."""
    itens = []
    for base, dirs, arqs in os.walk(RAIZ):
        dirs[:] = [d for d in dirs if d not in IGNORAR_DIRS and not d.startswith(".prumo")]
        for a in arqs:
            if a.startswith("."):
                continue
            if eh_ignoravel_ext(a):
                continue
            ext = os.path.splitext(a)[1].lower()
            if ext and ext not in EXT_CODIGO:
                continue
            fp = os.path.join(base, a)
            try:
                tam = os.path.getsize(fp)
                if tam > 2_000_000:   # arquivo gigante: conta mas não lê linhas
                    itens.append((os.path.relpath(fp, RAIZ), 0, tam))
                    continue
                with open(fp, "r", encoding="utf-8", errors="ignore") as f:
                    linhas = sum(1 for _ in f)
                itens.append((os.path.relpath(fp, RAIZ), linhas, tam))
            except (OSError, ValueError):
                continue
    return itens

def est_tokens(nbytes):
    # estimativa grosseira: ~4 caracteres por token
    return int(nbytes / 4)

def fmt_tok(n):
    if n >= 1000:
        return f"{n/1000:.1f}k"
    return str(n)

def cmd_raiox(args):
    itens = varre_projeto()
    if not itens:
        print("Não encontrei arquivos de código a partir de", RAIZ)
        print("Rode o Prumo dentro da pasta do seu projeto.")
        return
    total_linhas = sum(i[1] for i in itens)
    total_bytes = sum(i[2] for i in itens)
    tok_total = est_tokens(total_bytes)
    print(f"# Raio-X do projeto  ({RAIZ})")
    print(f"Arquivos de código: {len(itens)}  |  Linhas: {total_linhas:,}  |  "
          f"Peso p/ contexto: ~{fmt_tok(tok_total)} tokens se jogar TUDO".replace(",", "."))
    print()
    # por pasta
    porpasta = {}
    for rel, lin, by in itens:
        top = rel.split(os.sep)[0] if os.sep in rel else "(raiz)"
        p = porpasta.setdefault(top, [0, 0, 0])
        p[0] += 1; p[1] += lin; p[2] += by
    print("## Pastas mais pesadas (onde o contexto mora)")
    for pasta, (n, lin, by) in sorted(porpasta.items(), key=lambda x: -x[1][2])[:8]:
        print(f"  {fmt_tok(est_tokens(by)):>7} tok  {n:>4} arq  {lin:>7} linhas  {pasta}/")
    print()
    print("## Arquivos mais pesados")
    for rel, lin, by in sorted(itens, key=lambda x: -x[2])[:10]:
        print(f"  {fmt_tok(est_tokens(by)):>7} tok  {lin:>6} linhas  {rel}")
    print()

    tarefa = args.tarefa
    if tarefa:
        termos = set(tokeniza(tarefa))
        pont = []
        for rel, lin, by in itens:
            score = 0
            alvo = tokeniza(rel)
            for t in termos:
                for a in alvo:
                    if t == a or t in a or a in t:
                        score += 3
                        break
            # olha o conteúdo dos arquivos textuais pequenos
            if by < 200_000:
                try:
                    with open(os.path.join(RAIZ, rel), encoding="utf-8", errors="ignore") as f:
                        conteudo = sem_acento(f.read())
                    for t in termos:
                        c = conteudo.count(t)
                        if c:
                            score += min(c, 5)
                except OSError:
                    pass
            if score:
                pont.append((score, rel, lin))
        pont.sort(key=lambda x: -x[0])
        print(f'## Conjunto ENXUTO sugerido p/ a tarefa: "{tarefa}"')
        if not pont:
            print("  Não achei arquivos que casem com essas palavras. Descreva a tarefa com")
            print("  termos que apareçam nos nomes/código (ex.: 'login', 'checkout', 'usuario').")
        else:
            escolhidos = pont[:args.top]
            soma = 0
            for score, rel, lin in escolhidos:
                soma += lin
                print(f"  [{score:>3}] {rel}  ({lin} linhas)")
            frac = est_tokens(sum(i[2] for i in itens if i[0] in {e[1] for e in escolhidos}))
            print()
            print(f"  → São {len(escolhidos)} arquivo(s), ~{fmt_tok(frac)} tokens — "
                  f"em vez dos ~{fmt_tok(tok_total)} do projeto inteiro.")
            print("  Abra a IA APENAS nesses arquivos. Não jogue o repositório todo no contexto.")
    else:
        print("Dica: rode com  --tarefa \"o que você vai mexer\"  pra receber o conjunto")
        print("      enxuto de arquivos a abrir (economiza token de verdade).")

# ----------------------------------------------------------------------------
# PLANO (spec + passos)
# ----------------------------------------------------------------------------

def caminho_plano(slug):
    return os.path.join(DIR_PLANOS, slug + ".json")

def carrega_plano(slug):
    fp = caminho_plano(slug)
    if not os.path.exists(fp):
        return None
    with open(fp, encoding="utf-8") as f:
        return json.load(f)

def salva_plano(p):
    garante_dirs()
    with open(caminho_plano(p["slug"]), "w", encoding="utf-8") as f:
        json.dump(p, f, ensure_ascii=False, indent=2)

def cmd_plano_nova(args):
    garante_dirs()
    slug = args.slug or slugify(args.titulo)
    if carrega_plano(slug):
        print(f"Já existe um plano '{slug}'. Use outro --slug ou edite o existente.")
        return
    p = {
        "slug": slug,
        "titulo": args.titulo,
        "objetivo": args.objetivo or "",
        "criado": hoje_iso(),
        "arquivos_alvo": [],
        "fora_de_escopo": [x.strip() for x in (args.fora or "").split(";") if x.strip()],
        "criterio_aceite": args.aceite or "",
        "passos": [],
    }
    salva_plano(p)
    print(f"Plano criado: {slug}  ({args.titulo})")
    print("Próximo: adicione os arquivos-alvo (plano-alvo) e os passos (passo-add).")

def cmd_plano_alvo(args):
    p = carrega_plano(args.slug)
    if not p:
        print(f"Plano '{args.slug}' não existe."); return
    if args.add:
        for a in [x.strip() for x in args.add.split(",") if x.strip()]:
            if a not in p["arquivos_alvo"]:
                p["arquivos_alvo"].append(a)
    if args.rm and args.rm in p["arquivos_alvo"]:
        p["arquivos_alvo"].remove(args.rm)
    salva_plano(p)
    print(f"Arquivos-alvo de '{args.slug}': {len(p['arquivos_alvo'])}")
    for a in p["arquivos_alvo"]:
        print("  -", a)

FASES = {"setup": "1. Preparar", "impl": "2. Construir", "teste": "3. Testar e verificar"}

def cmd_passo_add(args):
    p = carrega_plano(args.slug)
    if not p:
        print(f"Plano '{args.slug}' não existe."); return
    fase = args.fase if args.fase in FASES else "impl"
    novo_id = (max([s["id"] for s in p["passos"]], default=0) + 1)
    p["passos"].append({
        "id": novo_id, "fase": fase, "texto": args.texto,
        "arquivo": args.arquivo or "", "aceite": args.aceite or "", "feito": False,
    })
    salva_plano(p)
    print(f"Passo #{novo_id} [{FASES[fase]}] adicionado ao plano '{args.slug}'.")

def render_plano(p):
    linhas = []
    linhas.append(f"# Plano: {p['titulo']}   (slug: {p['slug']})")
    if p.get("objetivo"):
        linhas.append(f"\n**Objetivo:** {p['objetivo']}")
    if p.get("arquivos_alvo"):
        linhas.append("\n## Arquivos-alvo (o conjunto enxuto — abra só estes)")
        for a in p["arquivos_alvo"]:
            linhas.append(f"  - {a}")
    if p.get("criterio_aceite"):
        linhas.append(f"\n## Critério de aceite (como saber que terminou)\n  {p['criterio_aceite']}")
    if p.get("fora_de_escopo"):
        linhas.append("\n## Fora de escopo (não faça agora — trava a IA de sair passeando)")
        for a in p["fora_de_escopo"]:
            linhas.append(f"  - {a}")
    if p.get("passos"):
        linhas.append("\n## Passos (um verificável por vez, em ordem)")
        for fase_k, fase_nome in FASES.items():
            ps = [s for s in p["passos"] if s["fase"] == fase_k]
            if not ps:
                continue
            linhas.append(f"\n### {fase_nome}")
            for s in ps:
                mark = "x" if s["feito"] else " "
                arq = f"  → arquivo: {s['arquivo']}" if s.get("arquivo") else ""
                linhas.append(f"  [{mark}] #{s['id']} {s['texto']}{arq}")
                if s.get("aceite"):
                    linhas.append(f"        aceite: {s['aceite']}")
    feitos = sum(1 for s in p["passos"] if s["feito"])
    linhas.append(f"\nProgresso: {feitos}/{len(p['passos'])} passos concluídos.")
    return "\n".join(linhas)

def cmd_plano(args):
    p = carrega_plano(args.slug)
    if not p:
        print(f"Plano '{args.slug}' não existe."); return
    print(render_plano(p))

def cmd_planos(args):
    garante_dirs()
    arqs = [f for f in os.listdir(DIR_PLANOS) if f.endswith(".json")]
    if not arqs:
        print("Nenhum plano ainda. Crie com: plano-nova --titulo \"...\"")
        return
    print("# Planos")
    for f in sorted(arqs):
        p = carrega_plano(f[:-5])
        feitos = sum(1 for s in p["passos"] if s["feito"])
        print(f"  {p['slug']:<28} {feitos}/{len(p['passos'])} passos  — {p['titulo']}")

def cmd_passo_proximo(args):
    p = carrega_plano(args.slug)
    if not p:
        print(f"Plano '{args.slug}' não existe."); return
    for fase_k in FASES:
        for s in p["passos"]:
            if s["fase"] == fase_k and not s["feito"]:
                print(f"Próximo passo do plano '{p['slug']}':\n")
                print(f"  [{FASES[s['fase']]}]  #{s['id']}  {s['texto']}")
                if s.get("arquivo"):
                    print(f"  arquivo: {s['arquivo']}")
                if s.get("aceite"):
                    print(f"  como verificar: {s['aceite']}")
                print("\n  → Faça SÓ este passo. Verifique. Depois: passo-concluir --slug",
                      f"{p['slug']} --id {s['id']}")
                return
    print(f"Todos os passos do plano '{p['slug']}' já foram concluídos. 🎉")

def cmd_passo_concluir(args):
    p = carrega_plano(args.slug)
    if not p:
        print(f"Plano '{args.slug}' não existe."); return
    achou = False
    for s in p["passos"]:
        if s["id"] == args.id:
            s["feito"] = not args.reabrir
            achou = True
    if not achou:
        print(f"Passo #{args.id} não existe no plano."); return
    salva_plano(p)
    feitos = sum(1 for s in p["passos"] if s["feito"])
    estado = "reaberto" if args.reabrir else "concluído"
    print(f"Passo #{args.id} {estado}. Progresso: {feitos}/{len(p['passos'])}.")

# ----------------------------------------------------------------------------
# CLAUDE.md — auditoria (a memória do projeto = economia toda sessão)
# ----------------------------------------------------------------------------

SECOES_ESPERADAS = [
    (["visao", "overview", "projeto", "sobre"], "Visão do projeto (o que é, em 1-2 linhas)"),
    (["stack", "tecnolog", "tech"], "Stack / tecnologias"),
    (["comando", "command", "scripts", "rodar", "run"], "Comandos (rodar, testar, buildar)"),
    (["arquitet", "estrutura", "architecture", "pastas"], "Arquitetura / estrutura de pastas"),
    (["convenc", "estilo", "style", "padr"], "Convenções / estilo de código"),
    (["gotcha", "cuidado", "evite", "nao faca", "armadilha", "pitfall", "don't", "dont"],
     "Cuidados / armadilhas (regras DE NÃO fazer)"),
    (["test"], "Como testar"),
]

def cmd_claudemd_auditar(args):
    caminho = args.arquivo or os.path.join(RAIZ, "CLAUDE.md")
    if not os.path.exists(caminho):
        print(f"Não achei CLAUDE.md em {caminho}")
        print("Esse arquivo é a MEMÓRIA do projeto — sem ele, a IA redescobre tudo toda")
        print("sessão e queima token à toa. Gere um esqueleto com:  claudemd-modelo")
        return
    with open(caminho, encoding="utf-8") as f:
        txt = f.read()
    baixo = sem_acento(txt)
    nbytes = len(txt.encode("utf-8"))
    tok = est_tokens(nbytes)
    linhas_txt = [l for l in txt.splitlines()]
    achados = []   # (severidade, msg)

    # 1) orçamento de tokens
    if tok > 4000:
        achados.append(("🔴", f"CLAUDE.md tem ~{fmt_tok(tok)} tokens. Isso é carregado em TODA "
                              "sessão. Acima de ~4000 é caro demais — quebre em arquivos menores "
                              "e use @import, ou corte o que a IA não precisa toda vez."))
    elif tok > 3000:
        achados.append(("🟡", f"CLAUDE.md tem ~{fmt_tok(tok)} tokens, perto do teto de ~3000 "
                              "recomendado. Enxugue as seções mais verborrágicas."))

    # 2) seções esperadas
    faltando = []
    for chaves, nome in SECOES_ESPERADAS:
        if not any(c in baixo for c in chaves):
            faltando.append(nome)
    for nome in faltando:
        sev = "🟡" if "armadilha" not in nome.lower() and "testar" not in nome.lower() else "⚪"
        achados.append((sev, f"Falta seção: {nome}."))

    # 3) placeholders não resolvidos
    ph = re.findall(r"\[preencher\]|\[seu[^\]]*\]|\[.*?aqui.*?\]|\bTODO\b|\bTBD\b|xxxx+", baixo)
    if ph:
        achados.append(("🔴", f"Tem {len(ph)} placeholder(s) não preenchido(s) (ex.: [PREENCHER], "
                              "TODO). A IA obedece isso ao pé da letra — preencha ou apague."))

    # 4) comandos rodáveis
    if "```" not in txt and not re.search(r"`[a-z]+ [a-z]", baixo):
        achados.append(("🟡", "Não achei comandos concretos (npm run..., pytest, etc.). Liste os "
                              "comandos EXATOS de rodar/testar/buildar — poupa a IA de adivinhar."))

    # 5) prosa demais (pouco bullet/código)
    bullets = len(re.findall(r"(?m)^\s*[-*]\s", txt))
    codeblk = txt.count("```") // 2
    n_linhas_conteudo = len([l for l in linhas_txt if l.strip()])
    if n_linhas_conteudo > 25 and bullets < 5 and codeblk == 0:
        achados.append(("⚪", "Está em prosa corrida. Bullets, tabelas e blocos de código gastam "
                              "menos token e a IA acha mais rápido. Converta em lista."))

    # relatório
    print(f"# Auditoria do CLAUDE.md  ({caminho})")
    print(f"Tamanho: ~{fmt_tok(tok)} tokens  |  {n_linhas_conteudo} linhas de conteúdo  |  "
          f"{bullets} bullets  |  {codeblk} blocos de código")
    print()
    reds = sum(1 for s, _ in achados if s == "🔴")
    yellows = sum(1 for s, _ in achados if s == "🟡")
    if not achados:
        nota = "🟢 Ótimo"
    elif reds:
        nota = "🔴 Precisa de conserto"
    elif yellows:
        nota = "🟡 Dá pra melhorar"
    else:
        nota = "🟢 Bom, com ajustes opcionais"
    print(f"Veredito: {nota}")
    print()
    if achados:
        print("## Pontos")
        for sev, msg in achados:
            print(f"  {sev} {msg}")
    else:
        print("Tem visão, stack, comandos, arquitetura, convenções, cuidados e testes. Segue assim.")
    print()
    print("Regra de ouro: o CLAUDE.md é lido TODA sessão. Cada linha inútil aqui é token")
    print("gasto pra sempre; cada regra útil evita a IA errar e refazer. Enxuto e certeiro.")

def cmd_claudemd_modelo(args):
    cfg = ler_config()
    nome = cfg_get(cfg, "projeto", "nome", padrao="Meu Projeto")
    print("""# {nome}

## Visão do projeto
- O que é: [descreva em 1-2 linhas o que este software faz e pra quem]
- Estado: [em produção / em construção / protótipo]

## Stack
- Linguagem/framework: [ex.: Node + React + TypeScript / Python + FastAPI]
- Banco de dados: [ex.: PostgreSQL / SQLite / nenhum]
- Onde roda: [ex.: local / Vercel / VPS]

## Comandos (os exatos)
```
[comando de rodar,   ex.: npm run dev]
[comando de testar,  ex.: npm test]
[comando de build,   ex.: npm run build]
[comando de lint,    ex.: npm run lint]
```

## Arquitetura / estrutura
- `src/...` — [o que vive aqui]
- [pasta] — [responsabilidade]
- Como as partes conversam: [1-2 linhas]

## Convenções
- Estilo: [ex.: funções pequenas, sem classe / TypeScript estrito]
- Nomes: [camelCase / snake_case]
- Sempre: [ex.: tratar erro, escrever teste do que muda]

## Cuidados / armadilhas (regras DE NÃO fazer)
- NÃO edite [arquivos gerados automaticamente / migrations antigas]
- NÃO use [biblioteca X descontinuada]
- Cuidado com [pegadinha conhecida do projeto]

## Como testar
- [como rodar 1 teste específico e como saber que passou]
""".format(nome=nome))
    print("# ↑ Copie isso pro CLAUDE.md na raiz do projeto e a IA preenche cada [colchete] com você.")

# ----------------------------------------------------------------------------
# CHECAR — porta de pré-voo antes de soltar a IA
# ----------------------------------------------------------------------------

def cmd_checar(args):
    print("# Pré-voo — a tarefa está pronta pra soltar a IA sem queimar token?\n")
    itens = []   # (ok?, rótulo, dica)

    # CLAUDE.md presente e dentro do orçamento
    cm = os.path.join(RAIZ, "CLAUDE.md")
    if os.path.exists(cm):
        tok = est_tokens(len(open(cm, encoding="utf-8", errors="ignore").read().encode("utf-8")))
        if tok > 4000:
            itens.append(("🟡", f"CLAUDE.md existe mas está pesado (~{fmt_tok(tok)} tok)",
                          "enxugue — roda claudemd-auditar"))
        else:
            itens.append(("🟢", "CLAUDE.md presente (memória do projeto)", ""))
    else:
        itens.append(("🔴", "Sem CLAUDE.md", "gere com claudemd-modelo — sem ele a IA redescobre tudo"))

    p = carrega_plano(args.slug) if args.slug else None
    if args.slug and not p:
        print(f"(plano '{args.slug}' não existe — crie com plano-nova)\n")
    if p:
        # plano tem objetivo
        itens.append(("🟢" if p.get("objetivo") else "🔴",
                      "Objetivo escrito" if p.get("objetivo") else "Plano sem objetivo",
                      "" if p.get("objetivo") else "diga o que/por quê"))
        # arquivos-alvo enxutos
        n = len(p.get("arquivos_alvo", []))
        if n == 0:
            itens.append(("🔴", "Nenhum arquivo-alvo definido",
                          "rode raiox --tarefa e liste os poucos arquivos que importam"))
        elif n > 12:
            itens.append(("🟡", f"{n} arquivos-alvo (muita coisa)",
                          "quebre a tarefa — contexto grande = token e confusão"))
        else:
            itens.append(("🟢", f"Conjunto enxuto: {n} arquivo(s)-alvo", ""))
        # critério de aceite
        itens.append(("🟢" if p.get("criterio_aceite") else "🔴",
                      "Critério de aceite definido" if p.get("criterio_aceite") else "Sem critério de aceite",
                      "" if p.get("criterio_aceite") else "como você vai saber que terminou?"))
        # passos
        itens.append(("🟢" if p.get("passos") else "🟡",
                      f"{len(p.get('passos', []))} passo(s) no plano" if p.get("passos") else "Sem passos",
                      "" if p.get("passos") else "quebre em passos verificáveis"))
        # fora de escopo
        itens.append(("🟢" if p.get("fora_de_escopo") else "⚪",
                      "Fora-de-escopo declarado" if p.get("fora_de_escopo") else "Fora-de-escopo não declarado",
                      "" if p.get("fora_de_escopo") else "diga o que NÃO fazer agora — trava a IA de passear"))
    else:
        itens.append(("🔴", "Sem plano pra esta tarefa",
                      "crie com plano-nova e passe --slug aqui no checar"))

    for sev, rot, dica in itens:
        extra = f"  → {dica}" if dica else ""
        print(f"  {sev} {rot}{extra}")

    reds = sum(1 for s, _, _ in itens if s == "🔴")
    yellows = sum(1 for s, _, _ in itens if s == "🟡")
    print()
    if reds:
        print("Veredito: 🔴 AINDA NÃO. Resolva os 🔴 antes de soltar a IA — é aí que o token vaza.")
    elif yellows:
        print("Veredito: 🟡 QUASE. Dá pra ir, mas ajuste os 🟡 pra gastar menos.")
    else:
        print("Veredito: 🟢 PRONTO. Plano enxuto, contexto pequeno, aceite claro. Pode construir.")

# ----------------------------------------------------------------------------
# SESSÃO — diário + painel de economia
# ----------------------------------------------------------------------------

CAMPOS_SESSAO = ["id", "data", "tarefa", "desfecho", "tokens", "nota"]

def le_sessoes():
    if not os.path.exists(ARQ_SESSOES):
        return []
    with open(ARQ_SESSOES, encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))

def escreve_sessoes(rows):
    garante_dirs()
    with open(ARQ_SESSOES, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=CAMPOS_SESSAO)
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k, "") for k in CAMPOS_SESSAO})

def cmd_sessao_iniciar(args):
    rows = le_sessoes()
    novo_id = str(max([int(r["id"]) for r in rows if r.get("id", "").isdigit()], default=0) + 1)
    rows.append({"id": novo_id, "data": hoje_iso(), "tarefa": args.tarefa,
                 "desfecho": "aberta", "tokens": "", "nota": ""})
    escreve_sessoes(rows)
    print(f"Sessão #{novo_id} aberta: {args.tarefa}")
    print("Ao terminar, feche com o desfecho honesto:")
    print(f"  sessao-fechar --id {novo_id} --desfecho entregou|travou|loop [--tokens N] [--nota \"...\"]")

DESFECHOS = {"entregou": "🟢 entregou", "travou": "🟡 travou", "loop": "🔴 loop/refez"}

def cmd_sessao_fechar(args):
    rows = le_sessoes()
    achou = False
    for r in rows:
        if r["id"] == str(args.id):
            r["desfecho"] = args.desfecho if args.desfecho in DESFECHOS else "entregou"
            if args.tokens is not None:
                r["tokens"] = str(args.tokens)
            if args.nota:
                r["nota"] = args.nota
            achou = True
    if not achou:
        print(f"Sessão #{args.id} não existe."); return
    escreve_sessoes(rows)
    print(f"Sessão #{args.id} fechada como {DESFECHOS.get(args.desfecho, args.desfecho)}.")

def cmd_sessoes(args):
    rows = le_sessoes()
    if not rows:
        print("Nenhuma sessão registrada. Abra com: sessao-iniciar --tarefa \"...\"")
        return
    print("# Sessões")
    for r in rows[-20:]:
        d = DESFECHOS.get(r.get("desfecho", ""), r.get("desfecho", ""))
        tk = f"  ~{r['tokens']} tok" if r.get("tokens") else ""
        nota = f"  — {r['nota']}" if r.get("nota") else ""
        print(f"  #{r['id']} {r['data']}  {d}{tk}  {r['tarefa']}{nota}")

def cmd_stats(args):
    rows = le_sessoes()
    if not rows:
        print("Sem sessões ainda. Registre com sessao-iniciar / sessao-fechar.")
        return
    fechadas = [r for r in rows if r.get("desfecho") in DESFECHOS]
    n = len(fechadas)
    print("# Painel de economia\n")
    print(f"Sessões registradas: {len(rows)}  (fechadas: {n})")
    if n:
        for k, rotulo in DESFECHOS.items():
            c = sum(1 for r in fechadas if r["desfecho"] == k)
            pct = f"{100*c/n:.0f}%"
            print(f"  {rotulo:<14} {c:>3}  ({pct})")
        toks = [int(r["tokens"]) for r in fechadas if r.get("tokens", "").isdigit()]
        if toks:
            print(f"\nToken/sessão (quando informado): média ~{fmt_tok(int(sum(toks)/len(toks)))}, "
                  f"total ~{fmt_tok(sum(toks))}")
        ruins = [r for r in fechadas if r["desfecho"] in ("travou", "loop")]
        if ruins:
            print(f"\n⚠️  {len(ruins)} sessão(ões) travaram ou entraram em loop "
                  f"({100*len(ruins)/n:.0f}%) — é aí que o token queima.")
            # assuntos recorrentes das sessões ruins
            cont = {}
            for r in ruins:
                for t in tokeniza(r.get("tarefa", "")):
                    cont[t] = cont.get(t, 0) + 1
            top = sorted(cont.items(), key=lambda x: -x[1])
            top = [f"{t}({c})" for t, c in top if c >= 2][:6]
            if top:
                print("   Assuntos que mais travam:", ", ".join(top))
                print("   → Esses merecem um CLAUDE.md melhor ou um plano mais enxuto antes.")
        else:
            print("\n🟢 Nenhuma sessão travada/loop registrada. Disciplina no prumo!")

# ----------------------------------------------------------------------------
# CONFIG
# ----------------------------------------------------------------------------

def cmd_config_ver(args):
    cfg = ler_config()
    if not cfg:
        print("Sem config ainda (rode o setup de primeira execução).")
        return
    print("# Config do Prumo")
    for k, v in cfg.items():
        print(f"  {k}: {v}")

# ----------------------------------------------------------------------------
# CLI
# ----------------------------------------------------------------------------

def build_parser():
    p = argparse.ArgumentParser(prog="prumo", description="Prumo — plano + economia de contexto/tokens no Claude Code")
    sub = p.add_subparsers(dest="cmd")

    r = sub.add_parser("raiox", help="mede o peso do projeto + conjunto enxuto de arquivos")
    r.add_argument("--tarefa", default="", help="palavras da tarefa p/ sugerir os arquivos-alvo")
    r.add_argument("--top", type=int, default=6, help="quantos arquivos sugerir (padrão 6)")
    r.set_defaults(func=cmd_raiox)

    pn = sub.add_parser("plano-nova", help="cria um plano de tarefa")
    pn.add_argument("--titulo", required=True)
    pn.add_argument("--slug", default="")
    pn.add_argument("--objetivo", default="")
    pn.add_argument("--fora", default="", help="itens fora de escopo separados por ;")
    pn.add_argument("--aceite", default="")
    pn.set_defaults(func=cmd_plano_nova)

    pa = sub.add_parser("plano-alvo", help="gerencia os arquivos-alvo (conjunto enxuto)")
    pa.add_argument("--slug", required=True)
    pa.add_argument("--add", default="", help="paths separados por vírgula")
    pa.add_argument("--rm", default="")
    pa.set_defaults(func=cmd_plano_alvo)

    ps = sub.add_parser("passo-add", help="adiciona um passo verificável ao plano")
    ps.add_argument("--slug", required=True)
    ps.add_argument("--fase", default="impl", choices=list(FASES.keys()))
    ps.add_argument("--texto", required=True)
    ps.add_argument("--arquivo", default="")
    ps.add_argument("--aceite", default="")
    ps.set_defaults(func=cmd_passo_add)

    pv = sub.add_parser("plano", help="mostra um plano")
    pv.add_argument("--slug", required=True)
    pv.set_defaults(func=cmd_plano)

    sub.add_parser("planos", help="lista os planos").set_defaults(func=cmd_planos)

    pp = sub.add_parser("passo-proximo", help="mostra o próximo passo a fazer")
    pp.add_argument("--slug", required=True)
    pp.set_defaults(func=cmd_passo_proximo)

    pc = sub.add_parser("passo-concluir", help="marca um passo como feito")
    pc.add_argument("--slug", required=True)
    pc.add_argument("--id", type=int, required=True)
    pc.add_argument("--reabrir", action="store_true")
    pc.set_defaults(func=cmd_passo_concluir)

    ca = sub.add_parser("claudemd-auditar", help="audita o CLAUDE.md do projeto")
    ca.add_argument("--arquivo", default="")
    ca.set_defaults(func=cmd_claudemd_auditar)

    sub.add_parser("claudemd-modelo", help="imprime um esqueleto de CLAUDE.md").set_defaults(func=cmd_claudemd_modelo)

    ck = sub.add_parser("checar", help="pré-voo: a tarefa está pronta pra soltar a IA?")
    ck.add_argument("--slug", default="")
    ck.set_defaults(func=cmd_checar)

    si = sub.add_parser("sessao-iniciar", help="abre uma sessão de trabalho no diário")
    si.add_argument("--tarefa", required=True)
    si.set_defaults(func=cmd_sessao_iniciar)

    sf = sub.add_parser("sessao-fechar", help="fecha uma sessão com o desfecho")
    sf.add_argument("--id", type=int, required=True)
    sf.add_argument("--desfecho", required=True, choices=list(DESFECHOS.keys()))
    sf.add_argument("--tokens", type=int, default=None)
    sf.add_argument("--nota", default="")
    sf.set_defaults(func=cmd_sessao_fechar)

    sub.add_parser("sessoes", help="lista as sessões").set_defaults(func=cmd_sessoes)
    sub.add_parser("stats", help="painel de economia").set_defaults(func=cmd_stats)
    sub.add_parser("config-ver", help="mostra a config").set_defaults(func=cmd_config_ver)
    return p

def main():
    parser = build_parser()
    args = parser.parse_args()
    if not getattr(args, "cmd", None):
        parser.print_help()
        return
    args.func(args)

if __name__ == "__main__":
    main()
