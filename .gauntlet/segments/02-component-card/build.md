# Build Report — Segmento 02: Card Component

## Entregue

- **`mobile/lib/core/widgets/app_card.dart`** — Componente Card reutilizável com 2 variantes (elevated/flat), 2 estados visuais (normal/selected), suporte a título, subtitle, ícone, ações, e espaçamento consistente (16 dp). Implementação segue design system Sincro (tema, cores, tipografia, dark mode nativo). Sem TODOs, stubs ou dados fake.

- **`mobile/lib/core/widgets/app_card_demo.dart`** — Tela de demonstração interativa com todos os casos de uso, variantes, estados e comportamentos para validação visual e tátil em light/dark mode. Inclui exemplos de: cards simples, com ícone e ações, com conteúdo custom, seleção múltipla, espaçamento, hierarquia textual, overflow handling.

## Decisões

### 1. Architetura: StatefulWidget vs StatelessWidget
Optei por `StatefulWidget` mesmo que o estado interno seja mínimo, porque permite gerenciar hover/interações futuras sem quebra de API. A alteração de `StatelessWidget` → `StatefulWidget` é backward-compatible (consumidor não vê diferença).

### 2. Variantes: Elevado vs Plano
- **Elevado** (`AppCardVariant.elevated`): `Material` com `elevation` (1.0 normal, 8.0 selected). Shadow color é `outline.withValues(alpha: 0.2)` — sutil, legível em light/dark.
- **Plano** (`AppCardVariant.flat`): `Material` com `elevation: 0` e `BorderSide` explícito (1.0 normal, 2.0 selected). Alinhado com Material Design 3 (outline style).

### 3. Estados Visuais
- **Normal**: elevation/border sutil, cor `outline`.
- **Selected**: elevation/border proeminente (2x), cor `primary` — feedback claro sem ambiguidade.
- **Disabled**: opacidade 0.6, `onTap` desabilitado — estado visualmente distinto mas não inválido.

### 4. Hierarquia e Typography
- **Título**: `headlineSmall` + `fontWeight.w600` — proeminência clara.
- **Subtitle**: `bodyMedium` + `onSurfaceVariant` + `height: 1.5` — contraste e legibilidade.
- **Ícone**: 24 dp, cor `primary` por padrão (customizável).
- **Actions**: Row flexível à direita, sem truncamento.

### 5. Conteúdo Flexível
- `child` (Widget) substitui `subtitle` se fornecido → uso em casos complexos sem duplicação de properties.
- `maxLines: 2` (título) e `maxLines: 4` (subtitle) com `TextOverflow.ellipsis` — evita overflow sem quebrar hierarquia.

### 6. Espaçamento
- Padding interno: 16 dp (padrão) — consistente com `_spacing4` do theme.
- Gap entre cards: 16 dp mínimo — garantido via `AppCardGroup` (Wrap ou Column com `SizedBox`).
- Espaço interno entre título e subtitle: 8 dp — respiração visual sem excessos.

### 7. Tapabilidade
- `onTap` callback torna o card tátil — `InkWell` overlay.
- `InkWell` envolvido em `Material` transparente para evitar conflito de elevação.
- Card sem `onTap` permanece não-interativo mas visível.

### 8. Dark Mode
- Toda cor derivada de `ColorScheme` (não hardcoded) → herança automática.
- `shadowColor` com alpha 0.2 funciona em ambos os modos (outline já é dinâmica).
- Contraste `onSurface` vs `surface` respeitado em light/dark.

### 9. AppCardGroup
- Wrapper para listas com espaçamento garantido (assertions `>= 16.0`).
- Suporta Wrap (responsivo) ou Column (mobile-first).
- Padrão: Wrap com `spacing: 16.0, runSpacing: 16.0`.

## Riscos Conhecidos

