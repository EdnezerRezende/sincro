# Guia rápido do app Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a dedicated "guide" screen that explains each app area in one line, shown automatically the first time a user reaches Home, reopenable from Settings, and that shows only new entries automatically after a future update.

**Architecture:** A static, versioned list of `GuideItem`s in code, a `SharedPreferencesAsync`-backed `GuidePreference` tracking the last version a device has seen, a pure filter function selecting which items are pending, and one `GuideScreen` reused by both the automatic (Home) and manual (Settings) entry points with a different item list/title.

**Tech Stack:** Flutter, Riverpod, `shared_preferences` (`SharedPreferencesAsync`) — same stack already used by `BiofeedbackCache`/`HomeLayoutPreference`. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-08-16-guia-do-app-design.md`

## Global Constraints

- No new pubspec dependency (no `package_info_plus`) — versioning is a hand-bumped `int guiaVersaoAtual` constant, same convention as `BiofeedbackCache.versaoPermissoesAtual`.
- Local-only persistence via `SharedPreferencesAsync` (never the legacy `SharedPreferences.getInstance()` singleton) — same convention as `BiofeedbackCache`/`HomeLayoutPreference`.
- `GuideScreen` is not a named route in `mobile/lib/main.dart` — it's opened via `Navigator.push(MaterialPageRoute(builder: ...))`, matching how `EmailDetailScreen`/`AdminGroundingCardFormScreen` are opened.
- No hardcoded colors — use `Theme.of(context)` / `context.sincroColors` (`mobile/lib/core/theme.dart`).
- No `pumpWidget` test for `GuideScreen` — this codebase's established convention is manual verification for screens; only pure-logic/preference classes get unit tests.
- All Portuguese UI copy, matching the rest of the app.

---

### Task 1: `GuideItem` model, content list, and the pending-items filter

**Files:**
- Create: `mobile/lib/features/guide/guide_item.dart`
- Create: `mobile/lib/features/guide/guide_content.dart`
- Test: `mobile/test/features/guide/guide_content_test.dart`

**Interfaces:**
- Produces: `class GuideItem { final IconData icon; final String title; final String description; final int version; }` (all fields `required` via a `const` constructor)
- Produces: `const int guiaVersaoAtual` (value `1`)
- Produces: `const List<GuideItem> guideItems` (8 items, all `version: 1`)
- Produces: `List<GuideItem> itemsToShow(List<GuideItem> items, int versaoVista)`

- [ ] **Step 1: Write `guide_item.dart`**

```dart
import 'package:flutter/material.dart';

class GuideItem {
  const GuideItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.version,
  });

  final IconData icon;
  final String title;
  final String description;
  final int version;
}
```

- [ ] **Step 2: Write the failing test for `itemsToShow`**

Create `mobile/test/features/guide/guide_content_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/guide/guide_content.dart';
import 'package:sincro_mobile/features/guide/guide_item.dart';
import 'package:flutter/material.dart';

