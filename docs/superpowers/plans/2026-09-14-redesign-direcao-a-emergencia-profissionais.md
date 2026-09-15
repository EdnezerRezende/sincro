# Redesign Direção A + Emergência multi-contato + Profissionais — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implementar no app Sincro a direção visual A (Login e Home), o fluxo "Avisar Rede de Apoio" com seleção de vários contatos e mensagem editável, e a evolução de Profissionais (busca por nome, adicionar à rede de apoio, admin com busca/inativos/localização).

**Architecture:** Backend NestJS (Prisma/Postgres) ganha um endpoint `POST /emergency/messages` e o parâmetro `q` em `GET /professionals/search`; o app Flutter (Riverpod + Dio) ganha uma folha inferior de emergência com fila de envio, um campo de busca por nome, um diálogo "Adicionar à rede de apoio" e a nova Home/Login. Nada muda no tema; a UI nova reutiliza `AppInput`, `AppButton` e os tokens de `theme.dart`.

**Tech Stack:** NestJS 10 + class-validator + Jest (backend); Flutter 3 + flutter_riverpod + dio + url_launcher + geolocator + flutter_test (mobile).

**Spec:** `docs/superpowers/specs/2026-09-14-redesign-direcao-a-spec.md` (leia antes; o canvas de referência está linkado lá).

## Global Constraints

- Copy das telas existentes não muda; strings novas só as listadas na spec.
- Tokens: sem cores novas; usar `Theme.of(context).colorScheme` e `context.sincroColors`.
- Alvos de toque ≥ 44 dp; `AppButtonSize.large` (56 dp) nas ações primárias de tela.
- Comandos de teste: backend `cd backend && npm test -- <arquivo>`; mobile `cd mobile && flutter test <arquivo>`.
- Commits pequenos, em português, prefixo `feat|fix|refactor|test(escopo):`, terminando com `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Em `mobile`, rodar `flutter analyze` antes de cada commit; não deixar warnings novos.
- Emergência: o texto padrão continua exatamente `Oi {primeiro nome}, estou passando por um momento difícil agora e queria avisar. Não precisa ligar se não for possível.` (com o primeiro nome substituído).

---

## Parte A — Emergência multi-contato

### Task 1: `EmergencyService.buildMessages` com template e vários contatos

**Files:**
- Create: `backend/src/emergency/dto/build-emergency-messages.dto.ts`
- Modify: `backend/src/emergency/emergency.service.ts`
- Test: `backend/src/emergency/emergency.service.spec.ts`

**Interfaces:**
- Consumes: `PrismaService.trustedContact.findMany`, `UsersService.getByFirebaseUidOrThrow`.
- Produces: `DEFAULT_EMERGENCY_TEMPLATE: string`, `EMERGENCY_NAME_PLACEHOLDER = '{primeiro nome}'`, `buildMessages(firebaseUid: string, contactIds: string[], template?: string): Promise<EmergencyMessage[]>` onde `EmergencyMessage = { contactId; contactName; whatsapp; message; waUrl }`, e `BuildEmergencyMessagesDto { contactIds: string[]; template?: string }`.

- [ ] **Step 1: Escrever os testes que falham**

Acrescentar ao final do `describe('EmergencyService', ...)` em `emergency.service.spec.ts`:

```ts
  describe('buildMessages', () => {
    const usersService = { getByFirebaseUidOrThrow: jest.fn().mockResolvedValue({ id: 'u1' }) };
    const contatos = [
      { id: 'c1', nome: 'Marina Souza', whatsapp: '+55 11 99999-9999' },
      { id: 'c2', nome: 'João Pedro Lima', whatsapp: '+5511988880000' },
    ];

    it('returns one message per contact, in the requested order, with the default template', async () => {
      const prisma = { trustedContact: { findMany: jest.fn().mockResolvedValue([contatos[1], contatos[0]]) } };
      const service = new EmergencyService(prisma as any, usersService as any);

      const result = await service.buildMessages('fb1', ['c1', 'c2']);

      expect(prisma.trustedContact.findMany).toHaveBeenCalledWith({
        where: { id: { in: ['c1', 'c2'] }, userId: 'u1' },
      });
      expect(result.map((m) => m.contactId)).toEqual(['c1', 'c2']);
      expect(result[0].message).toBe(
        'Oi Marina, estou passando por um momento difícil agora e queria avisar. Não precisa ligar se não for possível.',
      );
      expect(result[1].message.startsWith('Oi João,')).toBe(true);
      expect(result[1].waUrl).toBe(`https://wa.me/5511988880000?text=${encodeURIComponent(result[1].message)}`);
    });

    it('applies a custom template replacing {primeiro nome} for each contact', async () => {
      const prisma = { trustedContact: { findMany: jest.fn().mockResolvedValue(contatos) } };
      const service = new EmergencyService(prisma as any, usersService as any);

      const result = await service.buildMessages('fb1', ['c1', 'c2'], 'Oi {primeiro nome}, pode me ligar?');

      expect(result[0].message).toBe('Oi Marina, pode me ligar?');
      expect(result[1].message).toBe('Oi João, pode me ligar?');
    });

    it('keeps a template without the placeholder as-is', async () => {
      const prisma = { trustedContact: { findMany: jest.fn().mockResolvedValue([contatos[0]]) } };
      const service = new EmergencyService(prisma as any, usersService as any);

      const result = await service.buildMessages('fb1', ['c1'], 'Preciso de ajuda agora.');

      expect(result[0].message).toBe('Preciso de ajuda agora.');
    });

    it('throws NotFoundException when any contact is missing or belongs to another user', async () => {
      const prisma = { trustedContact: { findMany: jest.fn().mockResolvedValue([contatos[0]]) } };
      const service = new EmergencyService(prisma as any, usersService as any);

      await expect(service.buildMessages('fb1', ['c1', 'c2'])).rejects.toThrow(NotFoundException);
    });
  });
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd backend && npm test -- emergency.service.spec.ts`
Expected: FAIL com `service.buildMessages is not a function`.

- [ ] **Step 3: Criar o DTO**

`backend/src/emergency/dto/build-emergency-messages.dto.ts`:

```ts
import { ArrayMaxSize, ArrayMinSize, IsArray, IsOptional, IsString, IsUUID, Length } from 'class-validator';

export class BuildEmergencyMessagesDto {
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(10)
  @IsUUID('all', { each: true })
  contactIds: string[];

  @IsOptional()
  @IsString()
  @Length(1, 300)
  template?: string;
}
```

- [ ] **Step 4: Implementar no service**

Substituir o conteúdo de `backend/src/emergency/emergency.service.ts` por:

```ts
import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { UsersService } from '../users/users.service';

export const EMERGENCY_NAME_PLACEHOLDER = '{primeiro nome}';
export const DEFAULT_EMERGENCY_TEMPLATE =
  `Oi ${EMERGENCY_NAME_PLACEHOLDER}, estou passando por um momento difícil agora e queria avisar. Não precisa ligar se não for possível.`;

export interface EmergencyMessage {
  contactId: string;
  contactName: string;
  whatsapp: string;
  message: string;
  waUrl: string;
}

@Injectable()
export class EmergencyService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly usersService: UsersService,
  ) {}

  /** Mantido por compatibilidade com clientes antigos (`POST /emergency/message`). */
  async buildMessage(firebaseUid: string, contactId: string): Promise<EmergencyMessage> {
    const [message] = await this.buildMessages(firebaseUid, [contactId]);
    return message;
  }

  async buildMessages(firebaseUid: string, contactIds: string[], template?: string): Promise<EmergencyMessage[]> {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    const contacts = await this.prisma.trustedContact.findMany({
      where: { id: { in: contactIds }, userId: user.id },
    });
    const byId = new Map(contacts.map((contact) => [contact.id, contact]));
    const missing = contactIds.filter((id) => !byId.has(id));
    if (missing.length > 0) {
      throw new NotFoundException('Contato não encontrado');
    }

    const effectiveTemplate = template?.trim() ? template : DEFAULT_EMERGENCY_TEMPLATE;
    return contactIds.map((id) => {
      const contact = byId.get(id)!;
      const primeiroNome = contact.nome.split(' ')[0];
      const mensagem = effectiveTemplate.split(EMERGENCY_NAME_PLACEHOLDER).join(primeiroNome);
      const numeroLimpo = contact.whatsapp.replace(/\D/g, '');
      return {
        contactId: contact.id,
        contactName: contact.nome,
        whatsapp: contact.whatsapp,
        message: mensagem,
        waUrl: `https://wa.me/${numeroLimpo}?text=${encodeURIComponent(mensagem)}`,
      };
    });
  }
}
```

- [ ] **Step 5: Ajustar os dois testes antigos de `buildMessage`**

Os testes existentes mockam `trustedContact.findFirst`; trocar para `findMany` retornando `[]` (primeiro teste) e `[contato]` (segundo). No primeiro, a asserção passa a ser:

```ts
    expect(prisma.trustedContact.findMany).toHaveBeenCalledWith({
      where: { id: { in: ['c1'] }, userId: 'u1' },
    });
```

- [ ] **Step 6: Rodar e ver passar**

Run: `cd backend && npm test -- emergency.service.spec.ts`
Expected: PASS (6 testes).

- [ ] **Step 7: Commit**

```bash
git add backend/src/emergency
git commit -m "feat(emergency): buildMessages com vários contatos e template editável

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: Endpoint `POST /emergency/messages`

**Files:**
- Modify: `backend/src/emergency/emergency.controller.ts`
- Test: `backend/src/emergency/emergency.controller.spec.ts` (criar)

**Interfaces:**
- Consumes: `EmergencyService.buildMessages`, `BuildEmergencyMessagesDto` (Task 1).
- Produces: rota `POST /emergency/messages` → `EmergencyMessage[]`.

- [ ] **Step 1: Teste que falha**

`backend/src/emergency/emergency.controller.spec.ts`:

```ts
import { EmergencyController } from './emergency.controller';

describe('EmergencyController', () => {
  it('delegates POST /emergency/messages to the service with contactIds and template', async () => {
    const service = { buildMessages: jest.fn().mockResolvedValue([{ contactId: 'c1' }]), buildMessage: jest.fn() };
    const controller = new EmergencyController(service as any);

    const result = await controller.buildMessages('fb1', { contactIds: ['c1'], template: 'Oi {primeiro nome}' });

    expect(service.buildMessages).toHaveBeenCalledWith('fb1', ['c1'], 'Oi {primeiro nome}');
    expect(result).toEqual([{ contactId: 'c1' }]);
  });
});
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd backend && npm test -- emergency.controller.spec.ts`
Expected: FAIL com `controller.buildMessages is not a function`.

