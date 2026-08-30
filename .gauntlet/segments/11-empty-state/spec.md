# Segmento 11 — Empty State (Sem Conteúdo)

- **Onda**: 1
- **Depende de**: 00-design-system, 01-component-button
- **Escopo de arquivos**: `mobile/lib/core/widgets/empty_widget.dart` ou similar

## Entregável
Empty state reutilizável com:
- Ilustração ou ícone (suave, não desconfortável)
- Título descritivo ("Sem emails", "Nenhum contato", etc)
- Mensagem curta explicando o que esperar
- CTA button opcional ("Adicionar Email", "Criar Contato")
- Espaçamento e centralização

## Critérios de aceitação
1. Título é descritivo (não genérico tipo "vazio")
2. Mensagem é uma frase (máx 2), útil
3. Ícone/ilustração é alegre ou neutro (não angustiante)
4. CTA button é primário se houver ação óbvia
5. Empty state ocupa espaço sensível (não minúsculo)
6. Dark mode: cores legíveis
7. Consistência: todos os empty states seguem o mesmo padrão?
8. Sem blame language ("você não", "ainda não")

## Benchmark
Empty state amigável tipo Figma, Slack, Notion. Esperançoso, útil, alegre.

## Método de verificação
- Nível: 1 (screenshot)
- Ferramenta: App emulador + criar situações vazias (deletar todos contatos, etc)

### Roteiro de experiência
1. Abrir tela que pode ficar vazia (email list sem emails, contatos vazia)
2. Tirar screenshot de empty state
3. Observar: título é descritivo?
4. Observar: ícone é alegre/suave?
5. Observar: button é claro (se houver)?
6. Comparar empty states de diferentes telas (padrão consistente?)

## Histórico de notas
| Rodada | Nota | Status |
|---|---|---|
| 1 | — | pending |
