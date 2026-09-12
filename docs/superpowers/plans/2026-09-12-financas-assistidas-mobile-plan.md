# Finanças Assistidas — UI Mobile Flutter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Pluggy-based Finanças screen in the Sincro Flutter app with a UI that consumes the new backend endpoints (`/financas/contas`, `/financas/cartoes`, `/financas/lancamentos`, `/financas/resumo`, already merged to `master`), matching the approved design (canvas published at https://claude.ai/code/artifact/e712b5ed-15e7-4c8a-b2e9-e20b38838b6f): a calm Home card, a Finanças screen with "Pendentes de revisão" / "Lançamentos do mês" tabs, and a confirmation bottom sheet.

**Architecture:** New Dart models (`ContaFinanceira`, `CartaoCredito`, `LancamentoFinanceiro`) and a rewritten `FinanceSummary` mirror the backend's JSON shapes exactly (including that `/financas/contas|cartoes|lancamentos` serialize `Decimal` fields as **strings**, while `/financas/resumo` already converts to `number`). Three new repositories (`ContasRepository`, `CartoesRepository`, `LancamentosRepository`) follow the existing `Dio`-based repository pattern. Riverpod providers follow the existing `Provider` (repository) + `FutureProvider.autoDispose` (data) pattern. All Pluggy-specific mobile code (`finance_connection*.dart`, `pluggy_connect_webview_screen.dart`) is deleted.

**Tech Stack:** Flutter 3, Riverpod 3 (`flutter_riverpod: ^3.3.2`), Dio 5 (`dio: ^5.11.0`), `intl: ^0.20.2` for currency/date formatting, `flutter_test` + fakes-by-inheritance for repository/widget tests (this codebase does not use `mocktail` for repository fakes, despite it being a dependency — it uses `Dio` with `InterceptorsWrapper` for repository tests and subclass-overriding fakes for widget tests).

**Spec:** `docs/superpowers/specs/2026-09-12-financas-assistidas-design.md` (see "Mobile: UX" section) and the backend plan `docs/superpowers/plans/2026-09-12-financas-assistidas-plan.md` (already implemented, merged to `master` — this plan's Global Constraints below restate its exact response shapes).

## Global Constraints

- Package name is `sincro_mobile` — all imports in this plan use `package:sincro_mobile/...`.
- `/financas/contas`, `/financas/cartoes`, `/financas/lancamentos` return **raw Prisma rows**: `Decimal` fields (`saldoAtual`, `limiteTotal`, `valor`) are JSON **strings** (e.g. `"1234.56"`), not numbers — parse with `double.parse(json['field'] as String)`. `valor` on `LancamentoFinanceiro` is additionally nullable.
- `/financas/resumo` is the ONE exception: its 5 fields (`saldoLivre`, `saldoContas`, `faturasAbertas`, `despesasPendentesCiclo`) are already converted to JSON numbers by the backend controller; only `cicloFim` is an ISO date string.
- Enum string values (exact, case-sensitive) — `TipoContaFinanceira`: `CORRENTE`, `CARTEIRA`, `POUPANCA`. `TipoLancamento`: `DESPESA`, `RECEITA`, `FATURA_CARTAO`. `StatusLancamento`: `PENDENTE_REVISAO`, `CONFIRMADO`, `IGNORADO`. `OrigemLancamento`: `EMAIL_PARSER`, `MANUAL`. `CartaoCredito` has no `tipo` field — it is always a credit card.
- `webview_flutter` and `url_launcher` in `pubspec.yaml` must NOT be removed even though `pluggy_connect_webview_screen.dart` (which used them) is deleted — both packages are also used by `emergency_button.dart` and `professional_detail_screen.dart`.
- Never show `error`/red for anything in this feature except a genuine failed network request — urgency uses `context.sincroColors.caution`, never a punitive red, matching the app's calm, non-alarmist design philosophy (see spec's "Mobile: UX" section).
- Every new repository method that can fail (network error) lets the `DioException` propagate — do not swallow it — matching the existing `FinanceSummaryRepository`/`DiaRecebimentoRepository` pattern; the UI handles errors with `AsyncValue.when(error: ...)` or a local `try/catch`, not the repository.
- Test convention: repository tests use a real `Dio` with `InterceptorsWrapper` resolving a fake `Response` (no HTTP mocking library); widget tests use `ProviderScope(overrides: [xProvider.overrideWithValue(fake)])` wrapping `MaterialApp(theme: sincroLightTheme, home: TelaReal())`, with fakes built by subclassing the real repository and overriding its methods (not `mocktail`).
- Out of scope for this plan: implementing `RECEITA` as a positive contribution to Saldo Livre (the backend currently excludes it from the calculation entirely — the UI must not imply it affects the balance either), dark-mode screenshots/manual QA (the canvas mockups already validated the palette; this plan wires real data into that already-approved visual design, it does not redesign it), and any change to `dia_recebimento_repository.dart` (already correct, untouched).

---

## Task 1: Dart models — `ContaFinanceira`, `CartaoCredito`, `LancamentoFinanceiro`, rewritten `FinanceSummary`