- [ ] **Step 3: Implementar**

Em `emergency.controller.ts`, importar o DTO novo e adicionar o método abaixo de `buildMessage`:

```ts
import { BuildEmergencyMessagesDto } from './dto/build-emergency-messages.dto';
// ...
  @Post('messages')
  async buildMessages(@CurrentFirebaseUid() firebaseUid: string, @Body() dto: BuildEmergencyMessagesDto) {
    return this.service.buildMessages(firebaseUid, dto.contactIds, dto.template);
  }
```

- [ ] **Step 4: Rodar e ver passar**

Run: `cd backend && npm test -- emergency`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/src/emergency
git commit -m "feat(emergency): endpoint POST /emergency/messages

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: `EmergencyRepository.buildMessages` no app

**Files:**
- Modify: `mobile/lib/features/emergency/emergency_message.dart`
- Modify: `mobile/lib/features/emergency/emergency_repository.dart`
- Test: `mobile/test/features/emergency/emergency_repository_test.dart`

**Interfaces:**
- Produces: `const kEmergencyNamePlaceholder = '{primeiro nome}'`, `const kEmergencyDefaultTemplate` (mesmo texto do backend), `Future<List<EmergencyMessage>> buildMessages(List<String> contactIds, {String? template})`.

- [ ] **Step 1: Teste que falha**

Acrescentar em `emergency_repository_test.dart`:

```dart
  test('buildMessages posts contactIds and template and parses the list', () async {
    Map<String, dynamic>? sentBody;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      sentBody = options.data as Map<String, dynamic>;
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 201,
        data: [
          {'contactId': 'c1', 'contactName': 'Dra. Marina', 'whatsapp': '+5511999999999', 'message': 'Oi Marina', 'waUrl': 'https://wa.me/1'},
          {'contactId': 'c2', 'contactName': 'João', 'whatsapp': '+5511988880000', 'message': 'Oi João', 'waUrl': 'https://wa.me/2'},
        ],
      ));
    }));
    final repository = EmergencyRepository(dio);

    final result = await repository.buildMessages(['c1', 'c2'], template: 'Oi {primeiro nome}');

    expect(sentBody, {'contactIds': ['c1', 'c2'], 'template': 'Oi {primeiro nome}'});
    expect(result.map((m) => m.contactId), ['c1', 'c2']);
  });

  test('buildMessages omits template when null', () async {
    Map<String, dynamic>? sentBody;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      sentBody = options.data as Map<String, dynamic>;
      handler.resolve(Response(requestOptions: options, statusCode: 201, data: []));
    }));

    await EmergencyRepository(dio).buildMessages(['c1']);

    expect(sentBody, {'contactIds': ['c1']});
  });
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd mobile && flutter test test/features/emergency/emergency_repository_test.dart`
Expected: FAIL (método inexistente).

- [ ] **Step 3: Implementar**

No topo de `emergency_message.dart`:

```dart
const kEmergencyNamePlaceholder = '{primeiro nome}';
const kEmergencyDefaultTemplate =
    'Oi $kEmergencyNamePlaceholder, estou passando por um momento difícil agora e queria avisar. Não precisa ligar se não for possível.';
const kEmergencyTemplateMaxLength = 300;
```

Em `emergency_repository.dart`, após `buildMessage`:

```dart
  Future<List<EmergencyMessage>> buildMessages(List<String> contactIds, {String? template}) async {
    final response = await _dio.post('/emergency/messages', data: {
      'contactIds': contactIds,
      if (template != null) 'template': template,
    });
    return (response.data as List)
        .map((json) => EmergencyMessage.fromJson(json as Map<String, dynamic>))
        .toList();
  }
```

- [ ] **Step 4: Rodar e ver passar**

Run: `cd mobile && flutter test test/features/emergency/emergency_repository_test.dart`
Expected: PASS (3 testes).

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/emergency mobile/test/features/emergency
git commit -m "feat(mobile/emergency): repositório buildMessages e template padrão

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: `EmergencySendQueue` (lógica pura da fila de envio)

**Files:**
- Create: `mobile/lib/features/emergency/emergency_send_queue.dart`
- Test: `mobile/test/features/emergency/emergency_send_queue_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class EmergencySendQueue {
    EmergencySendQueue(List<EmergencyMessage> messages);
    EmergencyMessage? get current;      // próxima a abrir, null se acabou
    EmergencyMessage? get last;         // última aberta (para "Enviado para X")
    int get index;                      // 0-based, quantas já foram abertas
    int get total;
    bool get isDone;
    void markCurrentOpened();           // avança
  }
  String emergencyCtaLabel(int selectedCount, List<String> selectedFirstNames);
  ```

- [ ] **Step 1: Teste que falha**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/emergency/emergency_message.dart';
import 'package:sincro_mobile/features/emergency/emergency_send_queue.dart';

EmergencyMessage _msg(String id, String name) => EmergencyMessage(
      contactId: id, contactName: name, whatsapp: '+5511999999999', message: 'Oi', waUrl: 'https://wa.me/$id');

void main() {
  test('queue walks messages in order and reports done', () {
    final queue = EmergencySendQueue([_msg('c1', 'Marina Souza'), _msg('c2', 'João')]);

    expect(queue.total, 2);
    expect(queue.index, 0);
    expect(queue.current!.contactId, 'c1');
    expect(queue.last, isNull);
    expect(queue.isDone, isFalse);

    queue.markCurrentOpened();
    expect(queue.index, 1);
    expect(queue.last!.contactId, 'c1');
    expect(queue.current!.contactId, 'c2');

    queue.markCurrentOpened();
    expect(queue.isDone, isTrue);
    expect(queue.current, isNull);
  });

  test('markCurrentOpened after done is a no-op', () {
    final queue = EmergencySendQueue([_msg('c1', 'Marina')]);
    queue.markCurrentOpened();
    queue.markCurrentOpened();
    expect(queue.index, 1);
  });

  test('CTA label depends on how many contacts are selected', () {
    expect(emergencyCtaLabel(0, const []), 'Escolha quem avisar');
    expect(emergencyCtaLabel(1, const ['Marina']), 'Abrir WhatsApp para Marina');
    expect(emergencyCtaLabel(3, const ['Marina', 'João', 'Ana']), 'Abrir WhatsApp · 1 de 3: Marina');
  });
}
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd mobile && flutter test test/features/emergency/emergency_send_queue_test.dart`
Expected: FAIL (arquivo não existe).

- [ ] **Step 3: Implementar**

```dart
import 'emergency_message.dart';

/// Fila de abertura do WhatsApp: `wa.me` abre UMA conversa por vez, então a folha
/// abre uma, espera o app voltar ao primeiro plano e oferece a próxima.
class EmergencySendQueue {
  EmergencySendQueue(this._messages);

  final List<EmergencyMessage> _messages;
  int _index = 0;

  int get index => _index;
  int get total => _messages.length;
  bool get isDone => _index >= _messages.length;
  EmergencyMessage? get current => isDone ? null : _messages[_index];
  EmergencyMessage? get last => _index == 0 ? null : _messages[_index - 1];

  void markCurrentOpened() {
    if (!isDone) _index++;
  }
}

String emergencyCtaLabel(int selectedCount, List<String> selectedFirstNames) {
  if (selectedCount == 0) return 'Escolha quem avisar';
  final first = selectedFirstNames.first;
  if (selectedCount == 1) return 'Abrir WhatsApp para $first';
  return 'Abrir WhatsApp · 1 de $selectedCount: $first';
}

String primeiroNome(String nomeCompleto) => nomeCompleto.trim().split(' ').first;
```

- [ ] **Step 4: Rodar e ver passar**

Run: `cd mobile && flutter test test/features/emergency/emergency_send_queue_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/emergency/emergency_send_queue.dart mobile/test/features/emergency/emergency_send_queue_test.dart
git commit -m "feat(mobile/emergency): fila de envio e rótulo do CTA

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: Folha inferior `EmergencySheet`

**Files:**
- Create: `mobile/lib/features/emergency/emergency_sheet.dart`
- Test: `mobile/test/features/emergency/emergency_sheet_test.dart`

**Interfaces:**
- Consumes: `trustedContactsRepositoryProvider.list()`, `emergencyRepositoryProvider.buildMessages`, `EmergencySendQueue`, `emergencyCtaLabel`, `primeiroNome`, `kEmergencyDefaultTemplate`, `kEmergencyTemplateMaxLength`.
- Produces: `Future<void> showEmergencySheet(BuildContext context, {required List<TrustedContact> contacts, Future<void> Function(Uri) launch = _defaultLaunch})`. O parâmetro `launch` existe para os testes não abrirem o WhatsApp.

- [ ] **Step 1: Testes que falham**

```dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/emergency/emergency_providers.dart';
import 'package:sincro_mobile/features/emergency/emergency_repository.dart';
import 'package:sincro_mobile/features/emergency/emergency_sheet.dart';
import 'package:sincro_mobile/features/trusted_contacts/trusted_contact.dart';

const _contacts = [
  TrustedContact(id: 'c1', nome: 'Marina Souza', relacao: 'PSICOLOGO', whatsapp: '+5511999999999', prioridade: 0),
  TrustedContact(id: 'c2', nome: 'João Lima', relacao: 'FAMILIAR', whatsapp: '+5511988880000', prioridade: 0),
];

EmergencyRepository _repo(void Function(Map<String, dynamic>) onBody) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test'));
  dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
    final body = options.data as Map<String, dynamic>;
    onBody(body);
    final ids = (body['contactIds'] as List).cast<String>();
    handler.resolve(Response(
      requestOptions: options,
      statusCode: 201,
      data: ids
          .map((id) => {
                'contactId': id,
                'contactName': _contacts.firstWhere((c) => c.id == id).nome,
                'whatsapp': '+55',
                'message': 'Oi',
                'waUrl': 'https://wa.me/$id',
              })
          .toList(),
    ));
  }));
  return EmergencyRepository(dio);
}

Future<void> _pumpSheet(WidgetTester tester, EmergencyRepository repo, List<Uri> launched) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [emergencyRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => showEmergencySheet(context, contacts: _contacts, launch: (uri) async => launched.add(uri)),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('starts with every contact selected and the default template', (tester) async {
    await _pumpSheet(tester, _repo((_) {}), []);

    expect(find.text('Avisar Rede de Apoio'), findsOneWidget);
    expect(find.text('Abrir WhatsApp · 1 de 2: Marina'), findsOneWidget);
    expect(find.textContaining('Oi {primeiro nome}, estou passando'), findsOneWidget);
  });

  testWidgets('unselecting everyone disables the CTA', (tester) async {
    await _pumpSheet(tester, _repo((_) {}), []);

    await tester.tap(find.text('Marina Souza'));
    await tester.tap(find.text('João Lima'));
    await tester.pump();

    final button = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Escolha quem avisar'));
    expect(button.onPressed, isNull);
  });

  testWidgets('sends selected ids and edited template, then walks the queue', (tester) async {
    Map<String, dynamic>? body;
    final launched = <Uri>[];
    await _pumpSheet(tester, _repo((b) => body = b), launched);

    await tester.tap(find.text('João Lima'));
    await tester.enterText(find.byType(TextField), 'Oi {primeiro nome}, pode me ligar?');
    await tester.tap(find.text('Abrir WhatsApp para Marina'));
    await tester.pumpAndSettle();

    expect(body!['contactIds'], ['c1']);
    expect(body!['template'], 'Oi {primeiro nome}, pode me ligar?');
    expect(launched.single.toString(), 'https://wa.me/c1');
    expect(find.text('Avisos abertos para 1 pessoa.'), findsOneWidget);
  });

  testWidgets('with two contacts shows the next step after the first launch', (tester) async {
    final launched = <Uri>[];
    await _pumpSheet(tester, _repo((_) {}), launched);

    await tester.tap(find.text('Abrir WhatsApp · 1 de 2: Marina'));
    await tester.pumpAndSettle();

    expect(launched.length, 1);
    expect(find.text('Enviado para Marina. Próximo: João'), findsOneWidget);
    expect(find.text('Continuar com João'), findsOneWidget);

    await tester.tap(find.text('Continuar com João'));
    await tester.pumpAndSettle();
    expect(launched.length, 2);
    expect(find.text('Avisos abertos para 2 pessoas.'), findsOneWidget);
  });

  testWidgets('"Restaurar padrão" puts the default template back', (tester) async {
    await _pumpSheet(tester, _repo((_) {}), []);
    await tester.enterText(find.byType(TextField), 'x');
    await tester.tap(find.text('Restaurar padrão'));
    await tester.pump();
    expect(find.textContaining('Oi {primeiro nome}, estou passando'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd mobile && flutter test test/features/emergency/emergency_sheet_test.dart`
Expected: FAIL (arquivo não existe).

- [ ] **Step 3: Implementar a folha**

`mobile/lib/features/emergency/emergency_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/widgets/app_button.dart';
import '../trusted_contacts/trusted_contact.dart';
import 'emergency_message.dart';
import 'emergency_providers.dart';
import 'emergency_send_queue.dart';

Future<void> _defaultLaunch(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

Future<void> showEmergencySheet(
  BuildContext context, {
  required List<TrustedContact> contacts,
  Future<void> Function(Uri) launch = _defaultLaunch,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _EmergencySheet(contacts: contacts, launch: launch),
  );
}

class _EmergencySheet extends ConsumerStatefulWidget {
  const _EmergencySheet({required this.contacts, required this.launch});

  final List<TrustedContact> contacts;
  final Future<void> Function(Uri) launch;

  @override
  ConsumerState<_EmergencySheet> createState() => _EmergencySheetState();
}

class _EmergencySheetState extends ConsumerState<_EmergencySheet> {
  late final Set<String> _selected = widget.contacts.map((c) => c.id).toSet();
  late final TextEditingController _template = TextEditingController(text: kEmergencyDefaultTemplate);
  EmergencySendQueue? _queue;
  bool _preparing = false;
  String? _error;

  @override
  void dispose() {
    _template.dispose();
    super.dispose();
  }

  List<TrustedContact> get _selectedContacts =>
      widget.contacts.where((c) => _selected.contains(c.id)).toList();

  Future<void> _start() async {
    setState(() {
      _preparing = true;
      _error = null;
    });
    try {
      final ids = _selectedContacts.map((c) => c.id).toList();
      final template = _template.text.trim();
      final messages = await ref.read(emergencyRepositoryProvider).buildMessages(
            ids,
            template: template == kEmergencyDefaultTemplate ? null : template,
          );
      _queue = EmergencySendQueue(messages);
      await _openCurrent();
    } catch (_) {
      setState(() => _error = 'Não foi possível preparar as mensagens. Tente novamente.');
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  /// Decisão de implementação: a fila avança assim que `launch` retorna (o WhatsApp foi
  /// aberto), sem depender de `AppLifecycleState.resumed` — mais simples e testável, e o
  /// usuário só vê o próximo passo quando voltar ao app de qualquer forma.
  Future<void> _openCurrent() async {
    final queue = _queue!;
    final current = queue.current;
    if (current == null) return;
    try {
      await widget.launch(Uri.parse(current.waUrl));
    } catch (_) {
      if (mounted) setState(() => _error = 'Não foi possível abrir o WhatsApp.');
      return;
    }
    queue.markCurrentOpened();
    if (!mounted) return;
    if (queue.isDone) {
      final n = queue.total;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Avisos abertos para $n ${n == 1 ? 'pessoa' : 'pessoas'}.')),
      );
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final queue = _queue;
    final selectedNames = _selectedContacts.map((c) => primeiroNome(c.nome)).toList();
    final canSend = _selected.isNotEmpty && !_preparing && _template.text.trim().isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: scheme.outline, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 12),
            Text('Avisar Rede de Apoio', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text('Escolha quem avisar e ajuste a mensagem, se quiser. Nada é enviado sem você confirmar.',
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            if (queue != null && !queue.isDone) ...[
              Text('Enviado para ${primeiroNome(queue.last!.contactName)}. Próximo: ${primeiroNome(queue.current!.contactName)}',
                  style: theme.textTheme.bodyLarge),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: scheme.error)),
              ],
              const SizedBox(height: 12),
              AppButton(
                label: 'Continuar com ${primeiroNome(queue.current!.contactName)}',
                size: AppButtonSize.large,
                onPressed: _openCurrent,
              ),
            ] else ...[
              Text('Quem avisar', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    for (final contact in widget.contacts)
                      CheckboxListTile(
                        value: _selected.contains(contact.id),
                        onChanged: (v) => setState(() => v == true ? _selected.add(contact.id) : _selected.remove(contact.id)),
                        title: Text(contact.nome),
                        subtitle: Text(contact.relacao),
                        controlAffinity: ListTileControlAffinity.trailing,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text('Mensagem', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _template,
                maxLines: 4,
                maxLength: kEmergencyTemplateMaxLength,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text('$kEmergencyNamePlaceholder vira o nome de cada pessoa',
                        style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _template.text = kEmergencyDefaultTemplate),
                    child: const Text('Restaurar padrão'),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: scheme.error)),
              ],
              const SizedBox(height: 12),
              AppButton(
                label: emergencyCtaLabel(_selected.length, selectedNames),
                size: AppButtonSize.large,
                icon: Icons.chat_outlined,
                isLoading: _preparing,
                onPressed: canSend ? _start : null,
              ),
              AppButton(
                label: 'Agora não',
                variant: AppButtonVariant.text,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

Nota: `AppButton` renderiza sempre um `ElevatedButton` com `onPressed: effectiveOnPressed` (`mobile/lib/core/widgets/app_button.dart:227`), nulo quando desabilitado, então a asserção `tester.widget<ElevatedButton>(...)` do teste funciona como está.

- [ ] **Step 4: Rodar e ver passar**

Run: `cd mobile && flutter test test/features/emergency/emergency_sheet_test.dart`
Expected: PASS (5 testes).

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/emergency/emergency_sheet.dart mobile/test/features/emergency/emergency_sheet_test.dart
git commit -m "feat(mobile/emergency): folha de aviso com multi-seleção, mensagem editável e fila

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: `EmergencyButton` abre a folha

**Files:**
- Modify: `mobile/lib/features/home/emergency_button.dart`
- Test: `mobile/test/features/home/emergency_button_test.dart` (criar)

- [ ] **Step 1: Teste que falha**

```dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/home/emergency_button.dart';
import 'package:sincro_mobile/features/trusted_contacts/trusted_contacts_providers.dart';
import 'package:sincro_mobile/features/trusted_contacts/trusted_contacts_repository.dart';

TrustedContactsRepository _repoWith(List<Map<String, dynamic>> contacts) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test'));
  dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) => h.resolve(Response(requestOptions: o, statusCode: 200, data: contacts))));
  return TrustedContactsRepository(dio);
}

Future<void> _pump(WidgetTester tester, TrustedContactsRepository repo) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [trustedContactsRepositoryProvider.overrideWithValue(repo)],
    child: const MaterialApp(home: Scaffold(body: EmergencyButton())),
  ));
}

