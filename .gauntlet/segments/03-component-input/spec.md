# Segmento 03 — Componente Input (Text Field)

- **Onda**: 0
- **Depende de**: 00-design-system
- **Escopo de arquivos**: `mobile/lib/core/widgets/app_input.dart` ou similar

## Entregável
Input text reutilizável com:
- Estados: default, focused, filled, error, disabled
- Placeholder visível e informativo
- Label acima do field (não dentro)
- Error message clara abaixo se houver
- Ícone de helper (info, clear, show-password)
- Tamanho mínimo altura 48 dp

## Critérios de aceitação
1. Label é sempre visível (não vira placeholder só)
2. Focus state tem cor clara (border, shadow ou cor) — sem ambiguidade
3. Error state é visível (texto vermelho, ícone, border vermelha)
4. Placeholder é cinza/opaco (distinção clara do texto digitado)
5. Altura mínima 48 dp para mobile
6. Sem text overflow — trunca ou wraps sensatamente
7. Ícone clear ou show-password tem tamanho/espaçamento tátil (24x24 mínimo)
8. Dark mode: focus/error cores ainda legíveis

## Benchmark
Material Design 3 TextField ou iOS UITextField. Clara hierarquia, estados distinto.

## Método de verificação
- Nível: 2 (interactive)
- Ferramenta: App emulador, teste de toque e digitação

### Roteiro de experiência
1. Abrir tela com form (login, anamnese, etc)
2. Ver input vazio → placeholder é claro?
3. Clicar no input → focus state é notável?
4. Digitar texto → placeholder some, texto é legível?
5. Gerar erro (ex: submit vazio) → error message aparece clara?
6. Observar disabled input → visualmente morto?
7. Testar em dark mode → cores ainda claras?

## Histórico de notas
| Rodada | Nota | Status |
|---|---|---|
| 1 | — | pending |