**Files:**
- Create: `mobile/lib/features/financas/conta_financeira.dart`
- Test: `mobile/test/features/financas/conta_financeira_test.dart`
- Create: `mobile/lib/features/financas/cartao_credito.dart`
- Test: `mobile/test/features/financas/cartao_credito_test.dart`
- Create: `mobile/lib/features/financas/lancamento_financeiro.dart`
- Test: `mobile/test/features/financas/lancamento_financeiro_test.dart`
- Modify: `mobile/lib/features/financas/finance_summary.dart` (full rewrite)
- Modify: `mobile/test/features/financas/finance_summary_test.dart` (create if it doesn't already test the old shape, or rewrite it if it does — check first)

**Interfaces:**
- Produces: `ContaFinanceira` (`id, nome, tipo: TipoContaFinanceira, saldoAtual: double, cor: String?`), `CartaoCredito` (`id, nome, diaFechamento: int, diaVencimento: int, limiteTotal: double, cor: String?`), `LancamentoFinanceiro` (`id, tipo: TipoLancamento, descricao, instituicao: String?, valor: double?, dataVencimento: DateTime, dataCompetencia: DateTime, status: StatusLancamento, origem: OrigemLancamento, isPago: bool, codigoBarras: String?, cartaoId: String?, contaId: String?`), `FinanceSummary` (`saldoLivre, saldoContas, faturasAbertas, despesasPendentesCiclo: double; cicloFim: DateTime`). All with `factory .fromJson(Map<String, dynamic>)`. Consumed by Tasks 2-6 (repositories/providers) and Tasks 8-10 (UI).

- [ ] **Step 1: Check the existing `finance_summary_test.dart`**

```bash
cat mobile/test/features/financas/finance_summary_test.dart 2>&1
```

If it exists and tests the OLD shape (`contas`, `boletos` lists), you will rewrite it in Step 6 below. If it doesn't exist, you create it fresh in Step 6.

- [ ] **Step 2: Write the failing test for `ContaFinanceira`**

`mobile/test/features/financas/conta_financeira_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/financas/conta_financeira.dart';

void main() {
  group('ContaFinanceira.fromJson', () {
    test('parses saldoAtual (sent as a Decimal-string) into a double', () {
      final conta = ContaFinanceira.fromJson({
        'id': 'conta-1',
        'nome': 'Conta corrente',
        'tipo': 'CORRENTE',
        'saldoAtual': '1234.56',
        'cor': '#FF0000',
      });

      expect(conta.id, 'conta-1');
      expect(conta.nome, 'Conta corrente');
      expect(conta.tipo, TipoContaFinanceira.corrente);
      expect(conta.saldoAtual, 1234.56);
      expect(conta.cor, '#FF0000');
    });

    test('cor is null when absent', () {
      final conta = ContaFinanceira.fromJson({
        'id': 'conta-2',
        'nome': 'Carteira',
        'tipo': 'CARTEIRA',
        'saldoAtual': '0.00',
      });
      expect(conta.cor, isNull);
    });

    test('parses POUPANCA', () {
      final conta = ContaFinanceira.fromJson({
        'id': 'conta-3',
        'nome': 'Poupança',
        'tipo': 'POUPANCA',
        'saldoAtual': '500.00',
      });
      expect(conta.tipo, TipoContaFinanceira.poupanca);
    });
  });
}
```

- [ ] **Step 3: Run to verify it fails**

```bash
cd mobile && flutter test test/features/financas/conta_financeira_test.dart
```

Expected: FAIL — `conta_financeira.dart` doesn't exist.

- [ ] **Step 4: Write `conta_financeira.dart`**

```dart
enum TipoContaFinanceira { corrente, carteira, poupanca }

TipoContaFinanceira tipoContaFinanceiraFromJson(String value) {
  switch (value) {
    case 'CORRENTE':
      return TipoContaFinanceira.corrente;
    case 'CARTEIRA':
      return TipoContaFinanceira.carteira;
    case 'POUPANCA':
      return TipoContaFinanceira.poupanca;
    default:
      throw ArgumentError('tipo de conta desconhecido: $value');
  }
}

String tipoContaFinanceiraToJson(TipoContaFinanceira tipo) {
  switch (tipo) {
    case TipoContaFinanceira.corrente:
      return 'CORRENTE';
    case TipoContaFinanceira.carteira:
      return 'CARTEIRA';
    case TipoContaFinanceira.poupanca:
      return 'POUPANCA';
  }
}

class ContaFinanceira {
  const ContaFinanceira({
    required this.id,
    required this.nome,
    required this.tipo,
    required this.saldoAtual,
    this.cor,
  });

  final String id;
  final String nome;
  final TipoContaFinanceira tipo;
  final double saldoAtual;
  final String? cor;

  factory ContaFinanceira.fromJson(Map<String, dynamic> json) {
    return ContaFinanceira(
      id: json['id'] as String,
      nome: json['nome'] as String,
      tipo: tipoContaFinanceiraFromJson(json['tipo'] as String),
      saldoAtual: double.parse(json['saldoAtual'] as String),
      cor: json['cor'] as String?,
    );
  }

  Map<String, dynamic> toCreateJson() => {
        'nome': nome,
        'tipo': tipoContaFinanceiraToJson(tipo),
        'saldoAtual': saldoAtual,
        if (cor != null) 'cor': cor,
      };
}
```

- [ ] **Step 5: Run to verify it passes**

```bash
cd mobile && flutter test test/features/financas/conta_financeira_test.dart
```

Expected: PASS (3 tests).

- [ ] **Step 6: Repeat Steps 2-5 for `CartaoCredito`**

`mobile/test/features/financas/cartao_credito_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/financas/cartao_credito.dart';

void main() {
  test('CartaoCredito.fromJson parses limiteTotal (Decimal-string) into a double', () {
    final cartao = CartaoCredito.fromJson({
      'id': 'cartao-1',
      'nome': 'Nubank',
      'diaFechamento': 5,
      'diaVencimento': 12,
      'limiteTotal': '3000.00',
      'cor': '#8A05BE',
    });

    expect(cartao.id, 'cartao-1');
    expect(cartao.nome, 'Nubank');
    expect(cartao.diaFechamento, 5);
    expect(cartao.diaVencimento, 12);
    expect(cartao.limiteTotal, 3000.0);
    expect(cartao.cor, '#8A05BE');
  });

  test('cor is null when absent', () {
    final cartao = CartaoCredito.fromJson({
      'id': 'cartao-2',
      'nome': 'Itaú',
      'diaFechamento': 1,
      'diaVencimento': 10,
      'limiteTotal': '1500.00',
    });
    expect(cartao.cor, isNull);
  });
}
```

`mobile/lib/features/financas/cartao_credito.dart`:

```dart
class CartaoCredito {
  const CartaoCredito({
    required this.id,
    required this.nome,
    required this.diaFechamento,
    required this.diaVencimento,
    required this.limiteTotal,
    this.cor,
  });

  final String id;
  final String nome;
  final int diaFechamento;
  final int diaVencimento;
  final double limiteTotal;
  final String? cor;

  factory CartaoCredito.fromJson(Map<String, dynamic> json) {
    return CartaoCredito(
      id: json['id'] as String,
      nome: json['nome'] as String,
      diaFechamento: json['diaFechamento'] as int,
      diaVencimento: json['diaVencimento'] as int,
      limiteTotal: double.parse(json['limiteTotal'] as String),
      cor: json['cor'] as String?,
    );
  }

  Map<String, dynamic> toCreateJson() => {
        'nome': nome,
        'diaFechamento': diaFechamento,
        'diaVencimento': diaVencimento,
        'limiteTotal': limiteTotal,
        if (cor != null) 'cor': cor,
      };
}
```

Run: `cd mobile && flutter test test/features/financas/cartao_credito_test.dart` — expect PASS (2 tests).

- [ ] **Step 7: Repeat for `LancamentoFinanceiro`**

`mobile/test/features/financas/lancamento_financeiro_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/financas/lancamento_financeiro.dart';

void main() {
  group('LancamentoFinanceiro.fromJson', () {
    test('parses a fully-populated confirmed lançamento', () {
      final lancamento = LancamentoFinanceiro.fromJson({
        'id': 'lanc-1',
        'tipo': 'FATURA_CARTAO',
        'descricao': 'Sua fatura fechou',
        'instituicao': 'Nubank',
        'valor': '512.40',
        'dataVencimento': '2026-10-10T00:00:00.000Z',
        'dataCompetencia': '2026-10-10T00:00:00.000Z',
        'status': 'CONFIRMADO',
        'origem': 'EMAIL_PARSER',
        'isPago': false,
        'codigoBarras': null,
        'cartaoId': 'cartao-1',
        'contaId': null,
      });

      expect(lancamento.id, 'lanc-1');
      expect(lancamento.tipo, TipoLancamento.faturaCartao);
      expect(lancamento.descricao, 'Sua fatura fechou');
      expect(lancamento.instituicao, 'Nubank');
      expect(lancamento.valor, 512.40);
      expect(lancamento.dataVencimento, DateTime.utc(2026, 10, 10));
      expect(lancamento.status, StatusLancamento.confirmado);
      expect(lancamento.origem, OrigemLancamento.emailParser);
      expect(lancamento.isPago, false);
      expect(lancamento.cartaoId, 'cartao-1');
      expect(lancamento.contaId, isNull);
    });

    test('valor is null when the parser could not extract an amount', () {
      final lancamento = LancamentoFinanceiro.fromJson({
        'id': 'lanc-2',
        'tipo': 'DESPESA',
        'descricao': 'Conta de luz',
        'instituicao': 'Enel',
        'valor': null,
        'dataVencimento': '2026-09-15T00:00:00.000Z',
        'dataCompetencia': '2026-09-15T00:00:00.000Z',
        'status': 'PENDENTE_REVISAO',
        'origem': 'EMAIL_PARSER',
        'isPago': false,
        'codigoBarras': null,
        'cartaoId': null,
        'contaId': null,
      });

      expect(lancamento.valor, isNull);
      expect(lancamento.status, StatusLancamento.pendenteRevisao);
    });

    test('parses MANUAL origem and IGNORADO status', () {
      final lancamento = LancamentoFinanceiro.fromJson({
        'id': 'lanc-3',
        'tipo': 'RECEITA',
        'descricao': 'Freela',
        'instituicao': null,
        'valor': '800.00',
        'dataVencimento': '2026-09-05T00:00:00.000Z',
        'dataCompetencia': '2026-09-05T00:00:00.000Z',
        'status': 'IGNORADO',
        'origem': 'MANUAL',
        'isPago': false,
        'codigoBarras': null,
        'cartaoId': null,
        'contaId': null,
      });

      expect(lancamento.tipo, TipoLancamento.receita);
      expect(lancamento.status, StatusLancamento.ignorado);
      expect(lancamento.origem, OrigemLancamento.manual);
    });
  });
}
```

`mobile/lib/features/financas/lancamento_financeiro.dart`:

```dart
enum TipoLancamento { despesa, receita, faturaCartao }
enum StatusLancamento { pendenteRevisao, confirmado, ignorado }
enum OrigemLancamento { emailParser, manual }

TipoLancamento tipoLancamentoFromJson(String value) {
  switch (value) {
    case 'DESPESA':
      return TipoLancamento.despesa;
    case 'RECEITA':
      return TipoLancamento.receita;
    case 'FATURA_CARTAO':
      return TipoLancamento.faturaCartao;
    default:
      throw ArgumentError('tipo de lançamento desconhecido: $value');
  }
}

StatusLancamento statusLancamentoFromJson(String value) {
  switch (value) {
    case 'PENDENTE_REVISAO':
      return StatusLancamento.pendenteRevisao;
    case 'CONFIRMADO':
      return StatusLancamento.confirmado;
    case 'IGNORADO':
      return StatusLancamento.ignorado;
    default:
      throw ArgumentError('status de lançamento desconhecido: $value');
  }
}

String statusLancamentoToJson(StatusLancamento status) {
  switch (status) {
    case StatusLancamento.pendenteRevisao:
      return 'PENDENTE_REVISAO';
    case StatusLancamento.confirmado:
      return 'CONFIRMADO';
    case StatusLancamento.ignorado:
      return 'IGNORADO';
  }
}

OrigemLancamento origemLancamentoFromJson(String value) {
  switch (value) {
    case 'EMAIL_PARSER':
      return OrigemLancamento.emailParser;
    case 'MANUAL':
      return OrigemLancamento.manual;
    default:
      throw ArgumentError('origem de lançamento desconhecida: $value');
  }
}

class LancamentoFinanceiro {
  const LancamentoFinanceiro({
    required this.id,
    required this.tipo,
    required this.descricao,
    required this.instituicao,
    required this.valor,
    required this.dataVencimento,
    required this.dataCompetencia,
    required this.status,
    required this.origem,
    required this.isPago,
    required this.codigoBarras,
    required this.cartaoId,
    required this.contaId,
  });

  final String id;
  final TipoLancamento tipo;
  final String descricao;
  final String? instituicao;
  final double? valor;
  final DateTime dataVencimento;
  final DateTime dataCompetencia;
  final StatusLancamento status;
  final OrigemLancamento origem;
  final bool isPago;
  final String? codigoBarras;
  final String? cartaoId;
  final String? contaId;

  factory LancamentoFinanceiro.fromJson(Map<String, dynamic> json) {
    final valorRaw = json['valor'] as String?;
    return LancamentoFinanceiro(
      id: json['id'] as String,
      tipo: tipoLancamentoFromJson(json['tipo'] as String),
      descricao: json['descricao'] as String,
      instituicao: json['instituicao'] as String?,
      valor: valorRaw == null ? null : double.parse(valorRaw),
      dataVencimento: DateTime.parse(json['dataVencimento'] as String),
      dataCompetencia: DateTime.parse(json['dataCompetencia'] as String),
      status: statusLancamentoFromJson(json['status'] as String),
      origem: origemLancamentoFromJson(json['origem'] as String),
      isPago: json['isPago'] as bool,
      codigoBarras: json['codigoBarras'] as String?,
      cartaoId: json['cartaoId'] as String?,
      contaId: json['contaId'] as String?,
    );
  }
}
```

Run: `cd mobile && flutter test test/features/financas/lancamento_financeiro_test.dart` — expect PASS (3 tests).

- [ ] **Step 8: Rewrite `finance_summary.dart` and its test**

`mobile/test/features/financas/finance_summary_test.dart` (replace entirely if it tested the old shape):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/financas/finance_summary.dart';

void main() {
  test('FinanceSummary.fromJson parses the 5-field resumo shape', () {
    final summary = FinanceSummary.fromJson({
      'saldoLivre': 1234.56,
      'saldoContas': 2000.0,
      'faturasAbertas': 450.0,
      'despesasPendentesCiclo': 300.0,
      'cicloFim': '2026-09-30T00:00:00.000Z',
    });

    expect(summary.saldoLivre, 1234.56);
    expect(summary.saldoContas, 2000.0);
    expect(summary.faturasAbertas, 450.0);
    expect(summary.despesasPendentesCiclo, 300.0);
    expect(summary.cicloFim, DateTime.utc(2026, 9, 30));
  });
}
```

`mobile/lib/features/financas/finance_summary.dart` (full replacement):

```dart
class FinanceSummary {
  const FinanceSummary({
    required this.saldoLivre,
    required this.saldoContas,
    required this.faturasAbertas,
    required this.despesasPendentesCiclo,
    required this.cicloFim,
  });

  final double saldoLivre;
  final double saldoContas;
  final double faturasAbertas;
  final double despesasPendentesCiclo;
  final DateTime cicloFim;

  factory FinanceSummary.fromJson(Map<String, dynamic> json) {
    return FinanceSummary(
      saldoLivre: (json['saldoLivre'] as num).toDouble(),
      saldoContas: (json['saldoContas'] as num).toDouble(),
      faturasAbertas: (json['faturasAbertas'] as num).toDouble(),
      despesasPendentesCiclo: (json['despesasPendentesCiclo'] as num).toDouble(),
      cicloFim: DateTime.parse(json['cicloFim'] as String),
    );
  }
}
```

Run: `cd mobile && flutter test test/features/financas/finance_summary_test.dart` — expect PASS (1 test).

- [ ] **Step 9: Run the whole financas test directory, then commit**

```bash
cd mobile && flutter test test/features/financas/
git add lib/features/financas/conta_financeira.dart lib/features/financas/cartao_credito.dart \
  lib/features/financas/lancamento_financeiro.dart lib/features/financas/finance_summary.dart \
  test/features/financas/conta_financeira_test.dart test/features/financas/cartao_credito_test.dart \
  test/features/financas/lancamento_financeiro_test.dart test/features/financas/finance_summary_test.dart
git commit -m "feat(financas-mobile): novos models Dart (ContaFinanceira, CartaoCredito, LancamentoFinanceiro, FinanceSummary)"
```

---

## Task 2: `ContasRepository`

**Files:**
- Create: `mobile/lib/features/financas/contas_repository.dart`
- Test: `mobile/test/features/financas/contas_repository_test.dart`

**Interfaces:**
- Consumes: `ContaFinanceira` from Task 1.
- Produces: `ContasRepository(Dio)` with `Future<List<ContaFinanceira>> list()`, `Future<ContaFinanceira> create(ContaFinanceira conta)`, `Future<void> remove(String id)`. Consumed by Task 6's providers.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/financas/contas_repository.dart';
import 'package:sincro_mobile/features/financas/conta_financeira.dart';

void main() {
  test('list() GETs /financas/contas and parses the array', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      expect(options.path, '/financas/contas');
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: [
          {'id': 'c1', 'nome': 'Conta corrente', 'tipo': 'CORRENTE', 'saldoAtual': '100.00'},
        ],
      ));
    }));
    final repository = ContasRepository(dio);

    final contas = await repository.list();

    expect(contas, hasLength(1));
    expect(contas.first.nome, 'Conta corrente');
    expect(contas.first.saldoAtual, 100.0);
  });

  test('create() POSTs to /financas/contas with the account payload', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      expect(options.path, '/financas/contas');
      expect(options.data, {'nome': 'Poupança', 'tipo': 'POUPANCA', 'saldoAtual': 50.0});
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 201,
        data: {'id': 'c2', 'nome': 'Poupança', 'tipo': 'POUPANCA', 'saldoAtual': '50.00'},
      ));
    }));
    final repository = ContasRepository(dio);

    final conta = await repository.create(
      const ContaFinanceira(id: '', nome: 'Poupança', tipo: TipoContaFinanceira.poupanca, saldoAtual: 50.0),
    );

    expect(conta.id, 'c2');
  });

  test('remove() DELETEs /financas/contas/:id', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      expect(options.path, '/financas/contas/c1');
      expect(options.method, 'DELETE');
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: {'removed': true}));
    }));
    final repository = ContasRepository(dio);

    await repository.remove('c1');
  });
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd mobile && flutter test test/features/financas/contas_repository_test.dart
```

Expected: FAIL — `contas_repository.dart` doesn't exist.

- [ ] **Step 3: Write `contas_repository.dart`**

```dart
import 'package:dio/dio.dart';
import 'conta_financeira.dart';

class ContasRepository {
  ContasRepository(this._dio);

  final Dio _dio;

  Future<List<ContaFinanceira>> list() async {
    final response = await _dio.get('/financas/contas');
    return (response.data as List)
        .map((json) => ContaFinanceira.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<ContaFinanceira> create(ContaFinanceira conta) async {
    final response = await _dio.post('/financas/contas', data: conta.toCreateJson());
    return ContaFinanceira.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> remove(String id) async {
    await _dio.delete('/financas/contas/$id');
  }
}
```

- [ ] **Step 4: Run to verify it passes, then commit**

```bash
cd mobile && flutter test test/features/financas/contas_repository_test.dart
git add lib/features/financas/contas_repository.dart test/features/financas/contas_repository_test.dart
git commit -m "feat(financas-mobile): ContasRepository (list/create/remove)"
```

---

## Task 3: `CartoesRepository`

**Files:**
- Create: `mobile/lib/features/financas/cartoes_repository.dart`
- Test: `mobile/test/features/financas/cartoes_repository_test.dart`

**Interfaces:**
- Consumes: `CartaoCredito` from Task 1.
- Produces: `CartoesRepository(Dio)` with `Future<List<CartaoCredito>> list()`, `Future<CartaoCredito> create(CartaoCredito cartao)`, `Future<void> remove(String id)`. Consumed by Task 6.

This task mirrors Task 2 exactly, applied to `CartaoCredito`/`/financas/cartoes`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/financas/cartoes_repository.dart';
import 'package:sincro_mobile/features/financas/cartao_credito.dart';

void main() {
  test('list() GETs /financas/cartoes and parses the array', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      expect(options.path, '/financas/cartoes');
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: [
          {'id': 'k1', 'nome': 'Nubank', 'diaFechamento': 5, 'diaVencimento': 12, 'limiteTotal': '3000.00'},
        ],
      ));
    }));
    final repository = CartoesRepository(dio);

    final cartoes = await repository.list();

    expect(cartoes, hasLength(1));
    expect(cartoes.first.nome, 'Nubank');
    expect(cartoes.first.limiteTotal, 3000.0);
  });

  test('create() POSTs to /financas/cartoes with the card payload', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      expect(options.path, '/financas/cartoes');
      expect(options.data, {'nome': 'Itaú', 'diaFechamento': 1, 'diaVencimento': 10, 'limiteTotal': 1500.0});
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 201,
        data: {'id': 'k2', 'nome': 'Itaú', 'diaFechamento': 1, 'diaVencimento': 10, 'limiteTotal': '1500.00'},
      ));
    }));
    final repository = CartoesRepository(dio);

    final cartao = await repository.create(
      const CartaoCredito(id: '', nome: 'Itaú', diaFechamento: 1, diaVencimento: 10, limiteTotal: 1500.0),
    );

    expect(cartao.id, 'k2');
  });

  test('remove() DELETEs /financas/cartoes/:id', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      expect(options.path, '/financas/cartoes/k1');
      expect(options.method, 'DELETE');
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: {'removed': true}));
    }));
    final repository = CartoesRepository(dio);

    await repository.remove('k1');
  });
}
```

- [ ] **Step 2: Run to verify it fails, then write `cartoes_repository.dart`**

```dart
import 'package:dio/dio.dart';
import 'cartao_credito.dart';