void main() {
  testWidgets('without contacts shows the existing hint snackbar', (tester) async {
    await _pump(tester, _repoWith([]));
    await tester.tap(find.text('Avisar Rede de Apoio'));
    await tester.pumpAndSettle();
    expect(find.text('Cadastre um contato de confiança primeiro.'), findsOneWidget);
  });

  testWidgets('with contacts opens the sheet', (tester) async {
    await _pump(tester, _repoWith([
      {'id': 'c1', 'nome': 'Marina Souza', 'relacao': 'PSICOLOGO', 'whatsapp': '+5511999999999', 'prioridade': 0},
    ]));
    await tester.tap(find.text('Avisar Rede de Apoio'));
    await tester.pumpAndSettle();
    expect(find.text('Quem avisar'), findsOneWidget);
    expect(find.text('Abrir WhatsApp para Marina'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd mobile && flutter test test/features/home/emergency_button_test.dart`
Expected: o segundo teste FALHA (abre `AlertDialog`, não a folha).

- [ ] **Step 3: Implementar**

Substituir `_handlePress` em `emergency_button.dart`:

```dart
  Future<void> _handlePress(BuildContext context, WidgetRef ref) async {
    try {
      final contacts = await ref.read(trustedContactsRepositoryProvider).list();
      if (!context.mounted) return;
      if (contacts.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cadastre um contato de confiança primeiro.')),
        );
        return;
      }
      await showEmergencySheet(context, contacts: contacts);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao preparar mensagem: ${e.toString()}')),
        );
      }
    }
  }
```

Trocar os imports: remover `url_launcher` e `emergency_providers.dart`; adicionar `import '../emergency/emergency_sheet.dart';`.

- [ ] **Step 4: Rodar e ver passar**

Run: `cd mobile && flutter test test/features/home test/features/emergency`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/home/emergency_button.dart mobile/test/features/home/emergency_button_test.dart
git commit -m "feat(mobile/home): botão de emergência abre a folha de aviso

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## Parte B — Profissionais

### Task 7: Busca por nome (`q`) no backend

**Files:**
- Modify: `backend/src/professionals/professionals.service.ts`
- Modify: `backend/src/professionals/professionals.controller.ts`
- Test: `backend/src/professionals/professionals.service.spec.ts`, `backend/src/professionals/professionals.controller.spec.ts`

**Interfaces:**
- Produces: `search(lat: number, lng: number, tags?: string[], q?: string)`; query `?q=` na rota.

- [ ] **Step 1: Testes que falham**

Em `professionals.service.spec.ts`, dentro de `describe('search', ...)`:

```ts
    it('filters by name (case-insensitive contains) when q is given, keeping distance sort', async () => {
      const prisma = buildPrismaMock();
      prisma.professional.findMany.mockResolvedValue([buildProfessional({ id: 'p1', nome: 'Helena Prado' })]);
      const service = new ProfessionalsService(prisma as any);

      const result = await service.search(0, 0, undefined, 'hel');

      expect(prisma.professional.findMany).toHaveBeenCalledWith({
        where: { ativo: true, nome: { contains: 'hel', mode: 'insensitive' } },
      });
      expect(result[0].distanciaKm).toBeDefined();
    });

    it('combines q with tags', async () => {
      const prisma = buildPrismaMock();
      prisma.professional.findMany.mockResolvedValue([]);
      const service = new ProfessionalsService(prisma as any);

      await service.search(0, 0, ['Psicólogo'], 'ana');

      expect(prisma.professional.findMany).toHaveBeenCalledWith({
        where: { ativo: true, tags: { hasSome: ['Psicólogo'] }, nome: { contains: 'ana', mode: 'insensitive' } },
      });
    });
```

Em `professionals.controller.spec.ts` (seguir o padrão já existente no arquivo para instanciar o controller com um service mock):

```ts
  it('forwards q trimmed to the service', async () => {
    const service = { search: jest.fn().mockResolvedValue([]), listActiveTags: jest.fn() };
    const controller = new ProfessionalsController(service as any);

    await controller.search('1', '2', undefined, '  Hel ');

    expect(service.search).toHaveBeenCalledWith(1, 2, undefined, 'Hel');
  });
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd backend && npm test -- professionals`
Expected: FAIL nas asserções de `findMany`/`search`.

- [ ] **Step 3: Implementar**

Service:

```ts
  async search(lat: number, lng: number, tags?: string[], q?: string) {
    const where: Record<string, unknown> = { ativo: true };
    if (tags && tags.length > 0) where.tags = { hasSome: tags };
    if (q && q.trim()) where.nome = { contains: q.trim(), mode: 'insensitive' };

    const professionals = await this.prisma.professional.findMany({ where });
    // ...restante igual (map distanciaKm + sort)
  }
```

Controller: adicionar `@Query('q') qRaw?: string` como quarto parâmetro e chamar `this.service.search(lat, lng, tags, qRaw?.trim() || undefined)`.

Como o service passa a ser chamado com 4 argumentos, dois testes existentes em `professionals.controller.spec.ts` deixam de casar (o Jest compara o número de argumentos). Atualizar:

- linha 53: `expect(service.search).toHaveBeenCalledWith(-23.5, -46.6, ['TEA', 'TDAH'], undefined);`
- linha 62: `expect(service.search).toHaveBeenCalledWith(-23.5, -46.6, undefined, undefined);`

- [ ] **Step 4: Rodar e ver passar**

Run: `cd backend && npm test -- professionals`
Expected: PASS. O teste antigo `sorts active professionals by distance` espera `{ where: { ativo: true } }` — continua válido.

- [ ] **Step 5: Commit**

```bash
git add backend/src/professionals
git commit -m "feat(professionals): busca por nome (q) na rota de proximidade

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: Reativar profissional (PATCH parcial com `ativo`)

**Files:**
- Modify: `backend/src/professionals/dto/update-professional.dto.ts`
- Test: `backend/src/professionals/dto/update-professional.dto.spec.ts` (criar)

**Contexto que decide o desenho:** `backend/src/main.ts:14` usa `new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true })` e hoje os 7 campos do `UpdateProfessionalDto` são obrigatórios. Um `PATCH` só com `{ ativo: true }` seria rejeitado com 400. `@nestjs/mapped-types` (`PartialType`) **não** está instalado, então a solução é marcar todos os campos com `@IsOptional()` (semântica correta de PATCH) e adicionar `ativo`. O `AdminProfessionalsRepository.update` do app continua enviando o objeto completo, então nada muda para a edição.

- [ ] **Step 1: Teste que falha**

`backend/src/professionals/dto/update-professional.dto.spec.ts` (usa `class-validator` e `class-transformer`, ambos já em `backend/package.json`):

```ts
import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { UpdateProfessionalDto } from './update-professional.dto';

describe('UpdateProfessionalDto', () => {
  it('accepts a partial body with only ativo (reactivation)', async () => {
    const dto = plainToInstance(UpdateProfessionalDto, { ativo: true });
    const errors = await validate(dto, { whitelist: true, forbidNonWhitelisted: true });
    expect(errors).toHaveLength(0);
  });

  it('still validates provided fields', async () => {
    const dto = plainToInstance(UpdateProfessionalDto, { telefone: '11999' });
    const errors = await validate(dto, { whitelist: true, forbidNonWhitelisted: true });
    expect(errors.map((e) => e.property)).toEqual(['telefone']);
  });

  it('rejects unknown fields', async () => {
    const dto = plainToInstance(UpdateProfessionalDto, { foo: 1 });
    const errors = await validate(dto, { whitelist: true, forbidNonWhitelisted: true });
    expect(errors.map((e) => e.property)).toEqual(['foo']);
  });
});
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd backend && npm test -- update-professional.dto.spec.ts`
Expected: FAIL no primeiro teste (7 erros "must be a string" etc.).

- [ ] **Step 3: Implementar no DTO**

Substituir o conteúdo de `update-professional.dto.ts` por:

```ts
import { ArrayNotEmpty, IsArray, IsBoolean, IsLatitude, IsLongitude, IsOptional, IsString, Length, Matches } from 'class-validator';

/** PATCH parcial: todo campo é opcional; os presentes são validados como no create. */
export class UpdateProfessionalDto {
  @IsOptional()
  @IsString()
  @Length(1, 100)
  nome?: string;

  @IsOptional()
  @IsArray()
  @ArrayNotEmpty()
  @IsString({ each: true })
  tags?: string[];

  @IsOptional()
  @IsString()
  @Length(1, 100)
  cidade?: string;

  @IsOptional()
  @IsLatitude()
  latitude?: number;

  @IsOptional()
  @IsLongitude()
  longitude?: number;

  @IsOptional()
  @IsString()
  @Length(8, 20)
  @Matches(/^\+\d{10,15}$/, {
    message: 'telefone must start with + followed by the country code and 10-15 digits, e.g. +5511999999999',
  })
  telefone?: string;

  @IsOptional()
  @IsString()
  @Length(1, 500)
  bio?: string;

  @IsOptional()
  @IsBoolean()
  ativo?: boolean;
}
```

`ProfessionalsService.update(id, dto)` já repassa `data: dto`; com campos `undefined` o Prisma não os altera.

- [ ] **Step 4: Rodar tudo**

Run: `cd backend && npm test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/src/professionals
git commit -m "feat(professionals): permite reativar via PATCH com ativo=true

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 9: Repositórios mobile: `q` na busca e `reactivate` no admin

**Files:**
- Modify: `mobile/lib/features/professionals/professionals_repository.dart`
- Modify: `mobile/lib/features/professionals/admin_professionals_repository.dart`
- Test: `mobile/test/features/professionals/professionals_repository_test.dart`, `mobile/test/features/professionals/admin_professionals_repository_test.dart`

**Interfaces:**
- Produces: `search({required double lat, required double lng, List<String> tags = const [], String? q})`; `Future<void> reactivate(String id)` (faz `PATCH /admin/professionals/$id` com `{'ativo': true}`).

- [ ] **Step 1: Testes que falham**

`professionals_repository_test.dart` (seguir o padrão de interceptor já usado no arquivo):

```dart
  test('search sends q only when non-empty', () async {
    Map<String, dynamic>? params;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      params = o.queryParameters;
      h.resolve(Response(requestOptions: o, statusCode: 200, data: []));
    }));
    final repo = ProfessionalsRepository(dio);

    await repo.search(lat: 1, lng: 2, q: 'hel');
    expect(params!['q'], 'hel');

    await repo.search(lat: 1, lng: 2, q: '   ');
    expect(params!.containsKey('q'), isFalse);
  });
```

`admin_professionals_repository_test.dart`:

```dart
  test('reactivate patches ativo=true', () async {
    String? method; Map<String, dynamic>? body; String? path;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      method = o.method; body = o.data as Map<String, dynamic>; path = o.path;
      h.resolve(Response(requestOptions: o, statusCode: 200, data: {}));
    }));

    await AdminProfessionalsRepository(dio).reactivate('p1');

    expect(method, 'PATCH');
    expect(path, '/admin/professionals/p1');
    expect(body, {'ativo': true});
  });
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd mobile && flutter test test/features/professionals/professionals_repository_test.dart test/features/professionals/admin_professionals_repository_test.dart`
Expected: FAIL (parâmetro/método inexistentes).

- [ ] **Step 3: Implementar**

`professionals_repository.dart`:

```dart
  Future<List<Professional>> search({
    required double lat,
    required double lng,
    List<String> tags = const [],
    String? q,
  }) async {
    final termo = q?.trim() ?? '';
    final response = await _dio.get('/professionals/search', queryParameters: {
      'lat': lat,
      'lng': lng,
      if (tags.isNotEmpty) 'tags': tags.join(','),
      if (termo.isNotEmpty) 'q': termo,
    });
    // ...igual
  }
```

`admin_professionals_repository.dart`:

```dart
  Future<void> reactivate(String id) async {
    await _dio.patch('/admin/professionals/$id', data: {'ativo': true});
  }