void main() {
  const itemV1 = GuideItem(
    icon: Icons.home_outlined,
    title: 'Item v1',
    description: 'desc',
    version: 1,
  );
  const itemV2 = GuideItem(
    icon: Icons.star_outline,
    title: 'Item v2',
    description: 'desc',
    version: 2,
  );
  final items = [itemV1, itemV2];

  test('returns every item when nothing was ever seen (versaoVista 0)', () {
    expect(itemsToShow(items, 0), [itemV1, itemV2]);
  });

  test('returns only items newer than the last seen version', () {
    expect(itemsToShow(items, 1), [itemV2]);
  });

  test('returns empty when the last seen version covers everything', () {
    expect(itemsToShow(items, 2), isEmpty);
  });

  test('guideItems has 8 entries, all tagged version 1', () {
    expect(guideItems.length, 8);
    expect(guideItems.every((i) => i.version == 1), isTrue);
  });

  test('guiaVersaoAtual matches the highest version used in guideItems', () {
    final maiorVersaoUsada = guideItems.map((i) => i.version).reduce((a, b) => a > b ? a : b);
    expect(guiaVersaoAtual, maiorVersaoUsada);
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run (from `mobile/`): `flutter test test/features/guide/guide_content_test.dart`
Expected: FAIL — `guide_content.dart` doesn't exist yet (import error).

- [ ] **Step 4: Write `guide_content.dart`**

```dart
import 'package:flutter/material.dart';
import 'guide_item.dart';

const guiaVersaoAtual = 1;

const guideItems = <GuideItem>[
  GuideItem(
    icon: Icons.home_outlined,
    title: 'Home',
    description: 'Veja um resumo do seu dia, ou troque para abas (Hoje, '
        'Finanças, Apoio) nas Configurações.',
    version: 1,
  ),
  GuideItem(
    icon: Icons.account_balance_wallet_outlined,
    title: 'Finanças',
    description: 'Acompanhe seus gastos e receitas conectando suas contas.',
    version: 1,
  ),
  GuideItem(
    icon: Icons.favorite_outline,
    title: 'Biofeedback',
    description: 'O app usa dados do seu smartwatch para identificar sinais '
        'de estresse e sugerir uma pausa.',
    version: 1,
  ),
  GuideItem(
    icon: Icons.mail_outline,
    title: 'E-mails',
    description: 'Receba rascunhos de resposta prontos para e-mails que '
        'chegam na sua caixa.',
    version: 1,
  ),
  GuideItem(
    icon: Icons.people_outline,
    title: 'Contatos de confiança',
    description: 'Pessoas que podem ser acionadas em um momento de crise.',
    version: 1,
  ),
  GuideItem(
    icon: Icons.medical_services_outlined,
    title: 'Profissionais',
    description: 'Encontre profissionais de apoio perto de você.',
    version: 1,
  ),
  GuideItem(
    icon: Icons.spa_outlined,
    title: 'Cartões de acalma-se',
    description: 'Técnicas rápidas de grounding para momentos difíceis.',
    version: 1,
  ),
  GuideItem(
    icon: Icons.sos_outlined,
    title: 'Emergência',
    description: 'Botão de emergência para pedir ajuda rapidamente.',
    version: 1,
  ),
];

/// Mesma função filtra a lista completa (primeira vez, `versaoVista == 0`) e as novidades de uma
/// atualização (`versaoVista > 0`) — não há caminho especial para "guia completo".
List<GuideItem> itemsToShow(List<GuideItem> items, int versaoVista) {
  return items.where((item) => item.version > versaoVista).toList();
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/features/guide/guide_content_test.dart`
Expected: PASS (5 tests)

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/features/guide/guide_item.dart mobile/lib/features/guide/guide_content.dart mobile/test/features/guide/guide_content_test.dart
git commit -m "feat(mobile): add guide content model and pending-items filter"
```

---

### Task 2: `GuidePreference` and its Riverpod provider

**Files:**
- Create: `mobile/lib/features/guide/guide_preference.dart`
- Create: `mobile/lib/features/guide/guide_providers.dart`
- Test: `mobile/test/features/guide/guide_preference_test.dart`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `class GuidePreference { Future<int> getVersaoVista(); Future<void> setVersaoVista(int versao); }`
- Produces: `final guidePreferenceProvider = Provider<GuidePreference>((ref) => GuidePreference());`

- [ ] **Step 1: Write the failing test**

Create `mobile/test/features/guide/guide_preference_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sincro_mobile/features/guide/guide_preference.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  });

  tearDown(() {
    SharedPreferencesAsyncPlatform.instance = null;
  });

  test('getVersaoVista defaults to 0 when nothing was ever saved', () async {
    final pref = GuidePreference();

    expect(await pref.getVersaoVista(), 0);
  });

  test('setVersaoVista persists the value for later reads', () async {
    final pref = GuidePreference();

    await pref.setVersaoVista(1);

    expect(await pref.getVersaoVista(), 1);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run (from `mobile/`): `flutter test test/features/guide/guide_preference_test.dart`
Expected: FAIL — `guide_preference.dart` doesn't exist yet.

- [ ] **Step 3: Write `guide_preference.dart`**

```dart
import 'package:shared_preferences/shared_preferences.dart';

const _chaveVersaoVista = 'guide_last_seen_version';

/// Preferência local, mesmo padrão de `BiofeedbackCache`/`HomeLayoutPreference`: não sincroniza
/// entre aparelhos nem passa pelo backend, só controla o que este dispositivo já viu.
class GuidePreference {
  late final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  /// `0` quando nada foi salvo: cobre tanto quem nunca abriu o app quanto uma reinstalação —
  /// nesses casos o guia completo deve aparecer.
  Future<int> getVersaoVista() async {
    return await _prefs.getInt(_chaveVersaoVista) ?? 0;
  }

  Future<void> setVersaoVista(int versao) {
    return _prefs.setInt(_chaveVersaoVista, versao);
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/guide/guide_preference_test.dart`
Expected: PASS (2 tests)

- [ ] **Step 5: Write `guide_providers.dart` (no test — trivial Riverpod wiring, same as `home_layout_preference` → `homeLayoutPreferenceProvider`)**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'guide_preference.dart';

final guidePreferenceProvider = Provider<GuidePreference>((ref) {
  return GuidePreference();
});
```

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/features/guide/guide_preference.dart mobile/lib/features/guide/guide_providers.dart mobile/test/features/guide/guide_preference_test.dart
git commit -m "feat(mobile): add GuidePreference for tracking last-seen guide version"
```

---

### Task 3: `GuideScreen` UI

**Files:**
- Create: `mobile/lib/features/guide/guide_screen.dart`

**Interfaces:**
- Consumes: `GuideItem` (Task 1, fields `icon`/`title`/`description`), `guidePreferenceProvider` (Task 2, `.setVersaoVista(int)`), `guiaVersaoAtual` (Task 1).
- Produces: `class GuideScreen extends ConsumerWidget` with constructor `GuideScreen({required List<GuideItem> items, required String title})`. No named route — always opened via `Navigator.push(MaterialPageRoute(builder: (_) => GuideScreen(items: ..., title: ...)))`.

No automated test for this task (screen-level UI, manual verification per this codebase's convention — see Global Constraints).

- [ ] **Step 1: Write `guide_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'guide_content.dart';
import 'guide_item.dart';
import 'guide_providers.dart';

class GuideScreen extends ConsumerWidget {
  const GuideScreen({super.key, required this.items, required this.title});

  final List<GuideItem> items;
  final String title;

  Future<void> _fechar(BuildContext context, WidgetRef ref) async {
    await ref.read(guidePreferenceProvider).setVersaoVista(guiaVersaoAtual);
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              children: items.map((item) {
                return ListTile(
                  leading: Icon(item.icon),
                  title: Text(item.title),
                  subtitle: Text(item.description),
                );
              }).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _fechar(context, ref),
                child: const Text('Entendi'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Verify it compiles and analyzes clean**

Run (from `mobile/`): `flutter analyze lib/features/guide/guide_screen.dart`
Expected: "No issues found!"

- [ ] **Step 3: Commit**

```bash
git add mobile/lib/features/guide/guide_screen.dart
git commit -m "feat(mobile): add GuideScreen UI"
```

---

### Task 4: Wire the automatic trigger into `HomeScreen`

**Files:**
- Modify: `mobile/lib/features/home/home_screen.dart:1-44`

**Interfaces:**
- Consumes: `guidePreferenceProvider`/`GuidePreference.getVersaoVista()` (Task 2), `itemsToShow`/`guideItems` (Task 1), `GuideScreen` (Task 3).

- [ ] **Step 1: Add imports**

In `mobile/lib/features/home/home_screen.dart`, add these two imports alongside the existing feature imports (after the `biofeedback` imports, before `emergency_button.dart`):

```dart
import '../guide/guide_content.dart';
import '../guide/guide_providers.dart';
import '../guide/guide_screen.dart';
```

- [ ] **Step 2: Call `_checkGuide` from `initState`**

Replace:

```dart
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _registerFcmToken());
  }
```

With:

```dart
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _registerFcmToken();
      _checkGuide();
    });
  }