class CartoesRepository {
  CartoesRepository(this._dio);

  final Dio _dio;

  Future<List<CartaoCredito>> list() async {
    final response = await _dio.get('/financas/cartoes');
    return (response.data as List)
        .map((json) => CartaoCredito.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<CartaoCredito> create(CartaoCredito cartao) async {
    final response = await _dio.post('/financas/cartoes', data: cartao.toCreateJson());
    return CartaoCredito.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> remove(String id) async {
    await _dio.delete('/financas/cartoes/$id');
  }
}
```

- [ ] **Step 3: Run to verify it passes, then commit**

```bash
cd mobile && flutter test test/features/financas/cartoes_repository_test.dart
git add lib/features/financas/cartoes_repository.dart test/features/financas/cartoes_repository_test.dart
git commit -m "feat(financas-mobile): CartoesRepository (list/create/remove)"
```

---

## Task 4: `LancamentosRepository`

**Files:**
- Create: `mobile/lib/features/financas/lancamentos_repository.dart`
- Test: `mobile/test/features/financas/lancamentos_repository_test.dart`

**Interfaces:**
- Consumes: `LancamentoFinanceiro` from Task 1.
- Produces: `LancamentosRepository(Dio)` with `Future<List<LancamentoFinanceiro>> list({String? status, String? mes})`, `Future<void> confirmar(String id, {double? valor, DateTime? dataVencimento, String? contaId, String? cartaoId})`, `Future<void> ignorar(String id)`. Consumed by Task 6 (providers) and Task 10 (confirmation sheet).

- [ ] **Step 1: Write the failing test**

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/financas/lancamentos_repository.dart';

void main() {
  test('list() GETs /financas/lancamentos with status and mes query params', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      expect(options.path, '/financas/lancamentos');
      expect(options.queryParameters, {'status': 'PENDENTE_REVISAO', 'mes': '2026-09'});
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: [
          {
            'id': 'l1', 'tipo': 'DESPESA', 'descricao': 'Conta de luz', 'instituicao': 'Enel',
            'valor': '150.30', 'dataVencimento': '2026-09-15T00:00:00.000Z',
            'dataCompetencia': '2026-09-15T00:00:00.000Z', 'status': 'PENDENTE_REVISAO',
            'origem': 'EMAIL_PARSER', 'isPago': false, 'codigoBarras': null,
            'cartaoId': null, 'contaId': null,
          },
        ],
      ));
    }));
    final repository = LancamentosRepository(dio);

    final lancamentos = await repository.list(status: 'PENDENTE_REVISAO', mes: '2026-09');

    expect(lancamentos, hasLength(1));
    expect(lancamentos.first.descricao, 'Conta de luz');
  });

  test('list() omits absent query params entirely', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      expect(options.queryParameters, isEmpty);
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: <dynamic>[]));
    }));
    final repository = LancamentosRepository(dio);

    await repository.list();
  });

  test('confirmar() PATCHes /financas/lancamentos/:id/confirmar with only the provided fields', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      expect(options.path, '/financas/lancamentos/l1/confirmar');
      expect(options.method, 'PATCH');
      expect(options.data, {'valor': 512.40});
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: {}));
    }));
    final repository = LancamentosRepository(dio);

    await repository.confirmar('l1', valor: 512.40);
  });

  test('ignorar() PATCHes /financas/lancamentos/:id/ignorar with no body', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      expect(options.path, '/financas/lancamentos/l1/ignorar');
      expect(options.method, 'PATCH');
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: {}));
    }));
    final repository = LancamentosRepository(dio);

    await repository.ignorar('l1');
  });
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd mobile && flutter test test/features/financas/lancamentos_repository_test.dart
```

- [ ] **Step 3: Write `lancamentos_repository.dart`**

```dart
import 'package:dio/dio.dart';
import 'lancamento_financeiro.dart';

class LancamentosRepository {
  LancamentosRepository(this._dio);

  final Dio _dio;

  Future<List<LancamentoFinanceiro>> list({String? status, String? mes}) async {
    final queryParameters = <String, dynamic>{
      if (status != null) 'status': status,
      if (mes != null) 'mes': mes,
    };
    final response = await _dio.get('/financas/lancamentos', queryParameters: queryParameters);
    return (response.data as List)
        .map((json) => LancamentoFinanceiro.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<void> confirmar(
    String id, {
    double? valor,
    DateTime? dataVencimento,
    String? contaId,
    String? cartaoId,
  }) async {
    final data = <String, dynamic>{
      if (valor != null) 'valor': valor,
      if (dataVencimento != null) 'dataVencimento': dataVencimento.toIso8601String(),
      if (contaId != null) 'contaId': contaId,
      if (cartaoId != null) 'cartaoId': cartaoId,
    };
    await _dio.patch('/financas/lancamentos/$id/confirmar', data: data);
  }

  Future<void> ignorar(String id) async {
    await _dio.patch('/financas/lancamentos/$id/ignorar');
  }
}
```

- [ ] **Step 4: Run to verify it passes, then commit**

```bash
cd mobile && flutter test test/features/financas/lancamentos_repository_test.dart
git add lib/features/financas/lancamentos_repository.dart test/features/financas/lancamentos_repository_test.dart
git commit -m "feat(financas-mobile): LancamentosRepository (list/confirmar/ignorar)"
```

---

## Task 5: Rewrite `FinanceSummaryRepository`

**Files:**
- Modify: `mobile/lib/features/financas/finance_summary_repository.dart`
- Modify: `mobile/test/features/financas/finance_summary_repository_test.dart`

**Interfaces:**
- Consumes: `FinanceSummary` from Task 1.
- Produces: `FinanceSummaryRepository(Dio)` with `Future<FinanceSummary> getResumo()` — the SAME method name/signature as before (so Task 6 barely has to touch its provider), but `sync()` is REMOVED (the `/financas/sync` endpoint no longer exists on the backend).

- [ ] **Step 1: Read the current file and its test**

```bash
cat mobile/lib/features/financas/finance_summary_repository.dart
cat mobile/test/features/financas/finance_summary_repository_test.dart
```

- [ ] **Step 2: Update the test to remove the `sync()` test case and keep/update `getResumo()`**

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/financas/finance_summary_repository.dart';

void main() {
  test('getResumo() GETs /financas/resumo and parses the 5-field shape', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      expect(options.path, '/financas/resumo');
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: {
          'saldoLivre': 1234.56,
          'saldoContas': 2000.0,
          'faturasAbertas': 450.0,
          'despesasPendentesCiclo': 300.0,
          'cicloFim': '2026-09-30T00:00:00.000Z',
        },
      ));
    }));
    final repository = FinanceSummaryRepository(dio);

    final resumo = await repository.getResumo();

    expect(resumo.saldoLivre, 1234.56);
  });
}
```

- [ ] **Step 3: Rewrite `finance_summary_repository.dart`, removing `sync()`**

```dart
import 'package:dio/dio.dart';
import 'finance_summary.dart';