```

Depende da Task 8 (DTO de update com campos opcionais); sem ela o backend devolve 400 para este PATCH.

- [ ] **Step 4: Rodar e ver passar**

Run: `cd mobile && flutter test test/features/professionals`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/professionals mobile/test/features/professionals
git commit -m "feat(mobile/professionals): parâmetro q na busca e reactivate no admin

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 10: Campo "Buscar pelo nome" na tela de busca

**Files:**
- Modify: `mobile/lib/features/professionals/professionals_search_screen.dart`
- Test: `mobile/test/features/professionals/professionals_search_screen_test.dart`

- [ ] **Step 1: Teste que falha**

Acrescentar (usando o `_FakeLocationService(LocationPermissionResult.granted)` já existente; se `obterPosicaoAtual` não estiver sobrescrito na fake, adicionar `@override Future<Position> obterPosicaoAtual() async => Position(latitude: 0, longitude: 0, timestamp: DateTime(2026), accuracy: 0, altitude: 0, altitudeAccuracy: 0, heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0);`):

```dart
  testWidgets('typing a name re-runs the search with q after the debounce', (tester) async {
    final queries = <Map<String, dynamic>>[];
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      if (o.path == '/professionals/search') queries.add(Map.of(o.queryParameters));
      h.resolve(Response(requestOptions: o, statusCode: 200, data: []));
    }));

    await tester.pumpWidget(ProviderScope(
      overrides: [
        locationServiceProvider.overrideWithValue(_FakeLocationService(LocationPermissionResult.granted)),
        professionalsRepositoryProvider.overrideWithValue(ProfessionalsRepository(dio)),
      ],
      child: const MaterialApp(home: ProfessionalsSearchScreen()),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Buscar pelo nome'), 'Hel');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    expect(queries.last['q'], 'Hel');
  });
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd mobile && flutter test test/features/professionals/professionals_search_screen_test.dart`
Expected: FAIL (campo não existe).

- [ ] **Step 3: Implementar**

No `_ProfessionalsSearchScreenState`:

```dart
  final TextEditingController _nome = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _nome.dispose();
    super.dispose();
  }

  void _onNomeChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _buscar);
  }
```

Em `_buscar`, passar `q: _nome.text`. No `_buildBody`, quando há resultados (ou lista vazia com permissão concedida), envolver o conteúdo atual num `Column` cujo primeiro filho é:

```dart
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: AppInput(
            label: 'Buscar pelo nome',
            placeholder: 'Digite um nome',
            controller: _nome,
            onChanged: _onNomeChanged,
            suffixIcon: AppInputSuffixIcon.clear,
            onSuffixIconPressed: () { _nome.clear(); _buscar(); },
          ),
        ),
```

(`import 'dart:async';` e `import '../../core/widgets/app_input.dart';`.) O campo deve aparecer também no estado vazio, para o usuário poder limpar a busca. O spinner de `_carregando` durante a rebusca por nome não deve substituir o campo: manter o campo e mostrar o spinner só na área da lista (usar um `bool _buscandoLista` separado de `_carregando` para a busca inicial).

- [ ] **Step 4: Rodar e ver passar**

Run: `cd mobile && flutter test test/features/professionals/professionals_search_screen_test.dart`
Expected: PASS (todos, inclusive os antigos).

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/professionals/professionals_search_screen.dart mobile/test/features/professionals/professionals_search_screen_test.dart
git commit -m "feat(mobile/professionals): busca por nome com debounce na tela de proximidade

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 11: "Adicionar à rede de apoio" no detalhe do profissional

**Files:**
- Create: `mobile/lib/features/professionals/relacao_from_tags.dart`
- Modify: `mobile/lib/features/professionals/professional_detail_screen.dart` (vira `ConsumerStatefulWidget`)
- Test: `mobile/test/features/professionals/relacao_from_tags_test.dart`, `mobile/test/features/professionals/professional_detail_screen_test.dart`

**Interfaces:**
- Consumes: `trustedContactsRepositoryProvider.create(...)`, `trustedContactsListProvider`.
- Produces: `String relacaoFromTags(List<String> tags)`; `bool telefoneValidoParaContato(String telefone)` (regex `^\+\d{10,15}$` após remover espaços, hífens e parênteses).

- [ ] **Step 1: Testes que falham**

`relacao_from_tags_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/professionals/relacao_from_tags.dart';

void main() {
  test('maps tags to the trusted-contact relation', () {
    expect(relacaoFromTags(['Psicólogo', 'Adultos']), 'PSICOLOGO');
    expect(relacaoFromTags(['psiquiatra']), 'PSIQUIATRA');
    expect(relacaoFromTags(['T.O.']), 'T.O.');
    expect(relacaoFromTags(['Terapeuta Ocupacional']), 'T.O.');
    expect(relacaoFromTags(['Neuroafirmativo']), 'OUTRO');
    expect(relacaoFromTags([]), 'OUTRO');
  });

  test('validates the professional phone for a trusted contact', () {
    expect(telefoneValidoParaContato('+5511999990000'), isTrue);
    expect(telefoneValidoParaContato('+55 (11) 99999-0000'), isTrue);
    expect(telefoneValidoParaContato('11999990000'), isFalse);
  });
}
```

`professional_detail_screen_test.dart` hoje só tem dois testes puros de `buildWhatsAppUrl`/`buildTelUrl` (sem widgets); mantê-los e acrescentar os imports e os três testes abaixo:

```dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/professionals/professional.dart';
import 'package:sincro_mobile/features/professionals/professional_detail_screen.dart';
import 'package:sincro_mobile/features/trusted_contacts/trusted_contacts_providers.dart';
import 'package:sincro_mobile/features/trusted_contacts/trusted_contacts_repository.dart';

Professional _profissional({required List<String> tags, required String telefone}) => Professional(
    id: 'p1', nome: 'Helena Prado', tags: tags, cidade: 'São Paulo', latitude: 0, longitude: 0, telefone: telefone, bio: 'Bio', ativo: true);

