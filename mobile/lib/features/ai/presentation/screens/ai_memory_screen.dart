import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/widgets/motion.dart';

const _memoryTypes = ['fact', 'preference', 'customer', 'policy'];
const _memoryTypeLabels = {
  'fact': 'Fact',
  'preference': 'Preference',
  'customer': 'Customer note',
  'policy': 'Policy',
};

/// View, add, and remove shop notes stored in the encrypted local workspace.
/// They are deliberately not included in Axon Gateway requests automatically.
class AiMemoryScreen extends StatefulWidget {
  const AiMemoryScreen({super.key});

  @override
  State<AiMemoryScreen> createState() => _AiMemoryScreenState();
}

class _AiMemoryScreenState extends State<AiMemoryScreen> {
  List<Map<String, dynamic>> _memories = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final memories = await getIt<AppDatabase>().getLocalAiMemories();
      if (!mounted) return;
      setState(() {
        _memories = memories;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      const message = 'Could not load workspace memories from this device.';
      setState(() {
        _error = message;
        _loading = false;
      });
    }
  }

  Future<void> _addMemory() async {
    final result = await showModalBottomSheet<bool>(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _AddMemorySheet(),
    );
    if (result == true) _load();
  }

  Future<void> _deleteMemory(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this note?'),
        content: const Text(
          'This removes the note from this device. Existing backups may still contain it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: DesignColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final removed = _memories.firstWhere((m) => m['id'] == id);
    setState(() => _memories.removeWhere((m) => m['id'] == id));
    try {
      await getIt<AppDatabase>().deleteLocalAiMemory(id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _memories.add(removed));
      showGlassSnackBar(
        context,
        'Could not remove that memory — please try again.',
        icon: Icons.error_outline_rounded,
        color: DesignColors.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: const BrandedAppBar(title: 'Workspace Memory'),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(isDark),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addMemory,
        backgroundColor: DesignColors.accent,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add memory'),
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          EmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Something went wrong',
            subtitle: _error,
            iconColor: DesignColors.error,
            actionLabel: 'Retry',
            onAction: _load,
          ),
        ],
      );
    }
    if (_memories.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          _privacyNote(isDark),
          const SizedBox(height: 80),
          const EmptyState(
            icon: Icons.psychology_alt_outlined,
            title: 'No memories yet',
            subtitle:
                'Keep useful shop notes in this encrypted workspace. They stay '
                'on this device and are not sent to Axon AI automatically.',
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: _memories.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) return _privacyNote(isDark);
        final memory = _memories[index - 1];
        // First-mount entrance only: stable key per memory so pull-to-
        // refresh never replays the choreography.
        return StaggeredItem(
          itemKey: 'memory-${memory['id']}',
          index: index,
          child: _MemoryCard(
            memory: memory,
            isDark: isDark,
            onDelete: () => _deleteMemory(memory['id'] as String),
          ),
        );
      },
    );
  }

  Widget _privacyNote(bool isDark) => Container(
        margin: const EdgeInsets.only(bottom: DesignSpacing.md),
        padding: const EdgeInsets.all(DesignSpacing.md),
        decoration: BoxDecoration(
          color: (isDark ? DesignColors.darkSurfaceElevated : Colors.white),
          borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
          border: Border.all(
            color:
                isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder,
          ),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_outline_rounded,
                size: 19, color: DesignColors.accent),
            SizedBox(width: DesignSpacing.sm),
            Expanded(
              child: Text(
                'Saved in this encrypted workspace on this device; it does not '
                'sync across installs. Notes are not added to Axon AI requests '
                'automatically. Axon AI will not recall them unless you include '
                'one in chat. Encrypted shop backups include these notes.',
              ),
            ),
          ],
        ),
      );
}

class _MemoryCard extends StatelessWidget {
  final Map<String, dynamic> memory;
  final bool isDark;
  final VoidCallback onDelete;