```

- [ ] **Step 3: Add the `_checkGuide` method**

Add right after the existing `_registerFcmToken` method (after its closing `}`, before `@override Widget build`):

```dart
  Future<void> _checkGuide() async {
    final versaoVista = await ref.read(guidePreferenceProvider).getVersaoVista();
    final pendentes = itemsToShow(guideItems, versaoVista);
    if (pendentes.isEmpty || !mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GuideScreen(
          items: pendentes,
          title: versaoVista == 0 ? 'Guia rápido do Sincro' : 'Novidades',
        ),
      ),
    );
  }
```

- [ ] **Step 4: Run analyze and the existing home tests**

Run (from `mobile/`): `flutter analyze lib/features/home/home_screen.dart`
Expected: "No issues found!"

Run: `flutter test test/features/home/`
Expected: all existing tests still PASS (no test asserted on `initState`'s exact callback list, so this should be unaffected — if any test does assert on it, update that assertion to account for the new call, not remove the guide check).

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/home/home_screen.dart
git commit -m "feat(mobile): auto-show the guide on first Home visit"
```

---

### Task 5: Wire the manual entry into `SettingsScreen`

**Files:**
- Modify: `mobile/lib/features/settings/settings_screen.dart:1-14` (imports), `:477` (new section before "Conta"), and a new handler method near `:77` (after `_editHomeLayout`)

