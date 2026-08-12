import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'grounding_card.dart';
import 'grounding_cards_providers.dart';

class GroundingCardDetailScreen extends ConsumerStatefulWidget {
  const GroundingCardDetailScreen({super.key, required this.card, required this.favoritadoInicial});

  final GroundingCard card;
  final bool favoritadoInicial;

  @override
  ConsumerState<GroundingCardDetailScreen> createState() => _GroundingCardDetailScreenState();
}

class _GroundingCardDetailScreenState extends ConsumerState<GroundingCardDetailScreen> {
  late bool _favoritado;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _favoritado = widget.favoritadoInicial;
  }

  Future<void> _alternarFavorito() async {
    final novoEstado = !_favoritado;
    setState(() {
      _favoritado = novoEstado;
      _salvando = true;
    });
    try {
      if (novoEstado) {
        await ref.read(groundingCardsRepositoryProvider).favoritar(widget.card.id);
      } else {
        await ref.read(groundingCardsRepositoryProvider).desfavoritar(widget.card.id);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _favoritado = !novoEstado);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível salvar. Tente novamente.')),
        );
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.card.titulo),
        actions: [
          IconButton(
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
              child: Icon(
                _favoritado ? Icons.favorite : Icons.favorite_border,
                key: ValueKey(_favoritado),
              ),
            ),
            tooltip: _favoritado ? 'Remover dos favoritos' : 'Favoritar',
            onPressed: _salvando ? null : _alternarFavorito,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Chip(label: Text(rotuloCategoria(widget.card.categoria))),
            ),
            const SizedBox(height: 16),
            Text(widget.card.conteudo),
          ],
        ),
      ),
    );
  }
}