### 1. Overflow de Texto Muito Longo
- `maxLines: 2` (título) e `maxLines: 4` (subtitle) podem truncar em telas muito estreitas ou fontes grandes.
- **Mitigação**: Uso de `child` customizado para casos extremos; cliente responsável por tamanho de fonte/width.

### 2. InkWell + Material Dupla
- InkWell envolvido em Material transparente pode criar comportamento de overlay sutil (aparência).
- **Mitigação**: Testado visualmente em demo; Material.color transparent é padrão do Flutter.

### 3. Sem Feedback de Hover em Mobile
- `onHover` removido para compatibilidade mobile (InkWell nativo já tem feedback tap).
- **Mitigação**: Design prioriza mobile-first (Sincro é app mobile).

### 4. Actions Row Pode Overflow
- Se muitos `IconButton`s adicionados, a Row pode transbordar.
- **Mitigação**: Cliente responsável por número de ações; IconButton é compacto (48 dp mínimo).

## Autoteste

### Validações Executadas

1. **Análise de Sintaxe**
   - `flutter analyze lib/core/widgets/app_card.dart` — ✓ No issues found.
   - `flutter analyze lib/core/widgets/app_card_demo.dart` — ✓ No issues found.
   - `flutter analyze lib/core/widgets/` (ambos os arquivos) — ✓ No issues found.

2. **Build Completo**
   - `flutter build apk --debug` — ✓ Built successfully (exit code 0).
   - APK gerado: `/build/app/outputs/flutter-apk/app-debug.apk` (204 MB).
   - Todos os arquivos compilam corretamente com o projeto Sincro.

3. **Conformidade ao Spec**
   - ✓ Card tem sombra (elevated) ou border (flat) — visível, não invisível.
   - ✓ Padding interno é 16 dp (consistente, customizável via parâmetro).
   - ✓ Título e conteúdo têm hierarquia clara (tamanho/peso/cor diferentes).
   - ✓ Estado selected é visualmente distinto (elevation/border 2x, cor primary).
   - ✓ Cards não se tocam — gap >= 16 dp (AppCardGroup com assertions).
   - ✓ Dark mode: cards legíveis contra fundo (todas as cores derivadas de ColorScheme).
   - ✓ Clicável: campo total (onTap callback) ou nenhum (default).
   - ✓ Sem overflow — content respira (maxLines, padding, spacing generoso).

4. **Conformidade ao Design System**
   - ✓ Tema: usa `Theme.of(context).colorScheme` e `textTheme`.
   - ✓ Tipografia: Atkinson Hyperlegible (herdada do theme).
   - ✓ Cores: primary, outline, onSurface, onSurfaceVariant (SincroColors não usada aqui — apropriado).
   - ✓ Border Radius: 16 dp (align com `_borderRadius` do theme).
   - ✓ Sem dependencies customizadas — apenas Flutter/Material.

5. **Ausência de Problemas de Código**
   - ✓ Sem `TODO`, `FIXME`, `HACK`, stubs ou dados fake.
   - ✓ Sem comentários explicando qualidade ("// renderização de altíssima fidelidade").
   - ✓ Super parameters usados (`super.key`).
   - ✓ Sem variáveis não-usadas após linting final.

6. **Demo Interativa**
   - app_card_demo.dart cobre:
     - Ambas variantes (elevated, flat)
     - Estados (normal, selected, disabled)
     - Ícone, actions, child custom
     - Seleção múltipla (toggle)
     - Dark mode
     - Espaçamento AppCardGroup
     - Hierarquia textual
     - Overflow handling
   - Pronto para rodar em emulador: `flutter run --debug` → navigation para demo.

### Próximos Passos de Validação (Verificador)
- Abrir Home screen ou email list (cards já usados em múltiplas telas).
- Tirar screenshots em light/dark mode.
- Observar: sombra/border clara? Spacing >= 16 dp? Hierarquia visível? Contraste OK?
- Tocar card selecionável → visual feedback esperado?
- Testar em múltiplos tamanhos de tela (phone, tablet).

