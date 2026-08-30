# Segmento 06 — AppBar (Header Principal)

- **Onda**: 1
- **Depende de**: 00-design-system
- **Escopo de arquivos**: `mobile/lib/core/widgets/app_bar.dart` ou similar

## Entregável
AppBar reutilizável com:
- Título centralizado ou à esquerda
- Ícones de ação à direita (máx 2–3 ícones)
- Suporta volta/back button à esquerda
- Elevação/sombra sutil
- Bem espaçado (padding 16 dp)
- Status bar aware (safe area em notch, etc)

## Critérios de aceitação
1. Título é legível (tamanho 16–18 sp, font weight claro)
2. Back button é um ícone claro (chevron left ou seta)
3. Action icons têm espaçamento entre eles (gap 16 dp aprox)
4. Sombra é sutil (não muito preto)
5. Altura é adequada (56–64 dp em mobile)
6. Safe area é respeitada (notch não sobrepõe conteúdo)
7. Dark mode: título e ícones legíveis
8. Action buttons têm tamanho tátil (48x48 dp mínimo)

## Benchmark
Material Design 3 AppBar ou design iOS. Limpo, profissional, espaçado.

## Método de verificação
- Nível: 1 (screenshot)
- Ferramenta: App emulador em múltiplos dispositivos/orientações

### Roteiro de experiência
1. Abrir app em diferentes telas (home, settings, email detail)
2. Tirar screenshot de cada uma
3. Observar AppBar em cada contexto
4. Observar: título é sempre claro?
5. Observar: back button está presente/ausente conforme necessário?
6. Observar: action icons são visíveis e bem espaçados?
7. Testar com notch (iPhone 12+) → conteúdo não sobrepõe?

## Histórico de notas
| Rodada | Nota | Status |
|---|---|---|
| 1 | — | pending |
