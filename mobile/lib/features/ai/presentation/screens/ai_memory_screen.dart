import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/theme/design_system.dart';

const _memoryTypes = ['fact', 'preference', 'customer', 'policy'];
const _memoryTypeLabels = {
  'fact': 'Fact',
  'preference': 'Preference',
  'customer': 'Customer note',
  'policy': 'Policy',
};

/// View, add, and remove the AI's durable shop memories — the things it
/// recalls across sessions (owner preferences, policies, customer notes)
/// without being told again each time. Tenant-wide and shared by every
/// staff member, same as the AI chat thread itself. Backend only supports
/// create/list/delete (no edit-in-place), so this screen doesn't either.
class AiMemoryScreen extends StatefulWidget {
  const AiMemoryScreen({super.key});

  @override
  State<AiMemoryScreen> createState() => _AiMemoryScreenState();
}

class _AiMemoryScreenState extends State<AiMemoryScreen> {
  List<Map<String, dynamic>> _memories = [];
  bool _loading = true;
  String? _error;

  String get _branchId => getIt<AuthService>().branchId ?? '';

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
      final memories = await getIt<ApiClient>().getAiMemories(branchId: _branchId);
      if (!mounted) return;
      setState(() {
        _memories = memories;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      String message;
      if (e is DioException) {
        if (e.response?.statusCode == 402) {
          message = 'AI subscription required. Subscribe to use AI memory.';
        } else if (e.response?.statusCode == 400) {
          message = 'Could not identify your branch. Try logging in again.';
        } else {
          message = 'Could not load memories. Check your connection and try again.';
        }
      } else {
        message = 'Could not load memories. Check your connection and try again.';
      }
      setState(() {
        _error = message;
        _loading = false;
      });
    }
  }

  Future<void> _addMemory() async {
    final result = await showModalBottomSheet<bool>(
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
        title: const Text('Remove this memory?'),
        content: const Text('The AI will no longer recall this.'),
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
      await getIt<ApiClient>().deleteAiMemory(id: id, branchId: _branchId);
    } catch (e) {
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
      appBar: const BrandedAppBar(title: 'AI Memory'),
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
        children: const [
          SizedBox(height: 80),
          EmptyState(
            icon: Icons.psychology_alt_outlined,
            title: 'No memories yet',
            subtitle:
                'Add things the AI should always remember — a policy, a customer\'s '
                'preference, a fact about your shop. It also picks these up '
                'automatically when you tell it something in chat.',
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: _memories.length,
      itemBuilder: (context, index) {
        final memory = _memories[index];
        return _MemoryCard(
          memory: memory,
          isDark: isDark,
          onDelete: () => _deleteMemory(memory['id'] as String),
        );
      },
    );
  }
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
    final border = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
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
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: DesignColors.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
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
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: titleColor,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  content,
                  style: TextStyle(fontSize: 13, color: bodyColor, height: 1.4),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline_rounded,
                size: 20,
                color: isDark
                    ? DesignColors.darkTextTertiary
                    : DesignColors.textTertiary),
            onPressed: onDelete,
            tooltip: 'Remove',
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
      await getIt<ApiClient>().saveAiMemory(
        content: content,
        branchId: getIt<AuthService>().branchId ?? '',
        type: _type,
        title: _titleController.text.trim().isEmpty
            ? null
            : _titleController.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
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
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        decoration: BoxDecoration(
          color: isDark ? DesignColors.darkSurface : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Add a memory',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: _memoryTypes.map((type) {
                final selected = _type == type;
                return ChoiceChip(
                  label: Text(_memoryTypeLabels[type] ?? type),
                  selected: selected,
                  onSelected: (_) => setState(() => _type = type),
                  selectedColor: DesignColors.accent.withValues(alpha: 0.15),
                  labelStyle: TextStyle(
                    color: selected ? DesignColors.accent : null,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _titleController,
              maxLength: 60,
              decoration: const InputDecoration(
                labelText: 'Short title (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _contentController,
              maxLines: 4,
              maxLength: 2000,
              decoration: const InputDecoration(
                labelText: 'What should the AI remember?',
                hintText: 'e.g. "We give a 5% discount to customers who buy 3+ crates"',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: DesignColors.accent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
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
    );
  }
}