class FinanceSummaryRepository {
  FinanceSummaryRepository(this._dio);

  final Dio _dio;

  Future<FinanceSummary> getResumo() async {
    final response = await _dio.get('/financas/resumo');
    return FinanceSummary.fromJson(response.data as Map<String, dynamic>);
  }
}
```

- [ ] **Step 4: Run to verify it passes**

```bash
cd mobile && flutter test test/features/financas/finance_summary_repository_test.dart
```

- [ ] **Step 5: Check for other callers of the removed `sync()` method**

```bash
cd mobile && grep -rn "\.sync()" lib/ test/
```

Every hit needs its caller updated in Task 8/9 (the Home screen and/or Finanças screen previously called `sync()` to trigger a Pluggy refresh — that call is simply removed, there is no replacement, since email-driven staging happens server-side automatically now). Note what you find here for Task 9 to act on; do not fix call sites in this task if they belong to files rewritten by a later task (avoid duplicate work) — but if a file NOT touched by any later task calls `.sync()`, fix it now.

- [ ] **Step 6: Commit**

```bash
git add lib/features/financas/finance_summary_repository.dart test/features/financas/finance_summary_repository_test.dart
git commit -m "feat(financas-mobile): remove sync() do FinanceSummaryRepository (endpoint nao existe mais)"
```

---

## Task 6: Rewrite `finance_providers.dart`

**Files:**
- Modify: `mobile/lib/features/financas/finance_providers.dart`

**Interfaces:**
- Consumes: `ContasRepository`, `CartoesRepository`, `LancamentosRepository` (Tasks 2-4), rewritten `FinanceSummaryRepository` (Task 5), existing `apiClientProvider` (from `mobile/lib/core/api_providers.dart`, untouched), existing `diaRecebimentoRepositoryProvider` (untouched, kept as-is).
- Produces: `contasRepositoryProvider`, `contasProvider` (`FutureProvider.autoDispose<List<ContaFinanceira>>`), `cartoesRepositoryProvider`, `cartoesProvider`, `lancamentosRepositoryProvider`, `lancamentosPendentesProvider` (`FutureProvider.autoDispose<List<LancamentoFinanceiro>>`, calls `list(status: 'PENDENTE_REVISAO')`), `lancamentosDoMesProvider` (`FutureProvider.autoDispose.family<List<LancamentoFinanceiro>, String>` keyed by the `"YYYY-MM"` month string, calls `list(status: 'CONFIRMADO', mes: mes)`), `financeSummaryRepositoryProvider`/`financeSummaryProvider` (kept, same names as before). Consumed by Tasks 8-10 (all UI).

- [ ] **Step 1: Read the current file**

```bash
cat mobile/lib/features/financas/finance_providers.dart
```

- [ ] **Step 2: Rewrite it**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_providers.dart';
import 'cartao_credito.dart';
import 'cartoes_repository.dart';
import 'conta_financeira.dart';
import 'contas_repository.dart';
import 'dia_recebimento_repository.dart';
import 'finance_summary.dart';
import 'finance_summary_repository.dart';
import 'lancamento_financeiro.dart';
import 'lancamentos_repository.dart';

final contasRepositoryProvider = Provider<ContasRepository>((ref) {
  return ContasRepository(ref.watch(apiClientProvider).dio);
});

final contasProvider = FutureProvider.autoDispose<List<ContaFinanceira>>((ref) {
  return ref.watch(contasRepositoryProvider).list();
});

final cartoesRepositoryProvider = Provider<CartoesRepository>((ref) {
  return CartoesRepository(ref.watch(apiClientProvider).dio);
});

final cartoesProvider = FutureProvider.autoDispose<List<CartaoCredito>>((ref) {
  return ref.watch(cartoesRepositoryProvider).list();
});

final lancamentosRepositoryProvider = Provider<LancamentosRepository>((ref) {
  return LancamentosRepository(ref.watch(apiClientProvider).dio);
});

final lancamentosPendentesProvider = FutureProvider.autoDispose<List<LancamentoFinanceiro>>((ref) {
  return ref.watch(lancamentosRepositoryProvider).list(status: 'PENDENTE_REVISAO');
});

final lancamentosDoMesProvider =
    FutureProvider.autoDispose.family<List<LancamentoFinanceiro>, String>((ref, mes) {
  return ref.watch(lancamentosRepositoryProvider).list(status: 'CONFIRMADO', mes: mes);
});

final financeSummaryRepositoryProvider = Provider<FinanceSummaryRepository>((ref) {
  return FinanceSummaryRepository(ref.watch(apiClientProvider).dio);
});

final financeSummaryProvider = FutureProvider.autoDispose<FinanceSummary>((ref) {
  return ref.watch(financeSummaryRepositoryProvider).getResumo();
});

final diaRecebimentoRepositoryProvider = Provider<DiaRecebimentoRepository>((ref) {
  return DiaRecebimentoRepository(ref.watch(apiClientProvider).dio);
});
```

