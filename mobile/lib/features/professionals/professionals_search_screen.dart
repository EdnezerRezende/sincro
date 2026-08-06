import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'location_service.dart';
import 'professional.dart';
import 'professional_detail_screen.dart';
import 'professionals_providers.dart';

String mensagemPermissao(LocationPermissionResult resultado) {
  switch (resultado) {
    case LocationPermissionResult.granted:
      return '';
    case LocationPermissionResult.denied:
      return 'Precisamos da sua localização para buscar profissionais próximos. Você pode tentar novamente quando quiser.';
    case LocationPermissionResult.deniedForever:
      return 'A permissão de localização foi negada permanentemente. Abra as configurações do app para conceder.';
    case LocationPermissionResult.serviceDisabled:
      return 'Ative o serviço de localização do seu aparelho para buscar profissionais próximos.';
  }
}

class ProfessionalsSearchScreen extends ConsumerStatefulWidget {
  const ProfessionalsSearchScreen({super.key});

  @override
  ConsumerState<ProfessionalsSearchScreen> createState() => _ProfessionalsSearchScreenState();
}

class _ProfessionalsSearchScreenState extends ConsumerState<ProfessionalsSearchScreen> {
  double? _lat;
  double? _lng;
  LocationPermissionResult? _permissao;
  List<Professional>? _resultados;
  final Set<String> _tagsSelecionadas = {};
  bool _carregando = true;
  bool _erro = false;

  @override
  void initState() {
    super.initState();
    _iniciarBusca();
  }

  Future<void> _iniciarBusca() async {
    setState(() {
      _carregando = true;
      _erro = false;
    });
    try {
      final permissao = await ref.read(locationServiceProvider).solicitarPermissao();
      if (!mounted) return;
      setState(() => _permissao = permissao);
      if (permissao != LocationPermissionResult.granted) {
        setState(() => _carregando = false);
        return;
      }
      final posicao = await ref.read(locationServiceProvider).obterPosicaoAtual();
      _lat = posicao.latitude;
      _lng = posicao.longitude;
      await _buscar();
    } catch (_) {
      if (mounted) {
        setState(() {
          _erro = true;
          _carregando = false;
        });
      }
    }
  }

  Future<void> _buscar() async {
    if (_lat == null || _lng == null) return;
    setState(() {
      _carregando = true;
      _erro = false;
    });
    try {
      final resultados = await ref.read(professionalsRepositoryProvider).search(
            lat: _lat!,
            lng: _lng!,
            tags: _tagsSelecionadas.toList(),
          );
      if (mounted) {
        setState(() {
          _resultados = resultados;
          _carregando = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _erro = true;
          _carregando = false;
        });
      }
    }
  }

  void _alternarTag(String tag) {
    setState(() {
      if (_tagsSelecionadas.contains(tag)) {
        _tagsSelecionadas.remove(tag);
      } else {
        _tagsSelecionadas.add(tag);
      }
    });
    _buscar();
  }

  @override
  Widget build(BuildContext context) {
    final tagsAsync = ref.watch(professionalTagsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Encontrar profissional')),
      body: _buildBody(tagsAsync),
    );
  }

  Widget _buildBody(AsyncValue<List<String>> tagsAsync) {
    if (_carregando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_permissao != null && _permissao != LocationPermissionResult.granted) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(mensagemPermissao(_permissao!), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _iniciarBusca, child: const Text('Tentar novamente')),
            ],
          ),
        ),
      );
    }
    if (_erro) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Não foi possível buscar agora.', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _iniciarBusca, child: const Text('Tentar novamente')),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        tagsAsync.when(
          data: (tags) => tags.isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 8,
                    children: tags.map((tag) {
                      return FilterChip(
                        label: Text(tag),
                        selected: _tagsSelecionadas.contains(tag),
                        onSelected: (_) => _alternarTag(tag),
                      );
                    }).toList(),
                  ),
                ),
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        ),
        Expanded(
          child: (_resultados == null || _resultados!.isEmpty)
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Nenhum profissional encontrado por aqui ainda.', textAlign: TextAlign.center),
                  ),
                )
              : ListView.builder(
                  itemCount: _resultados!.length,
                  itemBuilder: (context, index) {
                    final profissional = _resultados![index];
                    return ListTile(
                      title: Text(profissional.nome),
                      subtitle: Text('${profissional.tags.join(', ')} · ${profissional.cidade}'),
                      trailing: Text('${profissional.distanciaKm?.toStringAsFixed(1)} km'),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => ProfessionalDetailScreen(profissional: profissional)),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