TrustedContactsRepository _repoVazio() {
  final dio = Dio(BaseOptions(baseUrl: 'http://test'));
  dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) => h.resolve(Response(requestOptions: o, statusCode: 200, data: []))));
  return TrustedContactsRepository(dio);
}
```

```dart
  testWidgets('"Adicionar à rede de apoio" creates a trusted contact with the mapped relation', (tester) async {
    Map<String, dynamic>? body;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      if (o.method == 'POST') body = o.data as Map<String, dynamic>;
      h.resolve(Response(requestOptions: o, statusCode: o.method == 'POST' ? 201 : 200, data: o.method == 'POST' ? {} : []));
    }));

    await tester.pumpWidget(ProviderScope(
      overrides: [trustedContactsRepositoryProvider.overrideWithValue(TrustedContactsRepository(dio))],
      child: MaterialApp(home: ProfessionalDetailScreen(profissional: _profissional(tags: ['Psicólogo'], telefone: '+5511999990000'))),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Adicionar à rede de apoio'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Adicionar'));
    await tester.pumpAndSettle();

    expect(body, {
      'nome': 'Helena Prado', 'relacao': 'PSICOLOGO', 'whatsapp': '+5511999990000', 'prioridade': 0, 'consentimentoAceito': true,
    });
    expect(find.text('Adicionado à sua rede de apoio.'), findsOneWidget);
  });

  testWidgets('button is disabled when the phone is not a valid WhatsApp number', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [trustedContactsRepositoryProvider.overrideWithValue(_repoVazio())],
      child: MaterialApp(home: ProfessionalDetailScreen(profissional: _profissional(tags: ['Psicólogo'], telefone: '11 3333-0000'))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Telefone do profissional em formato inválido.'), findsOneWidget);
  });

  testWidgets('shows "Já está na sua rede de apoio" when a contact with the same whatsapp exists', (tester) async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) => h.resolve(Response(requestOptions: o, statusCode: 200, data: [
      {'id': 'c1', 'nome': 'Helena Prado', 'relacao': 'PSICOLOGO', 'whatsapp': '+5511999990000', 'prioridade': 0},
    ]))));
    await tester.pumpWidget(ProviderScope(
      overrides: [trustedContactsRepositoryProvider.overrideWithValue(TrustedContactsRepository(dio))],
      child: MaterialApp(home: ProfessionalDetailScreen(profissional: _profissional(tags: ['Psicólogo'], telefone: '+5511999990000'))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Já está na sua rede de apoio'), findsOneWidget);
  });
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd mobile && flutter test test/features/professionals/relacao_from_tags_test.dart test/features/professionals/professional_detail_screen_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implementar `relacao_from_tags.dart`**

```dart
final _whatsappRegex = RegExp(r'^\+\d{10,15}$');

String relacaoFromTags(List<String> tags) {
  final lower = tags.map((t) => t.toLowerCase()).toList();
  if (lower.any((t) => t.contains('psiquiat'))) return 'PSIQUIATRA';
  if (lower.any((t) => t.contains('psic'))) return 'PSICOLOGO';
  if (lower.any((t) => t.contains('t.o') || t.contains('terapeuta ocupacional'))) return 'T.O.';
  return 'OUTRO';
}

String normalizarTelefone(String telefone) => telefone.replaceAll(RegExp(r'[\s()\-]'), '');

bool telefoneValidoParaContato(String telefone) => _whatsappRegex.hasMatch(normalizarTelefone(telefone));
```

(Ordem importa: "psiquiatra" também contém "psi", por isso testa psiquiatra antes.)

- [ ] **Step 4: Implementar na tela de detalhe**

Converter `ProfessionalDetailScreen` em `ConsumerStatefulWidget`. Estado: `bool _adicionando = false;`. Abaixo dos dois botões existentes:

```dart
            const SizedBox(height: 24),
            Text(
              'Ao adicionar, a pessoa passa a aparecer em Rede de apoio e pode receber seu aviso de emergência.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            _buildAdicionarButton(context),
```

```dart
  Widget _buildAdicionarButton(BuildContext context) {
    final telefoneOk = telefoneValidoParaContato(widget.profissional.telefone);
    final contatosAsync = ref.watch(trustedContactsListProvider);
    final jaExiste = contatosAsync.maybeWhen(
      data: (c) => c.any((x) => normalizarTelefone(x.whatsapp) == normalizarTelefone(widget.profissional.telefone)),
      orElse: () => false,
    );
    if (jaExiste) {
      return const AppButton(label: 'Já está na sua rede de apoio', size: AppButtonSize.large, icon: Icons.check, onPressed: null);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppButton(
          label: _adicionando ? 'Adicionando…' : 'Adicionar à rede de apoio',
          size: AppButtonSize.large,
          icon: Icons.favorite_outline,
          isLoading: _adicionando,
          onPressed: telefoneOk && !_adicionando ? () => _abrirDialogo(context) : null,
        ),
        if (!telefoneOk)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Telefone do profissional em formato inválido.', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
      ],
    );
  }

  Future<void> _abrirDialogo(BuildContext context) async {
    var relacao = relacaoFromTags(widget.profissional.tags);
    var consentimento = false;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Adicionar à rede de apoio'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                // `value:` está deprecado no Flutter 3.47 (gera warning no analyze); com
                // `initialValue` o campo guarda o próprio estado e `onChanged` só registra a escolha.
                initialValue: relacao,
                decoration: const InputDecoration(labelText: 'Relação'),
                items: const ['PSICOLOGO', 'PSIQUIATRA', 'T.O.', 'FAMILIAR', 'OUTRO']
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (v) => relacao = v ?? relacao,
              ),
              CheckboxListTile(
                value: consentimento,
                onChanged: (v) => setDialogState(() => consentimento = v ?? false),
                title: const Text(
                  'Você autoriza o Sincro a preparar mensagens de alerta para este contato em momentos de crise. Você sempre confirma antes do envio.',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
            ElevatedButton(onPressed: consentimento ? () => Navigator.pop(dialogContext, true) : null, child: const Text('Adicionar')),
          ],
        ),
      ),
    );
    if (confirmado != true || !mounted) return;

    setState(() => _adicionando = true);
    try {
      await ref.read(trustedContactsRepositoryProvider).create(
            nome: widget.profissional.nome,
            relacao: relacao,
            whatsapp: normalizarTelefone(widget.profissional.telefone),
            prioridade: 0,
            consentimentoAceito: true,
          );
      ref.invalidate(trustedContactsListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Adicionado à sua rede de apoio.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível adicionar. Tente novamente.')));
      }
    } finally {
      if (mounted) setState(() => _adicionando = false);
    }
  }
```

Imports: `flutter_riverpod`, `../../core/widgets/app_button.dart`, `../trusted_contacts/trusted_contacts_providers.dart`, `relacao_from_tags.dart`. Trocar `profissional.` por `widget.profissional.` nos métodos existentes.

- [ ] **Step 5: Rodar e ver passar**

Run: `cd mobile && flutter test test/features/professionals && flutter analyze`
Expected: PASS, sem warnings novos.

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/features/professionals mobile/test/features/professionals
git commit -m "feat(mobile/professionals): adicionar profissional à rede de apoio a partir do detalhe

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 12: Admin — busca, "Mostrar inativos" e "Reativar"

**Files:**
- Create: `mobile/lib/features/professionals/admin_professionals_filter.dart`
- Modify: `mobile/lib/features/professionals/admin_professionals_list_screen.dart`
- Test: `mobile/test/features/professionals/admin_professionals_filter_test.dart`, `mobile/test/features/professionals/admin_professionals_list_screen_test.dart` (criar)

**Interfaces:**
- Produces: `List<Professional> filtrarProfissionaisAdmin(List<Professional> todos, {required String termo, required bool mostrarInativos})` e `String resumoContagem(List<Professional> todos)` → `"N ativos · M inativos"` (singular `1 ativo` / `1 inativo`).

- [ ] **Step 1: Testes que falham**

`admin_professionals_filter_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/professionals/admin_professionals_filter.dart';
import 'package:sincro_mobile/features/professionals/professional.dart';

Professional _p(String nome, {bool ativo = true, List<String> tags = const [], String cidade = 'SP'}) => Professional(
    id: nome, nome: nome, tags: tags, cidade: cidade, latitude: 0, longitude: 0, telefone: '+5511999999999', bio: '', ativo: ativo);

void main() {
  final todos = [_p('Helena', tags: ['Psicólogo']), _p('Marcos', cidade: 'Guarulhos'), _p('Ana', ativo: false)];

  test('hides inactive by default and searches name, city and tag case-insensitively', () {
    expect(filtrarProfissionaisAdmin(todos, termo: '', mostrarInativos: false).map((p) => p.nome), ['Helena', 'Marcos']);
    expect(filtrarProfissionaisAdmin(todos, termo: 'psic', mostrarInativos: false).map((p) => p.nome), ['Helena']);
    expect(filtrarProfissionaisAdmin(todos, termo: 'guaru', mostrarInativos: false).map((p) => p.nome), ['Marcos']);
    expect(filtrarProfissionaisAdmin(todos, termo: 'ana', mostrarInativos: true).map((p) => p.nome), ['Ana']);
  });

  test('summarises counts with singular/plural', () {
    expect(resumoContagem(todos), '2 ativos · 1 inativo');
    expect(resumoContagem([todos.first]), '1 ativo · 0 inativos');
  });
}
```

`admin_professionals_list_screen_test.dart` (arquivo novo, completo):

```dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/professionals/admin_professionals_list_screen.dart';
import 'package:sincro_mobile/features/professionals/admin_professionals_repository.dart';
import 'package:sincro_mobile/features/professionals/professionals_providers.dart';

void main() {
  testWidgets('shows search field, count and reactivate for inactive when toggled', (tester) async {
    String? patchPath;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      if (o.method == 'PATCH') { patchPath = o.path; h.resolve(Response(requestOptions: o, statusCode: 200, data: {})); return; }
      h.resolve(Response(requestOptions: o, statusCode: 200, data: [
        {'id': 'p1', 'nome': 'Helena', 'tags': ['Psicólogo'], 'cidade': 'SP', 'latitude': 0, 'longitude': 0, 'telefone': '+5511999999999', 'bio': '', 'ativo': true},
        {'id': 'p2', 'nome': 'Ana', 'tags': ['Psicólogo'], 'cidade': 'SP', 'latitude': 0, 'longitude': 0, 'telefone': '+5511999999999', 'bio': '', 'ativo': false},
      ]));
    }));
    await tester.pumpWidget(ProviderScope(
      overrides: [adminProfessionalsRepositoryProvider.overrideWithValue(AdminProfessionalsRepository(dio))],
      child: const MaterialApp(home: AdminProfessionalsListScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('1 ativo · 1 inativo'), findsOneWidget);
    expect(find.text('Ana (inativo)'), findsNothing);

    await tester.tap(find.text('Mostrar inativos'));
    await tester.pumpAndSettle();
    expect(find.text('Ana (inativo)'), findsOneWidget);

    await tester.tap(find.text('Reativar'));
    await tester.pumpAndSettle();
    expect(patchPath, '/admin/professionals/p2');
  });
}
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd mobile && flutter test test/features/professionals/admin_professionals_filter_test.dart test/features/professionals/admin_professionals_list_screen_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implementar o filtro**

```dart
import 'professional.dart';

List<Professional> filtrarProfissionaisAdmin(List<Professional> todos, {required String termo, required bool mostrarInativos}) {
  final t = termo.trim().toLowerCase();
  return todos.where((p) {
    if (!mostrarInativos && !p.ativo) return false;
    if (t.isEmpty) return true;
    return p.nome.toLowerCase().contains(t) ||
        p.cidade.toLowerCase().contains(t) ||
        p.tags.any((tag) => tag.toLowerCase().contains(t));
  }).toList();
}

String resumoContagem(List<Professional> todos) {
  final ativos = todos.where((p) => p.ativo).length;
  final inativos = todos.length - ativos;
  return '$ativos ${ativos == 1 ? 'ativo' : 'ativos'} · $inativos ${inativos == 1 ? 'inativo' : 'inativos'}';
}
```

- [ ] **Step 4: Implementar na tela**

Converter `AdminProfessionalsListScreen` em `ConsumerStatefulWidget` com `String _termo = ''; bool _mostrarInativos = false;`. No `data:` do `when`, construir:

```dart
          final visiveis = filtrarProfissionaisAdmin(professionals, termo: _termo, mostrarInativos: _mostrarInativos);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: AppInput(label: 'Buscar', placeholder: 'Nome, cidade ou tag', onChanged: (v) => setState(() => _termo = v)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(child: Text(resumoContagem(professionals), style: Theme.of(context).textTheme.bodyMedium)),
                    FilterChip(
                      label: const Text('Mostrar inativos'),
                      selected: _mostrarInativos,
                      onSelected: (v) => setState(() => _mostrarInativos = v),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: professionals.isEmpty
                    ? const Center(child: Text('Nenhum profissional cadastrado ainda.'))
                    : visiveis.isEmpty
                        ? const Center(child: Text('Nenhum profissional encontrado por aqui ainda.'))
                        : ListView.builder(itemCount: visiveis.length, itemBuilder: (context, index) => _tile(context, visiveis[index])),
              ),
            ],
          );
```

Import necessário: `import '../../core/widgets/app_input.dart';`. `_tile` é o `itemBuilder` atual (`admin_professionals_list_screen.dart:53-72`) extraído para um método `Widget _tile(BuildContext context, Professional profissional)` sem mudar seu conteúdo, exceto o `trailing` do inativo, que passa a ser `TextButton(onPressed: () => _reativar(context, profissional), child: const Text('Reativar'))`, com:

```dart
  Future<void> _reativar(BuildContext context, Professional p) async {
    try {
      await ref.read(adminProfessionalsRepositoryProvider).reactivate(p.id);
      ref.invalidate(adminProfessionalsListProvider);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível reativar. Tente novamente.')));
      }
    }
  }
```

- [ ] **Step 5: Rodar e ver passar**

Run: `cd mobile && flutter test test/features/professionals`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/features/professionals mobile/test/features/professionals
git commit -m "feat(mobile/professionals): admin com busca, filtro de inativos e reativar

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 13: Admin form — "Usar minha localização atual"

**Files:**
- Modify: `mobile/lib/features/professionals/admin_professional_form_screen.dart`
- Test: `mobile/test/features/professionals/admin_professional_form_screen_test.dart`

- [ ] **Step 1: Teste que falha**

`admin_professional_form_screen_test.dart` hoje testa só `extractServerErrorMessage` (nenhum widget); a `_FakeLocationService` de `professionals_search_screen_test.dart` é privada daquele arquivo e não sobrescreve `obterPosicaoAtual`, então escrever a fake aqui, completa:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sincro_mobile/features/professionals/admin_professional_form_screen.dart';
import 'package:sincro_mobile/features/professionals/location_service.dart';
import 'package:sincro_mobile/features/professionals/professionals_providers.dart';

class _FakeLocationService extends LocationService {
  _FakeLocationService(this.resultado);
  final LocationPermissionResult resultado;

  @override
  Future<LocationPermissionResult> solicitarPermissao() async => resultado;

  @override
  Future<Position> obterPosicaoAtual() async => Position(
        latitude: -23.5505,
        longitude: -46.6333,
        timestamp: DateTime(2026, 9, 15),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
}
```