- [ ] **Step 3: Analyze — this file has no widget/unit test of its own (it's pure provider wiring, matching the pre-existing file's lack of a dedicated test); verify the app still compiles**

```bash
cd mobile && flutter analyze lib/features/financas/finance_providers.dart
```

Expected: no new errors from this file (errors from files not yet rewritten, e.g. `financas_screen.dart` still importing removed providers, are expected until Tasks 7-9 land — note them, don't fix them here).

- [ ] **Step 4: Commit**

```bash
git add lib/features/financas/finance_providers.dart
git commit -m "feat(financas-mobile): reescreve finance_providers.dart para os novos endpoints"
```

---

## Task 7: Remove Pluggy-specific mobile files

**Files:**
- Delete: `mobile/lib/features/financas/finance_connection.dart`
- Delete: `mobile/lib/features/financas/finance_connection_repository.dart`
- Delete: `mobile/lib/features/financas/finance_connection_actions.dart`
- Delete: `mobile/lib/features/financas/pluggy_connect_webview_screen.dart`
- Delete: any test files for the above under `mobile/test/features/financas/` (check first)
- Delete: `mobile/test/features/financas/_tmp_debug_test.dart`, `_tmp_debug2_test.dart`, `_tmp_debug3_test.dart`, `_tmp_gauntlet_r3_verification_test.dart` (scratch files from earlier sessions, not real tests)

**Interfaces:**
- No new interfaces — this task only removes dead code. `dia_recebimento_repository.dart` is explicitly NOT touched.

- [ ] **Step 1: Confirm what references these files before deleting**

```bash
cd mobile && grep -rln "finance_connection\|pluggy_connect_webview_screen\|FinanceConnection\|PluggyConnectWebviewScreen" lib/ test/
```

Expected to include `lib/features/financas/financas_screen.dart` and `lib/features/home/home_screen.dart` — both are rewritten in Tasks 8-9, so leave their references broken for now; they'll be fixed when those tasks land. Do NOT fix those two files in this task.

- [ ] **Step 2: Delete the files**

```bash
git rm mobile/lib/features/financas/finance_connection.dart \
       mobile/lib/features/financas/finance_connection_repository.dart \
       mobile/lib/features/financas/finance_connection_actions.dart \
       mobile/lib/features/financas/pluggy_connect_webview_screen.dart
ls mobile/test/features/financas/ | grep -i "connection\|pluggy\|_tmp_"
```

For each test file the `ls` above prints (connection/pluggy tests, and the `_tmp_*` scratch files), `git rm` it too.

- [ ] **Step 3: Confirm `pubspec.yaml` dependencies are still needed elsewhere**

```bash
cd mobile && grep -rln "webview_flutter\|url_launcher" lib/
```

Expected: still shows `lib/features/home/emergency_button.dart` and `lib/features/professionals/professional_detail_screen.dart` — do NOT remove these two packages from `pubspec.yaml`, they are genuinely still used.

- [ ] **Step 4: Commit**

```bash
git commit -m "chore(financas-mobile): remove arquivos Pluggy (finance_connection*, pluggy_connect_webview_screen) e testes obsoletos"
```

(Do not run `flutter analyze`/`flutter test` on the whole project yet — `financas_screen.dart` and `home_screen.dart` still reference the deleted symbols until Tasks 8-9 land; that's expected and fixed there, not here.)

---

## Task 8: Home screen — calm Finanças card (3 design variants)

**Files:**
- Modify: `mobile/lib/features/home/home_screen.dart`
- Test: `mobile/test/features/home/home_screen_test.dart` (check if it exists first; add cases if so, create minimal coverage if not)

**Interfaces:**
- Consumes: `financeSummaryProvider` from Task 6.
- Produces: updated `_FinancasCard`, `_ModernoFinancasCard`, `_FuncionalFinancasCard` widgets (same class names, so nothing else in `home_screen.dart` needs to change how it instantiates them) that read `ref.watch(financeSummaryProvider)` instead of `ref.watch(financeConnectionsProvider)`, and no longer call `_connectFinanceAccount`/import `pluggy_connect_webview_screen.dart`.

- [ ] **Step 1: Read the current file in full**

```bash
cat mobile/lib/features/home/home_screen.dart
```

Locate: the import of `finance_connection.dart`/`finance_providers.dart`/`pluggy_connect_webview_screen.dart`, the `_connectFinanceAccount` method, and the three card widget classes (`_FinancasCard`, `_ModernoFinancasCard`, `_FuncionalFinancasCard`) and their call sites (one per `HomeDesignStyle` × the "resumo" layout, plus wherever the "abas" layout embeds a Finanças tab).

- [ ] **Step 2: Replace the Pluggy import with the finance summary import**

Remove:
```dart
import '../financas/finance_connection.dart';
import '../financas/pluggy_connect_webview_screen.dart';
```
(keep `import '../financas/finance_providers.dart';` — it still exists, just exports different providers now.)

- [ ] **Step 3: Remove `_connectFinanceAccount`**

Delete the entire method — there is nothing to connect anymore; email-driven staging happens automatically server-side.

- [ ] **Step 4: Rewrite the three card widgets to use `financeSummaryProvider`**

Each of `_FinancasCard`, `_ModernoFinancasCard`, `_FuncionalFinancasCard` currently does something like:
```dart
final financeConnectionsAsync = ref.watch(financeConnectionsProvider);
```
Replace that line (and whatever the rest of each widget's body does with `connectionsAsync`) with a calm summary preview matching the approved canvas design (`HomeCard.dc.html` at the published canvas). For EACH of the 3 widgets, apply this same content — only the surrounding visual chrome (which the widget already defines per design style) differs; the DATA and its calm framing are shared:

```dart
final summaryAsync = ref.watch(financeSummaryProvider);

return summaryAsync.when(
  loading: () => const SizedBox(
    height: 96,
    child: Center(child: CircularProgressIndicator()),
  ),
  error: (error, stackTrace) => const SizedBox.shrink(),
  data: (summary) {
    final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const FinancasScreen()),
      ),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Saldo Livre', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text(
              currency.format(summary.saldoLivre),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
      ),
    );
  },
);
```

Add `import 'package:intl/intl.dart';` and `import '../financas/financas_screen.dart';` to `home_screen.dart` if not already present. Adjust indentation/wrapping to fit each widget's existing surrounding `Card`/`Container` chrome — do not change that chrome, only the content that used to depend on `financeConnectionsAsync`.

- [ ] **Step 5: Check the "abas" (tabs) layout variants too**

If any `_Home*AbasView` widget embeds a Finanças tab that ALSO reads `financeConnectionsProvider` directly (not just through the 3 card widgets above), apply the same replacement there.

- [ ] **Step 6: Run analyze and existing home tests**

```bash
cd mobile && flutter analyze lib/features/home/home_screen.dart
flutter test test/features/home/ 2>&1 || echo "no home tests directory yet"
```

If `test/features/home/home_screen_test.dart` exists and asserted anything about the old Pluggy connection UI (e.g. a "Conectar" button), update those assertions to match the new calm summary preview. If no such file exists, do not create a full new test suite here — that's beyond this task's scope (Task 9 covers the main Finanças screen's own tests in depth; the Home card previews are a thin read-only view of the same provider).

- [ ] **Step 7: Commit**

```bash
git add lib/features/home/home_screen.dart
git commit -m "feat(financas-mobile): card calmo de Financas na Home usa financeSummaryProvider"
```

---

## Task 9: Rewrite `FinancasScreen` — Saldo Livre + Pendentes/Mês tabs

**Files:**
- Modify: `mobile/lib/features/financas/financas_screen.dart` (full rewrite)
- Test: `mobile/test/features/financas/financas_screen_test.dart` (full rewrite)

**Interfaces:**
- Consumes: `financeSummaryProvider`, `lancamentosPendentesProvider`, `lancamentosDoMesProvider` from Task 6; `LancamentoFinanceiro`, `TipoLancamento`, `StatusLancamento` from Task 1.
- Produces: `FinancasScreen` widget (same public name — nothing outside this file needs to change how it's invoked). Emits a `Revisar` action per pending item that Task 10 wires to open the confirmation bottom sheet — this task defines a placeholder `onRevisar: (LancamentoFinanceiro) => void` callback parameter threaded through the item card widget, wired to nothing (a no-op stub) until Task 10 fills it in via `showModalBottomSheet`. Keep the item card widget itself (`_LancamentoPendenteCard` below) in a form Task 10 can wrap without further edits to this file.

This matches the approved canvas design (`Main.dc.html`): AppBar "Finanças", a Saldo Livre highlight card, a segmented pair of `AppChip`s for "Pendentes de revisão" / "Lançamentos do mês", and per-tab lists.

- [ ] **Step 1: Read the current file in full**

```bash
cat mobile/lib/features/financas/financas_screen.dart
```

- [ ] **Step 2: Write the failing test**

`mobile/test/features/financas/financas_screen_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/core/theme.dart';
import 'package:sincro_mobile/features/financas/finance_providers.dart';
import 'package:sincro_mobile/features/financas/finance_summary.dart';
import 'package:sincro_mobile/features/financas/finance_summary_repository.dart';
import 'package:sincro_mobile/features/financas/financas_screen.dart';
import 'package:sincro_mobile/features/financas/lancamento_financeiro.dart';
import 'package:sincro_mobile/features/financas/lancamentos_repository.dart';

class _FakeFinanceSummaryRepository extends FinanceSummaryRepository {
  _FakeFinanceSummaryRepository(this._summary) : super(Dio());
  final FinanceSummary _summary;
  @override
  Future<FinanceSummary> getResumo() async => _summary;
}

class _FakeLancamentosRepository extends LancamentosRepository {
  _FakeLancamentosRepository({required this.pendentes, required this.doMes}) : super(Dio());
  final List<LancamentoFinanceiro> pendentes;
  final List<LancamentoFinanceiro> doMes;

  @override
  Future<List<LancamentoFinanceiro>> list({String? status, String? mes}) async {
    if (status == 'PENDENTE_REVISAO') return pendentes;
    return doMes;
  }
}

final _summaryVazio = FinanceSummary(
  saldoLivre: 1000,
  saldoContas: 1000,
  faturasAbertas: 0,
  despesasPendentesCiclo: 0,
  cicloFim: DateTime.utc(2026, 9, 30),
);

LancamentoFinanceiro _pendente({required String descricao, double? valor}) {
  return LancamentoFinanceiro(
    id: 'l-$descricao',
    tipo: TipoLancamento.despesa,
    descricao: descricao,
    instituicao: 'Nubank',
    valor: valor,
    dataVencimento: DateTime.utc(2026, 9, 20),
    dataCompetencia: DateTime.utc(2026, 9, 20),
    status: StatusLancamento.pendenteRevisao,
    origem: OrigemLancamento.emailParser,
    isPago: false,
    codigoBarras: null,
    cartaoId: null,
    contaId: null,
  );
}

Widget _app({required List<LancamentoFinanceiro> pendentes, required List<LancamentoFinanceiro> doMes}) {
  return ProviderScope(
    overrides: [
      financeSummaryRepositoryProvider.overrideWithValue(_FakeFinanceSummaryRepository(_summaryVazio)),
      lancamentosRepositoryProvider
          .overrideWithValue(_FakeLancamentosRepository(pendentes: pendentes, doMes: doMes)),
    ],
    child: MaterialApp(theme: sincroLightTheme, home: const FinancasScreen()),
  );
}

void main() {
  testWidgets('shows the Saldo Livre value from the summary', (tester) async {
    await tester.pumpWidget(_app(pendentes: const [], doMes: const []));
    await tester.pumpAndSettle();

    expect(find.textContaining('1.000,00'), findsOneWidget);
  });

  testWidgets('defaults to the Pendentes tab and lists pending lançamentos', (tester) async {
    await tester.pumpWidget(_app(
      pendentes: [_pendente(descricao: 'Fatura Nubank', valor: 512.40)],
      doMes: const [],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Fatura Nubank'), findsOneWidget);
    expect(find.textContaining('512,40'), findsOneWidget);
  });

  testWidgets('shows "informar valor" instead of a value when valor is null', (tester) async {
    await tester.pumpWidget(_app(
      pendentes: [_pendente(descricao: 'Conta de luz', valor: null)],
      doMes: const [],
    ));
    await tester.pumpAndSettle();

    expect(find.text('informar valor'), findsOneWidget);
  });

  testWidgets('switching to "Lançamentos do mês" shows that list instead', (tester) async {
    await tester.pumpWidget(_app(
      pendentes: [_pendente(descricao: 'Pendente A')],
      doMes: [_pendente(descricao: 'Confirmado B')],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Pendente A'), findsOneWidget);
    expect(find.text('Confirmado B'), findsNothing);

    await tester.tap(find.text('Lançamentos do mês'));
    await tester.pumpAndSettle();

    expect(find.text('Pendente A'), findsNothing);
    expect(find.text('Confirmado B'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run to verify it fails**

```bash
cd mobile && flutter test test/features/financas/financas_screen_test.dart
```

Expected: FAIL (old screen doesn't have these widgets/text).

- [ ] **Step 4: Rewrite `financas_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/widgets/app_chip.dart';
import 'finance_providers.dart';
import 'finance_summary.dart';
import 'lancamento_financeiro.dart';

final _currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final _dateFormat = DateFormat('dd/MM', 'pt_BR');

class FinancasScreen extends ConsumerStatefulWidget {
  const FinancasScreen({super.key});

  @override
  ConsumerState<FinancasScreen> createState() => _FinancasScreenState();
}

enum _Aba { pendentes, mes }

class _FinancasScreenState extends ConsumerState<FinancasScreen> {
  _Aba _aba = _Aba.pendentes;

  @override
  Widget build(BuildContext context) {
    final summaryAsync = ref.watch(financeSummaryProvider);
    final mesAtual = DateFormat('yyyy-MM').format(DateTime.now());

    return Scaffold(
      appBar: AppBar(title: const Text('Finanças')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [
          summaryAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, stackTrace) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text('Não foi possível carregar seu resumo agora.',
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
            data: (summary) => _SaldoLivreCard(summary: summary),
          ),
          const SizedBox(height: 20),
          AppChipGroup(
            chips: [
              AppChip(
                label: 'Pendentes de revisão',
                selected: _aba == _Aba.pendentes,
                variant: AppChipVariant.filter,
                onSelected: (_) => setState(() => _aba = _Aba.pendentes),
              ),
              AppChip(
                label: 'Lançamentos do mês',
                selected: _aba == _Aba.mes,
                variant: AppChipVariant.filter,
                onSelected: (_) => setState(() => _aba = _Aba.mes),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_aba == _Aba.pendentes)
            ref.watch(lancamentosPendentesProvider).when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (error, stackTrace) => const Text('Não foi possível carregar seus lançamentos.'),
                  data: (pendentes) => Column(
                    children: [
                      for (final lancamento in pendentes)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _LancamentoPendenteCard(lancamento: lancamento, onRevisar: (_) {}),
                        ),
                    ],
                  ),
                )
          else
            ref.watch(lancamentosDoMesProvider(mesAtual)).when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (error, stackTrace) => const Text('Não foi possível carregar seus lançamentos.'),
                  data: (doMes) => Column(
                    children: [
                      for (final lancamento in doMes)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _LancamentoDoMesCard(lancamento: lancamento),
                        ),
                    ],
                  ),
                ),
        ],
      ),
    );
  }
}

class _SaldoLivreCard extends StatelessWidget {
  const _SaldoLivreCard({required this.summary});

  final FinanceSummary summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: Theme.of(context).colorScheme.primary, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Saldo Livre', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          Text(
            _currency.format(summary.saldoLivre),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _LancamentoPendenteCard extends StatelessWidget {
  const _LancamentoPendenteCard({required this.lancamento, required this.onRevisar});

  final LancamentoFinanceiro lancamento;
  final void Function(LancamentoFinanceiro) onRevisar;

  @override
  Widget build(BuildContext context) {
    final valor = lancamento.valor;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(lancamento.descricao, style: Theme.of(context).textTheme.titleMedium),
                    Text('Sugestão automática · vence ${_dateFormat.format(lancamento.dataVencimento)}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              valor == null
                  ? Text('informar valor',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(fontStyle: FontStyle.italic))
                  : Text(_currency.format(valor), style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => onRevisar(lancamento),
              child: const Text('Revisar'),
            ),
          ),
        ],
      ),
    );
  }
}

