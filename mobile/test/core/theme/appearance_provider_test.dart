import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:axon_pos/core/theme/appearance_provider.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('defaults to normal text and comfortable spacing', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final state = container.read(appearanceProvider);
    expect(state.textSize, AppTextSize.normal);
    expect(state.spacing, AppSpacing.comfortable);
  });

  test('saves a choice and restores it on the next start', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(appearanceProvider.notifier);
    await notifier.setTextSize(AppTextSize.large);
    await notifier.setSpacing(AppSpacing.compact);
    expect(container.read(appearanceProvider).textSize, AppTextSize.large);

    final next = ProviderContainer();
    addTearDown(next.dispose);
    next.read(appearanceProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(next.read(appearanceProvider).textSize, AppTextSize.large);
    expect(next.read(appearanceProvider).spacing, AppSpacing.compact);
    expect(next.read(appearanceProvider).spacing.density,
        VisualDensity.compact);
  });

  test('an unknown saved value falls back to the default', () {
    expect(AppTextSize.parse('huge'), AppTextSize.normal);
    expect(AppSpacing.parse(null), AppSpacing.comfortable);
  });
}