  const _MemoryCard({
    required this.memory,
    required this.isDark,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final type = (memory['type'] ?? 'fact').toString();
    final title = (memory['title'] ?? '').toString();
    final content = (memory['content'] ?? '').toString();
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final bodyColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;
    final border =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;

    return Container(
      margin: const EdgeInsets.only(bottom: DesignSpacing.sm + 2),
      padding: const EdgeInsets.all(DesignSpacing.lg - 2),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg - 2),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: DesignSpacing.sm, vertical: 3),
                      decoration: BoxDecoration(
                        color: DesignColors.accent.withValues(alpha: 0.12),
                        borderRadius:
                            BorderRadius.circular(DesignSpacing.radiusSm - 2),
                      ),
                      child: Text(
                        _memoryTypeLabels[type] ?? type,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: DesignColors.accent,
                        ),
                      ),
                    ),
                  ],
                ),
                if (title.isNotEmpty) ...[
                  const SizedBox(height: DesignSpacing.sm),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: titleColor,
                    ),
                  ),
                ],
                const SizedBox(height: DesignSpacing.xs),
                Text(
                  content,
                  style: TextStyle(fontSize: 13, color: bodyColor, height: 1.4),
                ),
              ],
            ),
          ),
          // >=44px tap target for delete.
          IconButton(
            tooltip: 'Remove',
            constraints: const BoxConstraints(
                minWidth: DesignSpacing.xl + 24,
                minHeight: DesignSpacing.xl + 24),
            padding: EdgeInsets.zero,
            icon: Icon(Icons.delete_outline_rounded,
                size: 20,
                color: isDark
                    ? DesignColors.darkTextTertiary
                    : DesignColors.textTertiary),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _AddMemorySheet extends StatefulWidget {
  const _AddMemorySheet();

  @override
  State<_AddMemorySheet> createState() => _AddMemorySheetState();
}

class _AddMemorySheetState extends State<_AddMemorySheet> {
  final _contentController = TextEditingController();
  final _titleController = TextEditingController();
  String _type = 'fact';
  bool _saving = false;

  @override
  void dispose() {
    _contentController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final content = _contentController.text.trim();
    if (content.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      await getIt<AppDatabase>().addLocalAiMemory(
        content: content,
        type: _type,
        title: _titleController.text.trim().isEmpty
            ? null
            : _titleController.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        showGlassSnackBar(
          context,
          'Could not save that memory — please try again.',
          icon: Icons.error_outline_rounded,
          color: DesignColors.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        // Keyboard-safe: cap the sheet height and scroll the form instead of
        // overflowing when the keyboard is up.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        decoration: BoxDecoration(
          color: isDark ? DesignColors.darkSurface : Colors.white,
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(DesignSpacing.radiusXl)),
        ),
        child: SingleChildScrollView(
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: DesignSpacing.lg),
                    decoration: BoxDecoration(
                      color: isDark
                          ? DesignColors.darkBorder
                          : DesignColors.surfaceBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'Add a memory',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? DesignColors.darkTextPrimary
                        : DesignColors.textPrimary,
                  ),
                ),
                const SizedBox(height: DesignSpacing.lg),
                Wrap(
                  spacing: DesignSpacing.sm,
                  runSpacing: DesignSpacing.sm,
                  children: _memoryTypes.map((type) {
                    final selected = _type == type;
                    // Full-height (>=44px) tap target + ink ripple.
                    return ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: DesignSpacing.xl + 24,
                      ),
                      child: ChoiceChip(
                        label: Text(_memoryTypeLabels[type] ?? type),
                        selected: selected,
                        onSelected: (_) => setState(() => _type = type),
                        selectedColor:
                            DesignColors.accent.withValues(alpha: 0.15),
                        labelStyle: TextStyle(
                          color: selected ? DesignColors.accent : null,
                          fontWeight:
                              selected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: DesignSpacing.md),
                TextField(
                  controller: _titleController,
                  maxLength: 60,
                  decoration: const InputDecoration(
                    labelText: 'Short title (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: DesignSpacing.sm),
                TextField(
                  controller: _contentController,
                  maxLines: 4,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: 'What should this workspace remember?',
                    hintText:
                        'e.g. "We give a 5% discount to customers who buy 3+ crates"',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: DesignSpacing.md),
                // >=44px tap target.
                SizedBox(
                  width: double.infinity,
                  height: DesignSpacing.xl + 24,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: DesignColors.accent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                          vertical: DesignSpacing.lg - 2),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