**Interfaces:**
- Consumes: `guideItems` (Task 1), `GuideScreen` (Task 3). Always passes the full `guideItems` list — manual reopen ignores `versaoVista` by design (see spec).

- [ ] **Step 1: Add imports**

In `mobile/lib/features/settings/settings_screen.dart`, add alongside the existing feature imports (after `../financas/finance_providers.dart`, before `../home/home_layout_mode.dart`):

```dart
import '../guide/guide_content.dart';
import '../guide/guide_screen.dart';
```

- [ ] **Step 2: Add the `_abrirGuia` handler**

Add right after the closing `}` of `_editHomeLayout` (the method starting at line 77), before `_manageContacts`/whatever method follows it:

```dart
  Future<void> _abrirGuia() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const GuideScreen(items: guideItems, title: 'Guia rápido do Sincro'),
      ),
    );
  }
```

- [ ] **Step 3: Add the "Ajuda" section and its `ListTile`**

Find this line (currently right before the final "Conta" section):

```dart
          const _SectionHeader('Conta'),
```

Replace it with:

```dart
          const _SectionHeader('Ajuda'),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Ver guia do app'),
            onTap: _busy ? null : _abrirGuia,
          ),
          const _SectionHeader('Conta'),
```

- [ ] **Step 4: Run analyze and existing settings tests**

Run (from `mobile/`): `flutter analyze lib/features/settings/settings_screen.dart`
Expected: "No issues found!"

Run: `flutter test test/features/settings/`
Expected: all existing tests still PASS.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/settings/settings_screen.dart
git commit -m "feat(mobile): add manual guide entry to Settings"
```

---

### Task 6: Full verification pass

**Files:** none (verification only)

- [ ] **Step 1: Run the full mobile test suite**

Run (from `mobile/`): `flutter test`
Expected: all tests PASS, including the new `guide_content_test.dart` and `guide_preference_test.dart`.

- [ ] **Step 2: Run full analyze**

Run (from `mobile/`): `flutter analyze`
Expected: "No issues found!"

- [ ] **Step 3: Manual verification checklist (report results, don't skip)**

Since `GuideScreen` has no automated widget test, confirm manually (device/emulator or `flutter run`):
- A fresh install (or `SharedPreferencesAsync` cleared) shows the full 8-item guide automatically the first time Home loads, titled "Guia rápido do Sincro".
- Tapping "Entendi" closes it and returns to Home; relaunching the app does NOT show it again.
- Settings → "Ver guia do app" reopens the full 8-item list every time, regardless of prior state.

No commit for this task — it's a checkpoint, not a code change.