class _LancamentoDoMesCard extends StatelessWidget {
  const _LancamentoDoMesCard({required this.lancamento});

  final LancamentoFinanceiro lancamento;

  @override
  Widget build(BuildContext context) {
    final colors = context.sincroColors;
    final valor = lancamento.valor;
    final diasParaVencer = lancamento.dataVencimento.difference(DateTime.now()).inDays;
    final corUrgencia = lancamento.isPago
        ? colors.success
        : (diasParaVencer <= 3 ? colors.caution : colors.success);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: corUrgencia, width: 4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(lancamento.descricao, style: Theme.of(context).textTheme.titleMedium),
                Text(lancamento.isPago ? 'Pago' : 'Vence em ${_dateFormat.format(lancamento.dataVencimento)}',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          if (valor != null) Text(_currency.format(valor)),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Run to verify it passes**

```bash
cd mobile && flutter test test/features/financas/financas_screen_test.dart
```

Expected: PASS (4 tests). If `AppChipGroup`/`AppChip`'s exact constructor from `app_chip.dart` doesn't match what's used above (re-read the file — this plan's earlier research pass may not have captured every parameter), adjust the call sites to match the real signature; the test assertions (what text/values are visible) are what must hold, not the exact widget tree shape.

- [ ] **Step 6: Commit**

```bash
git add lib/features/financas/financas_screen.dart test/features/financas/financas_screen_test.dart
git commit -m "feat(financas-mobile): reescreve FinancasScreen com abas Pendentes/Mes e Saldo Livre"
```

---

## Task 10: Confirmation bottom sheet

**Files:**
- Create: `mobile/lib/features/financas/confirmar_lancamento_sheet.dart`
- Test: `mobile/test/features/financas/confirmar_lancamento_sheet_test.dart`
- Modify: `mobile/lib/features/financas/financas_screen.dart` (wire `onRevisar` to open the sheet)
- Modify: `mobile/test/features/financas/financas_screen_test.dart` (add a case for opening the sheet)

**Interfaces:**
- Consumes: `LancamentoFinanceiro` from Task 1, `lancamentosRepositoryProvider`/`lancamentosPendentesProvider` from Task 6.
- Produces: `Future<void> showConfirmarLancamentoSheet(BuildContext context, WidgetRef ref, LancamentoFinanceiro lancamento)`.

Matches the approved canvas design (`ConfirmarSheet.dc.html`): a non-punitive explanatory line, pre-filled fields (read-only preview in this first version — full inline editing of valor/data/conta is a natural follow-up, not required by the spec's mobile section to ship in this task), and Ignorar/Confirmar actions.

- [ ] **Step 1: Write the failing test**

`mobile/test/features/financas/confirmar_lancamento_sheet_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/core/theme.dart';
import 'package:sincro_mobile/features/financas/confirmar_lancamento_sheet.dart';
import 'package:sincro_mobile/features/financas/lancamento_financeiro.dart';
import 'package:sincro_mobile/features/financas/lancamentos_repository.dart';

class _FakeLancamentosRepository extends LancamentosRepository {
  _FakeLancamentosRepository() : super(Dio());
  String? confirmedId;
  String? ignoredId;

  @override
  Future<void> confirmar(String id, {double? valor, DateTime? dataVencimento, String? contaId, String? cartaoId}) async {
    confirmedId = id;
  }

  @override
  Future<void> ignorar(String id) async {
    ignoredId = id;
  }
}

final _lancamento = LancamentoFinanceiro(
  id: 'l1',
  tipo: TipoLancamento.faturaCartao,
  descricao: 'Fatura Nubank',
  instituicao: 'Nubank',
  valor: 512.40,
  dataVencimento: DateTime.utc(2026, 10, 10),
  dataCompetencia: DateTime.utc(2026, 10, 10),
  status: StatusLancamento.pendenteRevisao,
  origem: OrigemLancamento.emailParser,
  isPago: false,
  codigoBarras: null,
  cartaoId: null,
  contaId: null,
);

void main() {
  testWidgets('Confirmar button calls repository.confirmar with the lançamento id', (tester) async {
    final repository = _FakeLancamentosRepository();

    await tester.pumpWidget(MaterialApp(
      theme: sincroLightTheme,
      home: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            showDragHandle: true,
            builder: (sheetContext) => ConfirmarLancamentoSheetContent(
              lancamento: _lancamento,
              onConfirmar: () => repository.confirmar(_lancamento.id),
              onIgnorar: () => repository.ignorar(_lancamento.id),
            ),
          ),
          child: const Text('abrir'),
        );
      }),
    ));

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Fatura Nubank'), findsOneWidget);
    expect(find.textContaining('512,40'), findsOneWidget);

    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();

    expect(repository.confirmedId, 'l1');
  });

  testWidgets('Ignorar button calls repository.ignorar with the lançamento id', (tester) async {
    final repository = _FakeLancamentosRepository();

    await tester.pumpWidget(MaterialApp(
      theme: sincroLightTheme,
      home: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            showDragHandle: true,
            builder: (sheetContext) => ConfirmarLancamentoSheetContent(
              lancamento: _lancamento,
              onConfirmar: () => repository.confirmar(_lancamento.id),
              onIgnorar: () => repository.ignorar(_lancamento.id),
            ),
          ),
          child: const Text('abrir'),
        );
      }),
    ));

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ignorar'));
    await tester.pumpAndSettle();

    expect(repository.ignoredId, 'l1');
  });
}
```

This tests the pure `ConfirmarLancamentoSheetContent` widget directly with plain
callbacks, rather than exercising `showConfirmarLancamentoSheet` itself (the
public entry point built in Step 3, which needs a real `WidgetRef` — that
function is covered indirectly by Task 10's Step 6 test in
`financas_screen_test.dart`, which opens the sheet through the real screen
where a `WidgetRef` is naturally available).

- [ ] **Step 2: Run to verify it fails**

```bash
cd mobile && flutter test test/features/financas/confirmar_lancamento_sheet_test.dart
```

- [ ] **Step 3: Write `confirmar_lancamento_sheet.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'finance_providers.dart';
import 'lancamento_financeiro.dart';

final _currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final _dateFormat = DateFormat('dd/MM/yyyy', 'pt_BR');

Future<void> showConfirmarLancamentoSheet(
  BuildContext context,
  WidgetRef ref,
  LancamentoFinanceiro lancamento,
) {
  final repository = ref.read(lancamentosRepositoryProvider);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => ConfirmarLancamentoSheetContent(
      lancamento: lancamento,
      onConfirmar: () async {
        await repository.confirmar(lancamento.id, valor: lancamento.valor);
        ref.invalidate(lancamentosPendentesProvider);
        if (sheetContext.mounted) Navigator.of(sheetContext).pop();
      },
      onIgnorar: () async {
        await repository.ignorar(lancamento.id);
        ref.invalidate(lancamentosPendentesProvider);
        if (sheetContext.mounted) Navigator.of(sheetContext).pop();
      },
    ),
  );
}

class ConfirmarLancamentoSheetContent extends StatelessWidget {
  const ConfirmarLancamentoSheetContent({
    super.key,
    required this.lancamento,
    required this.onConfirmar,
    required this.onIgnorar,
  });

  final LancamentoFinanceiro lancamento;
  final VoidCallback onConfirmar;
  final VoidCallback onIgnorar;

  @override
  Widget build(BuildContext context) {
    final valor = lancamento.valor;
    final instituicao = lancamento.instituicao;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Confirmar lançamento', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(
            instituicao != null
                ? 'Detectamos isso a partir de um e-mail do $instituicao. Dá uma conferida antes de confirmar — sem pressa.'
                : 'Detectamos isso a partir de um e-mail. Dá uma conferida antes de confirmar — sem pressa.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Text('Descrição', style: Theme.of(context).textTheme.labelSmall),
          Text(lancamento.descricao, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Text('Valor', style: Theme.of(context).textTheme.labelSmall),
          Text(
            valor == null ? 'não informado' : _currency.format(valor),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Text('Vencimento', style: Theme.of(context).textTheme.labelSmall),
          Text(_dateFormat.format(lancamento.dataVencimento), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(onPressed: onIgnorar, child: const Text('Ignorar')),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(onPressed: onConfirmar, child: const Text('Confirmar')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run to verify it passes**

```bash
cd mobile && flutter test test/features/financas/confirmar_lancamento_sheet_test.dart
```

Expected: PASS (2 tests — remove the stub first test case per the note in Step 1).

- [ ] **Step 5: Wire `onRevisar` in `financas_screen.dart`**

In `_FinancasScreenState.build`, change:
```dart
child: _LancamentoPendenteCard(lancamento: lancamento, onRevisar: (_) {}),
```
to:
```dart
child: _LancamentoPendenteCard(
  lancamento: lancamento,
  onRevisar: (l) => showConfirmarLancamentoSheet(context, ref, l),
),
```
Add `import 'confirmar_lancamento_sheet.dart';` to the top of `financas_screen.dart`.

- [ ] **Step 6: Add a test case to `financas_screen_test.dart` for the wiring**

```dart
testWidgets('tapping Revisar opens the confirmation sheet', (tester) async {
  await tester.pumpWidget(_app(
    pendentes: [_pendente(descricao: 'Fatura Nubank', valor: 512.40)],
    doMes: const [],
  ));
  await tester.pumpAndSettle();

  await tester.tap(find.text('Revisar'));
  await tester.pumpAndSettle();

  expect(find.text('Confirmar lançamento'), findsOneWidget);
});
```

- [ ] **Step 7: Run both test files**

```bash
cd mobile && flutter test test/features/financas/financas_screen_test.dart test/features/financas/confirmar_lancamento_sheet_test.dart
```

- [ ] **Step 8: Commit**

```bash
git add lib/features/financas/confirmar_lancamento_sheet.dart lib/features/financas/financas_screen.dart \
  test/features/financas/confirmar_lancamento_sheet_test.dart test/features/financas/financas_screen_test.dart
git commit -m "feat(financas-mobile): bottom sheet de confirmacao de lancamento"
```

---

## Task 11: Whole-app verification and cleanup

**Files:**
- No new files — this task only verifies and, if needed, fixes small leftover issues across the feature.

**Interfaces:**
- None — final integration check.

- [ ] **Step 1: Run `flutter analyze` on the whole project**

```bash
cd mobile && flutter analyze
```

Expected: zero errors. Fix any leftover reference to a removed Pluggy symbol (there should be none left, since Tasks 7-9 covered every known call site, but a stray import elsewhere is possible — grep for `FinanceConnection|PluggyConnectWebviewScreen|financeConnectionsProvider` across `lib/` if analyze reports anything unexpected).

- [ ] **Step 2: Run the full test suite**

```bash
cd mobile && flutter test
```

Expected: 100% pass. If any pre-existing, unrelated test was already failing before this plan (check by running `git stash` and re-running on the pre-plan state if something looks suspicious, then `git stash pop`), note it as pre-existing and do not attempt to fix it in this task — only fix regressions this plan's changes caused.

- [ ] **Step 3: Confirm no dangling references to the removed `/financas/sync` or `/financas/connect-token` endpoints**

```bash
cd mobile && grep -rn "financas/sync\|financas/connect-token\|financas/conexoes" lib/
```

Expected: no output.

- [ ] **Step 4: Manual smoke check of the widget tree (no device required)**

```bash
cd mobile && flutter analyze lib/features/financas/ lib/features/home/home_screen.dart
```

Expected: clean. This plan cannot run the app on a real device/emulator from here — note in your final report that a manual run on a simulator (or `flutter run`) is recommended before this ships, to visually confirm the screen matches the approved canvas mockups, since widget tests verify behavior/text but not pixel-level fidelity to the design.

- [ ] **Step 5: Commit any final fixups (only if Steps 1-3 required changes)**

```bash
git add -A
git commit -m "fix(financas-mobile): ajustes finais de integracao pos-reescrita da tela de Financas"
```

If nothing needed fixing, skip this commit — there's nothing to record.

---

## Out of scope for this plan

- **Inline editing of valor/data/conta/cartão inside the confirmation bottom sheet** — Task 10 ships a read-only preview + Confirmar/Ignorar, matching the MINIMUM the spec requires ("abre o card, ajusta se necessário, confirma"); adding editable fields to the sheet (an `AppInput` per field, a date picker, a conta/cartão dropdown) is a natural fast-follow, not blocking the core review flow, and was not explicitly re-confirmed as in-scope during this plan's brainstorming.
- **Manual CRUD screens for creating/editing Contas and Cartões** — Tasks 2-3 build the repositories (list/create/remove) so the data layer is ready, but no screen/form calls `create()` yet; the approved canvas mockups only covered the resumo/pendentes/confirm flow, not an accounts management screen. A follow-up plan should cover this once designed.
- **Removing `webview_flutter`/`url_launcher` from `pubspec.yaml`** — explicitly NOT done, per Global Constraints (still used by other features).
- **Dark mode manual QA on a device** — the canvas mockups already validated the dark palette; this plan trusts `context.sincroColors` to apply correctly since it's the same mechanism every other screen already uses, and does not re-verify it pixel-by-pixel.