Testes (o construtor `AdminProfessionalFormScreen()` sem argumentos abre o modo "Novo profissional"):

```dart
  testWidgets('"Usar minha localização atual" fills latitude and longitude', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [locationServiceProvider.overrideWithValue(_FakeLocationService(LocationPermissionResult.granted))],
      child: const MaterialApp(home: AdminProfessionalFormScreen()),
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Usar minha localização atual'));
    await tester.tap(find.text('Usar minha localização atual'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, '-23.5505'), findsOneWidget);
    expect(find.widgetWithText(TextField, '-46.6333'), findsOneWidget);
  });

  testWidgets('denied permission shows the shared permission message', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [locationServiceProvider.overrideWithValue(_FakeLocationService(LocationPermissionResult.denied))],
      child: const MaterialApp(home: AdminProfessionalFormScreen()),
    ));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Usar minha localização atual'));
    await tester.tap(find.text('Usar minha localização atual'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Precisamos da sua localização'), findsOneWidget);
  });
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd mobile && flutter test test/features/professionals/admin_professional_form_screen_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implementar**

Abaixo dos campos Latitude/Longitude:

```dart
            TextButton.icon(
              onPressed: _usarLocalizacaoAtual,
              icon: const Icon(Icons.my_location_outlined),
              label: const Text('Usar minha localização atual'),
            ),
```

```dart
  Future<void> _usarLocalizacaoAtual() async {
    final location = ref.read(locationServiceProvider);
    final permissao = await location.solicitarPermissao();
    if (!mounted) return;
    if (permissao != LocationPermissionResult.granted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensagemPermissao(permissao))));
      return;
    }
    final pos = await location.obterPosicaoAtual();
    if (!mounted) return;
    setState(() {
      _latitudeController.text = pos.latitude.toStringAsFixed(4);
      _longitudeController.text = pos.longitude.toStringAsFixed(4);
    });
  }
```

Os controllers chamam-se `_latitudeController` e `_longitudeController` (`admin_professional_form_screen.dart:24-25`). Adicionar dois imports ao arquivo (hoje ele importa só dio, material, riverpod, `dio_error_message.dart`, `admin_professional_form_validation.dart`, `professional.dart` e `professionals_providers.dart`): `import 'location_service.dart';` (para `LocationPermissionResult`) e `import 'professionals_search_screen.dart';` (para `mensagemPermissao`, função de topo na linha 8 desse arquivo).

- [ ] **Step 4: Rodar e ver passar**

Run: `cd mobile && flutter test test/features/professionals`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/professionals mobile/test/features/professionals
git commit -m "feat(mobile/professionals): usar localização atual no formulário admin

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## Parte C — UI Direção A

### Task 14: Login com logo real e cabeçalho centralizado

**Files:**
- Modify: `mobile/lib/features/auth/login_screen.dart:106-200`
- Test: `mobile/test/features/auth/login_screen_test.dart` (criar)

- [ ] **Step 1: Teste que falha**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/auth/login_screen.dart';

void main() {
  testWidgets('login header shows the real logo and no emoji tile', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: LoginScreen())));
    await tester.pumpAndSettle();

    expect(find.text('💚'), findsNothing);
    final image = tester.widget<Image>(find.byType(Image).first);
    expect((image.image as AssetImage).assetName, 'assets/logos/symbol_transparent_512x512.png');
    expect(find.text('Sincro'), findsOneWidget);
    expect(find.text('Bem-vindo de volta'), findsOneWidget);
    expect(find.text('Entrar'), findsOneWidget);
    expect(find.text('Entrar com Google'), findsOneWidget);
    expect(find.text('Criar uma conta'), findsOneWidget);
  });
}
```

Se `LoginScreen` ler `SharedPreferences` no `initState`, adicionar `SharedPreferences.setMockInitialValues({});` no início do teste (`import 'package:shared_preferences/shared_preferences.dart';`).

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd mobile && flutter test test/features/auth/login_screen_test.dart`
Expected: FAIL (emoji presente, sem `Image`).

- [ ] **Step 3: Implementar**

Em `login_screen.dart`:
1. Remover `_fadeController`, `_slideController`, as `Animation`s, o `FadeTransition`/`SlideTransition` e o `TickerProviderStateMixin` (manter `ConsumerState`).
2. Remover o `Container` com `gradient` do `Stack` e o próprio `Stack` (o `body` vira o `SingleChildScrollView`).
3. Substituir o `Container` 80×80 com `'💚'` por:

```dart
                            Image.asset(
                              'assets/logos/symbol_transparent_512x512.png',
                              width: 96,
                              height: 96,
                              semanticLabel: 'Sincro',
                            ),
```

4. `'Sincro'` passa a usar `theme.textTheme.headlineMedium?.copyWith(fontSize: 24)` (o tema define `headlineMedium` em 22 sp bold; não existe estilo de 24 sp em `theme.dart`, por isso o `copyWith`) e `'Bem-vindo de volta'` usa `theme.textTheme.bodyLarge?.copyWith(color: colorScheme.onSurfaceVariant)`.
5. `SizedBox(height: MediaQuery.of(context).padding.top + 32)` → `+ 16`; o `SizedBox(height: 48)` entre cabeçalho e formulário → `32`.

- [ ] **Step 4: Rodar e ver passar**

Run: `cd mobile && flutter test test/features/auth && flutter analyze`
Expected: PASS, sem warnings novos.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/auth/login_screen.dart mobile/test/features/auth/login_screen_test.dart
git commit -m "feat(mobile/auth): login com logo real e cabeçalho da direção A

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 15: Widget `SectionCard` (cartão agrupado com divisores)

**Files:**
- Create: `mobile/lib/core/widgets/section_card.dart`
- Test: `mobile/test/core/section_card_test.dart`

**Interfaces:**
- Produces: `class SectionCard extends StatelessWidget { const SectionCard({super.key, required this.children, this.title}); final List<Widget> children; final String? title; }` — renderiza `title` (16 bold) acima, e um `Card` com `children` intercalados por `Divider(height: 1, indent: 16, endIndent: 16)`.

- [ ] **Step 1: Teste que falha**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/core/widgets/section_card.dart';

void main() {
  testWidgets('renders title, children and n-1 dividers', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SectionCard(title: 'Apoio', children: [Text('a'), Text('b'), Text('c')])),
    ));
    expect(find.text('Apoio'), findsOneWidget);
    expect(find.byType(Divider), findsNWidgets(2));
    expect(find.byType(Card), findsOneWidget);
  });
}
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd mobile && flutter test test/core/section_card_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implementar**

```dart
import 'package:flutter/material.dart';

/// Cartão agrupado da direção A: título opcional (16 bold) + `Card` do tema com linhas
/// separadas por divisores internos. As linhas costumam ser `ListTile`s de 56 dp.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.children, this.title});

  final List<Widget> children;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(Divider(height: 1, indent: 16, endIndent: 16, color: scheme.outline));
      rows.add(children[i]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) ...[
          Text(title!, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
        ],
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: scheme.outline)),
          clipBehavior: Clip.antiAlias,
          child: Column(children: rows),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Rodar e ver passar**

Run: `cd mobile && flutter test test/core/section_card_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/core/widgets/section_card.dart mobile/test/core/section_card_test.dart
git commit -m "feat(mobile/core): SectionCard para listas agrupadas

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 16: Home `resumo + minimalista` na direção A

**Files:**
- Modify: `mobile/lib/features/home/home_screen.dart:156-192` (`_HomeMinimalistaResumoView`), `:260-277` (`_GmailCard._connect`) e `:322-455` (`_FinancasCard`, só leitura para reaproveitar `_pendentesCount` e o `NumberFormat` já importado)
- Test: `mobile/test/features/home/home_minimalista_resumo_test.dart` (criar)

**Interfaces:**
- Consumes: `SectionCard` (Task 15), `EmergencyButton` (Task 6), providers já usados na view (`financeSummaryProvider`, `gmailConnectionStatusProvider`, `upcomingEventsProvider`, `biofeedbackAtivoProvider`, `trustedContactsListProvider`).

- [ ] **Step 1: Teste que falha**

`_HomeMinimalistaResumoView` é privada, então o teste monta `HomeScreen` com os providers de layout/estilo forçados (mesmo padrão de `mobile/test/features/home/financas_card_test.dart`). Arquivo completo:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/core/theme.dart';
import 'package:sincro_mobile/core/widgets/section_card.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_providers.dart';
import 'package:sincro_mobile/features/calendar/calendar_event.dart';
import 'package:sincro_mobile/features/calendar/calendar_providers.dart';
import 'package:sincro_mobile/features/email_triage/email_triage_providers.dart';
import 'package:sincro_mobile/features/email_triage/gmail_connection_repository.dart';
import 'package:sincro_mobile/features/financas/finance_providers.dart';
import 'package:sincro_mobile/features/financas/finance_summary.dart';
import 'package:sincro_mobile/features/financas/lancamento_financeiro.dart';
import 'package:sincro_mobile/features/home/home_design_style.dart';
import 'package:sincro_mobile/features/home/home_layout_mode.dart';
import 'package:sincro_mobile/features/home/home_providers.dart';
import 'package:sincro_mobile/features/home/home_screen.dart';
import 'package:sincro_mobile/features/trusted_contacts/trusted_contacts_providers.dart';

List<Override> _overrides() => [
      homeLayoutModeProvider.overrideWith((ref) async => HomeLayoutMode.resumo),
      homeDesignStyleProvider.overrideWith((ref) async => HomeDesignStyle.minimalista),
      upcomingEventsProvider.overrideWith((ref) async => <CalendarEvent>[]),
      biofeedbackAtivoProvider.overrideWith((ref) async => false),
      gmailConnectionStatusProvider.overrideWith((ref) async => const GmailConnectionStatus(connected: false)),
      financeSummaryProvider.overrideWith((ref) async => FinanceSummary(
            saldoLivre: 1240,
            saldoContas: 0,
            faturasAbertas: 0,
            despesasPendentesCiclo: 0,
            cicloFim: DateTime.utc(2026, 10, 4),
          )),
      lancamentosPendentesProvider.overrideWith((ref) async => <LancamentoFinanceiro>[]),
      trustedContactsListProvider.overrideWith((ref) async => []),
    ];

Future<void> pumpHomeMinimalistaResumo(WidgetTester tester) => tester.pumpWidget(ProviderScope(
      overrides: _overrides(),
      child: MaterialApp(theme: sincroLightTheme, home: const HomeScreen()),
    ));

void main() {
  testWidgets('minimalista/resumo shows greeting, finance hero, grouped rows, Apoio and pinned emergency', (tester) async {
    await pumpHomeMinimalistaResumo(tester);
    await tester.pumpAndSettle();

    expect(find.text('Você está em dia'), findsOneWidget);
    expect(find.text('Tudo sob controle'), findsOneWidget);
    expect(find.text('Saldo Livre'), findsOneWidget);
    expect(find.text('Ver finanças'), findsOneWidget);
    expect(find.text('Caixa de Entrada'), findsOneWidget);
    expect(find.text('Próximos eventos'), findsOneWidget);
    expect(find.text('Biofeedback'), findsOneWidget);
    expect(find.text('Apoio'), findsOneWidget);
    expect(find.text('Encontrar profissional'), findsOneWidget);
    expect(find.text('Alívio sensorial'), findsOneWidget);
    expect(find.byType(SectionCard), findsNWidgets(2));

    // botão de emergência fora da rolagem: continua encontrável após rolar a lista até o fim
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('Avisar Rede de Apoio'), findsOneWidget);
    final buttonRect = tester.getRect(find.text('Avisar Rede de Apoio'));
    expect(buttonRect.bottom, lessThanOrEqualTo(tester.view.physicalSize.height / tester.view.devicePixelRatio));
  });
}
```

