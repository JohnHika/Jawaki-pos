import 'package:flutter/material.dart';

import '../providers/business_layout_provider.dart';
import '../theme/design_system.dart';

/// Lets a merchant add complementary shop types without changing the primary
/// profile's terminology or core checkout defaults.
Future<List<String>?> showBusinessLayoutProfilePicker(
  BuildContext context, {
  required String primaryProfileId,
  Iterable<String> selectedProfileIds = const [],
  int maxProfiles = 3,
}) async {
  final searchController = TextEditingController();
  final validProfiles = businessLayoutAdditionalPresets(
    primaryProfileId,
    selectedProfileIds,
  );
  final selected = validProfiles.map((profile) => profile.id).toSet();
  try {
    return await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? DesignColors.darkSurface
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final query = searchController.text.trim().toLowerCase();
          final profiles = businessLayoutPresets.where((profile) {
            if (profile.id == primaryProfileId || profile.id == 'custom') {
              return false;
            }
            return businessLayoutProfileMatchesSearch(profile, query);
          }).toList(growable: false);
          final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
          return SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * .78,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? DesignColors.darkBorder : Colors.black12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('What else does this shop sell?',
                          style: Theme.of(sheetContext)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 5),
                      Text(
                        'Add up to $maxProfiles more profiles. They bring in useful product details and work areas while your main profile keeps the shop’s wording.',
                        style: Theme.of(sheetContext)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(
                              color: isDark
                                  ? DesignColors.darkTextSecondary
                                  : DesignColors.textSecondary,
                              height: 1.35,
                            ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: searchController,
                        onChanged: (_) => setSheetState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Search shop types',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: query.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear search',
                                  onPressed: () {
                                    searchController.clear();
                                    setSheetState(() {});
                                  },
                                  icon: const Icon(Icons.close_rounded),
                                ),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: profiles.isEmpty
                      ? const Center(child: Text('No shop types match.'))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          itemCount: profiles.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 6),
                          itemBuilder: (context, index) {
                            final profile = profiles[index];
                            final checked = selected.contains(profile.id);
                            final atLimit = selected.length >= maxProfiles;
                            return CheckboxListTile.adaptive(
                              value: checked,
                              activeColor: DesignColors.accent,
                              secondary: CircleAvatar(
                                backgroundColor:
                                    DesignColors.accent.withValues(alpha: .12),
                                child: Icon(profile.icon,
                                    color: DesignColors.accent, size: 20),
                              ),
                              title: Text(profile.name),
                              subtitle: Text(profile.description),
                              controlAffinity: ListTileControlAffinity.trailing,
                              onChanged: !checked && atLimit
                                  ? null
                                  : (value) => setSheetState(() {
                                        if (value == true) {
                                          selected.add(profile.id);
                                        } else {
                                          selected.remove(profile.id);
                                        }
                                      }),
                            );
                          },
                        ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.of(sheetContext)
                            .pop(selected.toList(growable: false)),
                        child: Text(selected.isEmpty
                            ? 'Use primary profile only'
                            : 'Apply ${selected.length} additional ${selected.length == 1 ? 'profile' : 'profiles'}'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  } finally {
    searchController.dispose();
  }
}
