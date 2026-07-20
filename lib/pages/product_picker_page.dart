import 'package:flutter/material.dart';

import '../models/product_preset.dart';

/// Full-screen product picker with a search box and an A–Z jump strip
/// along the right edge. Returns the selected [ProductPreset] via
/// Navigator.pop, or null if the cashier backs out without choosing one.
class ProductPickerPage extends StatefulWidget {
  final List<ProductPreset> products;
  final String currencySymbol;

  const ProductPickerPage({
    super.key,
    required this.products,
    required this.currencySymbol,
  });

  @override
  State<ProductPickerPage> createState() => _ProductPickerPageState();
}

class _ProductPickerPageState extends State<ProductPickerPage> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  late List<ProductPreset> _filtered;
  final Map<String, double> _letterOffsets = {};

  static const double _headerHeight = 36;
  static const double _itemHeight = 72;

  @override
  void initState() {
    super.initState();
    _filtered = widget.products;
    _searchController.addListener(_onSearchChanged);
    _computeOffsets();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filtered = query.isEmpty
          ? widget.products
          : widget.products
              .where((p) => p.name.toLowerCase().contains(query))
              .toList();
      _computeOffsets();
    });
  }

  String _letterFor(ProductPreset product) {
    final trimmed = product.name.trim();
    if (trimmed.isEmpty) return '#';
    final firstChar = trimmed[0].toUpperCase();
    return RegExp(r'[A-Z]').hasMatch(firstChar) ? firstChar : '#';
  }

  void _computeOffsets() {
    _letterOffsets.clear();
    double runningOffset = 0;
    String? lastLetter;

    for (final product in _filtered) {
      final letter = _letterFor(product);
      if (letter != lastLetter) {
        _letterOffsets[letter] = runningOffset;
        runningOffset += _headerHeight;
        lastLetter = letter;
      }
      runningOffset += _itemHeight;
    }
  }

  List<String> get _availableLetters => _letterOffsets.keys.toList();

  void _jumpToLetter(String letter) {
    final offset = _letterOffsets[letter];
    if (offset == null) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    _scrollController.animateTo(
      offset.clamp(0, maxScroll),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    const alphabet = [
      'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
      'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '#',
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Product'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search products...',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => _searchController.clear(),
                        )
                      : null,
                ),
              ),
            ),
            Expanded(
              child: _filtered.isEmpty
                  ? const Center(child: Text('No products found.'))
                  : Stack(
                      children: [
                        ListView.builder(
                          controller: _scrollController,
                          itemCount: _buildFlatList().length,
                          itemBuilder: (context, index) {
                            final entry = _buildFlatList()[index];
                            if (entry is String) {
                              return Container(
                                height: _headerHeight,
                                width: double.infinity,
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Text(
                                  entry,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                  ),
                                ),
                              );
                            }
                            final product = entry as ProductPreset;
                            return SizedBox(
                              height: _itemHeight,
                              child: ListTile(
                                title: Text(product.name),
                                subtitle: Text(
                                  '${widget.currencySymbol}${product.price.toStringAsFixed(2)}',
                                ),
                                onTap: () =>
                                    Navigator.of(context).pop(product),
                              ),
                            );
                          },
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          bottom: 0,
                          child: _AlphabetStrip(
                            letters: alphabet,
                            availableLetters: _availableLetters.toSet(),
                            onLetterTap: _jumpToLetter,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<dynamic> _buildFlatList() {
    final List<dynamic> flat = [];
    String? lastLetter;
    for (final product in _filtered) {
      final letter = _letterFor(product);
      if (letter != lastLetter) {
        flat.add(letter);
        lastLetter = letter;
      }
      flat.add(product);
    }
    return flat;
  }
}

class _AlphabetStrip extends StatelessWidget {
  final List<String> letters;
  final Set<String> availableLetters;
  final void Function(String letter) onLetterTap;

  const _AlphabetStrip({
    required this.letters,
    required this.availableLetters,
    required this.onLetterTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: letters.map((letter) {
          final isAvailable = availableLetters.contains(letter);
          return GestureDetector(
            onTap: isAvailable ? () => onLetterTap(letter) : null,
            child: Text(
              letter,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isAvailable
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey.shade400,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}