Se o construtor de `FinanceSummary` tiver campos além dos cinco listados, copiar a instância usada em `financas_card_test.dart`.

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd mobile && flutter test test/features/home/home_minimalista_resumo_test.dart`
Expected: FAIL ('Você está em dia' não existe nessa view; hoje é 'Tudo em ordem por hoje.').

- [ ] **Step 3: Reescrever `_HomeMinimalistaResumoView`**

```dart
class _HomeMinimalistaResumoView extends ConsumerWidget {
  const _HomeMinimalistaResumoView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final gmailStatusAsync = ref.watch(gmailConnectionStatusProvider);
    final calendarEventsAsync = ref.watch(upcomingEventsProvider);
    final biofeedbackAtivoAsync = ref.watch(biofeedbackAtivoProvider);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Você está em dia', style: theme.textTheme.headlineMedium?.copyWith(fontSize: 24)),
                Text('Tudo sob controle', style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 12),
                const _FinancasHeroCard(),
                const SizedBox(height: 12),
                SectionCard(children: [
                  _GmailRow(statusAsync: gmailStatusAsync),
                  _CalendarRow(eventsAsync: calendarEventsAsync),
                  _BiofeedbackRow(ativoAsync: biofeedbackAtivoAsync),
                ]),
                const SizedBox(height: 12),
                const SectionCard(title: 'Apoio', children: [_ProfessionalsRow(), _GroundingCardsRow()]),
              ],
            ),
          ),
        ),
        const SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: _EmergencySection(),
          ),
        ),
      ],
    );
  }
}
```

Os `_XxxRow` são `ListTile`s de 56 dp que reaproveitam a lógica dos cards `_GmailCard`, `_CalendarCard`, `_BiofeedbackCard`, `_ProfessionalsCard`, `_GroundingCardsCard` (mesmos providers, mesmos textos, mesma navegação, **mesmos estados de loading/erro** — a spec deixa estados fora de escopo), só sem o `Card` envolvente.

Primeiro extrair `_GmailCard._connect` (`home_screen.dart:260-277`) para uma função de topo `Future<void> _conectarGmail(BuildContext context, WidgetRef ref)` com o mesmo corpo, e fazer `_GmailCard` chamá-la — assim `_GmailRow` reutiliza a mesma lógica. Exemplo para o Gmail (repetir o padrão para os demais, mantendo exatamente os títulos/subtítulos/ações já existentes nos cards):

```dart
class _GmailRow extends ConsumerWidget {
  const _GmailRow({required this.statusAsync});
  final AsyncValue<GmailConnectionStatus> statusAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return statusAsync.when(
      data: (status) => ListTile(
        leading: const _RowIcon(Icons.mail_outline),
        title: const Text('Caixa de Entrada'),
        subtitle: Text(status.connected ? 'Conectado como ${status.gmailEmail}' : 'Conecte seu Gmail para ver um resumo calmo dos seus e-mails.'),
        trailing: status.connected ? const Icon(Icons.chevron_right) : TextButton(onPressed: () => _conectarGmail(context, ref), child: const Text('Conectar Gmail')),
        onTap: status.connected ? () => Navigator.of(context).pushNamed('/inbox') : null,
      ),
      loading: () => const ListTile(title: Text('Caixa de Entrada'), subtitle: Text('Carregando...')),
      error: (_, __) => const SizedBox.shrink(), // mesmo comportamento de _GmailCard hoje (home_screen.dart:314)
    );
  }
}

class _RowIcon extends StatelessWidget {
  const _RowIcon(this.icon);
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 40, height: 40,
      decoration: BoxDecoration(color: scheme.primary.withAlpha(26), borderRadius: BorderRadius.circular(12)),
      child: Icon(icon, color: scheme.primary, size: 20),
    );
  }
}
```

(Usar os nomes reais do tipo do status e do método de conexão que `_GmailCard` já usa — copiar de lá.) Biofeedback: `trailing: OutlinedButton(child: Text('Ativar Biofeedback'))` quando inativo, chevron quando ativo.

- [ ] **Step 4: Criar `_FinancasHeroCard`**

Reusar `financeSummaryProvider` e `_pendentesCount(ref)` de `_FinancasCard`:

```dart
class _FinancasHeroCard extends ConsumerWidget {
  const _FinancasHeroCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final summaryAsync = ref.watch(financeSummaryProvider);
    final pendentes = _pendentesCount(ref);
    void abrir() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FinancasScreen()));

    return Container(
      decoration: BoxDecoration(
        color: scheme.primary.withAlpha(15),
        border: Border.all(color: scheme.primary.withAlpha(64)),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: summaryAsync.when(
        loading: () => const SizedBox(height: 96, child: Center(child: CircularProgressIndicator())),
        error: (_, __) => InkWell(onTap: abrir, child: Text('Não foi possível carregar seu resumo agora. Toque para ver Finanças.', style: theme.textTheme.bodySmall)),
        data: (summary) {
          final saldo = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(summary.saldoLivre);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.account_balance_outlined, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Text('Saldo Livre', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 4),
              Text(saldo, style: theme.textTheme.headlineMedium?.copyWith(fontSize: 34, color: scheme.primary, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(
                  child: pendentes != null && pendentes > 0
                      ? Text(
                          '$pendentes ${pendentes == 1 ? "lançamento" : "lançamentos"} para revisar, sem pressa',
                          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                        )
                      : const SizedBox.shrink(),
                ),
                TextButton.icon(
                  onPressed: abrir,
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  iconAlignment: IconAlignment.end,
                  label: const Text('Ver finanças'),
                ),
              ]),
            ],
          );
        },
      ),
    );
  }
}
```

Sem pendências a linha some (nenhuma string nova; `financas_card_test.dart:174` exige que "para revisar" não apareça nesse caso).

- [ ] **Step 5: Rodar e ver passar**

Run: `cd mobile && flutter test test/features/home && flutter analyze`
Expected: PASS. Atenção: `financas_card_test.dart` roda **também** a combinação `(resumo, minimalista)` (linha 49 fixa `resumo`, linha 93 itera os três estilos) e exige, no estado de erro, um toque que abra `FinancasScreen`, e no estado com dados o texto "N lançamentos para revisar, sem pressa" e um "Ver finanças" tocável — o `_FinancasHeroCard` cumpre os três (erro com `InkWell`, contagem, `TextButton.icon`). Os testes procuram `find.textContaining('Ver finanças')` (`financas_card_test.dart:147,175` e `financas_abas_layout_test.dart:84,122,161`), então o rótulo `'Ver finanças'` com ícone de seta satisfaz tanto esses quanto o `find.text('Ver finanças')` do teste novo.

- [ ] **Step 6: Verificar no aparelho/emulador**

Run: `cd mobile && flutter run` com Configurações → Layout "Resumo simples" e Estilo "Minimalista Refinado". Conferir em um aparelho de ~390×844 dp que o botão "Avisar Rede de Apoio" fica visível sem rolar e que a lista rola por baixo dele.

- [ ] **Step 7: Commit**

```bash
git add mobile/lib/features/home/home_screen.dart mobile/test/features/home/home_minimalista_resumo_test.dart
git commit -m "feat(mobile/home): layout resumo/minimalista na direção A com emergência fixa

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## Fechamento

- [ ] Rodar `cd backend && npm test` e `cd mobile && flutter test && flutter analyze` — tudo verde.
- [ ] Atualizar `mobile/lib/features/guide/guide_content.dart` só se o texto do item "Emergência" mencionar "primeiro contato" (agora é multi-seleção); manter `guiaVersaoAtual` se nada mudar.
- [ ] Registrar no vault (`wiki/projetos/sincro_07_status_atual_backlog_em_andamento.md`) que as Partes A, B e C entraram, com o hash do merge.

## Self-review (feito ao escrever)

- Spec → tarefas: Login (T14), Home (T15–16), Emergência backend (T1–2) e mobile (T3–6), Profissionais backend (T7–8) e mobile (T9–13). "Fora de escopo" da spec não tem tarefa, por decisão.
- Nomes consistentes: `buildMessages`, `EmergencySendQueue`, `emergencyCtaLabel`, `primeiroNome`, `kEmergencyDefaultTemplate`, `relacaoFromTags`, `telefoneValidoParaContato`, `normalizarTelefone`, `filtrarProfissionaisAdmin`, `resumoContagem`, `reactivate`, `SectionCard` — usados com a mesma grafia em todas as tarefas.
- Risco conhecido: T9/T12 dependem de como o `ValidationPipe` trata `PATCH` parcial (ver nota em T9).
