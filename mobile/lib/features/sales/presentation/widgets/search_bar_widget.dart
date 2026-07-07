import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/design_system.dart';
import '../providers/catalog_provider.dart';

class SearchBarWidget extends ConsumerStatefulWidget {
  const SearchBarWidget({super.key});

  @override
  ConsumerState<SearchBarWidget> createState() => _SearchBarWidgetState();
}

class _SearchBarWidgetState extends ConsumerState<SearchBarWidget>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _showClear = false;
  late AnimationController _animController;
  late Animation<double> _iconTween;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: DesignAnimation.fast,
      vsync: this,
    );
    _iconTween = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: DesignAnimation.smooth),
    );
    _controller.addListener(() {
      final hasText = _controller.text.isNotEmpty;
      if (_showClear != hasText) {
        setState(() => _showClear = hasText);
        if (hasText) {
          _animController.forward();
        } else {
          _animController.reverse();
        }
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        borderRadius: 14,
        blur: 8,
        tint: isDark ? DesignColors.glassDark : DesignColors.glassWhite,
        borderColor: isDark
            ? DesignColors.glassDarkBorder
            : DesignColors.surfaceBorder.withValues(alpha:0.6),
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          decoration: InputDecoration(
            hintText: 'Search products...',
            hintStyle: TextStyle(
              color: isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary,
              fontWeight: FontWeight.w400,
            ),
            prefixIcon: AnimatedBuilder(
              animation: _iconTween,
              builder: (context, child) => Icon(
                _showClear ? Icons.search_rounded : Icons.search_rounded,
                color: _showClear
                    ? DesignColors.brand
                    : (isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary),
                size: 20,
              ),
            ),
            suffixIcon: _showClear
                ? IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    style: IconButton.styleFrom(
                      backgroundColor: DesignColors.error.withValues(alpha:0.1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () {
                      _controller.clear();
                      ref.read(searchQueryProvider.notifier).state = '';
                      _focusNode.unfocus();
                    },
                  )
                : null,
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          onChanged: (value) {
            ref.read(searchQueryProvider.notifier).state = value;
          },
          textInputAction: TextInputAction.search,
        ),
      ),
    );
  }
}

class SearchSuggestions extends ConsumerWidget {
  const SearchSuggestions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(searchQueryProvider);

    if (query.isEmpty) {
      return const SizedBox.shrink();
    }

    final productsAsync = ref.watch(productsProvider);

    return productsAsync.when(
      data: (products) {
        final suggestions = products
            .where(
                (p) => (p['name'] as String).toLowerCase().contains(query.toLowerCase()))
            .take(5)
            .toList();

        if (suggestions.isEmpty) {
          return const SizedBox.shrink();
        }

        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: isDark ? DesignColors.darkSurface : Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha:isDark ? 0.3 : 0.08),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: suggestions.map((product) => ListTile(
              leading: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: DesignColors.brand.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.search_rounded, size: 18, color: DesignColors.brand),
              ),
              title: Text(
                product['name'] as String,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              dense: true,
              onTap: () {
                ref.read(searchQueryProvider.notifier).state = product['name'] as String;
              },
            )).toList(),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
