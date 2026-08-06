import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'admin_professional_form_validation.dart';
import 'professional.dart';
import 'professionals_providers.dart';

/// Extracts a human-readable message from a Nest validation-error response
/// shaped as `{ statusCode, message, error }`, where `message` may be a
/// string or an array of strings.
String extractServerErrorMessage(DioException e) {
  final data = e.response?.data;
  if (data is Map) {
    final message = data['message'];
    if (message is List) {
      final joined = message.map((m) => m.toString()).join('; ');
      if (joined.isNotEmpty) return joined;
    } else if (message is String && message.isNotEmpty) {
      return message;
    }
  }
  return 'Não foi possível salvar. Tente novamente.';
}

class AdminProfessionalFormScreen extends ConsumerStatefulWidget {
  const AdminProfessionalFormScreen({super.key, this.profissional});

  final Professional? profissional;

  @override
  ConsumerState<AdminProfessionalFormScreen> createState() => _AdminProfessionalFormScreenState();
}

class _AdminProfessionalFormScreenState extends ConsumerState<AdminProfessionalFormScreen> {
  late final TextEditingController _nomeController;
  late final TextEditingController _tagsController;
  late final TextEditingController _cidadeController;
  late final TextEditingController _telefoneController;
  late final TextEditingController _bioController;
  late final TextEditingController _latitudeController;
  late final TextEditingController _longitudeController;
  bool _salvando = false;
  String? _erro;

  bool get _editando => widget.profissional != null;

  @override
  void initState() {
    super.initState();
    final p = widget.profissional;
    _nomeController = TextEditingController(text: p?.nome ?? '');
    _tagsController = TextEditingController(text: p?.tags.join(', ') ?? '');
    _cidadeController = TextEditingController(text: p?.cidade ?? '');
    _telefoneController = TextEditingController(text: p?.telefone ?? '');
    _bioController = TextEditingController(text: p?.bio ?? '');
    _latitudeController = TextEditingController(text: p?.latitude.toString() ?? '');
    _longitudeController = TextEditingController(text: p?.longitude.toString() ?? '');
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _tagsController.dispose();
    _cidadeController.dispose();
    _telefoneController.dispose();
    _bioController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    setState(() => _erro = null);
    final double latitude;
    final double longitude;
    final List<String> tags;
    try {
      latitude = parseCoordenada(_latitudeController.text, min: -90, max: 90, campo: 'Latitude');
      longitude = parseCoordenada(_longitudeController.text, min: -180, max: 180, campo: 'Longitude');
      tags = parseTags(_tagsController.text);
      validateTags(tags);
      validateTelefone(_telefoneController.text);
      validateBio(_bioController.text);
    } on ProfessionalFormValidationException catch (e) {
      setState(() => _erro = e.message);
      return;
    }
    if (_nomeController.text.trim().isEmpty || _cidadeController.text.trim().isEmpty) {
      setState(() => _erro = 'Nome e cidade são obrigatórios.');
      return;
    }

    setState(() => _salvando = true);
    try {
      if (_editando) {
        await ref.read(adminProfessionalsRepositoryProvider).update(
              widget.profissional!.id,
              nome: _nomeController.text.trim(),
              tags: tags,
              cidade: _cidadeController.text.trim(),
              latitude: latitude,
              longitude: longitude,
              telefone: _telefoneController.text.trim(),
              bio: _bioController.text.trim(),
            );
      } else {
        await ref.read(adminProfessionalsRepositoryProvider).create(
              nome: _nomeController.text.trim(),
              tags: tags,
              cidade: _cidadeController.text.trim(),
              latitude: latitude,
              longitude: longitude,
              telefone: _telefoneController.text.trim(),
              bio: _bioController.text.trim(),
            );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on DioException catch (e) {
      if (mounted) setState(() => _erro = extractServerErrorMessage(e));
    } catch (_) {
      if (mounted) setState(() => _erro = 'Não foi possível salvar. Tente novamente.');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_editando ? 'Editar profissional' : 'Novo profissional')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(controller: _nomeController, decoration: const InputDecoration(labelText: 'Nome')),
          TextField(
            controller: _tagsController,
            decoration: const InputDecoration(labelText: 'Tags (separadas por vírgula)'),
          ),
          TextField(controller: _cidadeController, decoration: const InputDecoration(labelText: 'Cidade')),
          TextField(
            controller: _telefoneController,
            decoration: const InputDecoration(labelText: 'Telefone (+55...)'),
          ),
          TextField(controller: _bioController, decoration: const InputDecoration(labelText: 'Bio'), maxLines: 3),
          TextField(
            controller: _latitudeController,
            decoration: const InputDecoration(labelText: 'Latitude'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          ),
          TextField(
            controller: _longitudeController,
            decoration: const InputDecoration(labelText: 'Longitude'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          ),
          if (_erro != null) ...[
            const SizedBox(height: 12),
            Text(_erro!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 24),
          ElevatedButton(onPressed: _salvando ? null : _salvar, child: const Text('Salvar')),
        ],
      ),
    );
  }
}
