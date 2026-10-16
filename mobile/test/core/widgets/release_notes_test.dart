import 'package:flutter_test/flutter_test.dart';
import 'package:axon_pos/core/widgets/release_notes.dart';

// The exact GitHub release body shown to users after updating to build 2093.
const _ciReleaseBody = '''
## Axon POS Android Update

**Release:** Axon POS 1.0.50
**Internal build:** 2093
**Source:** Dual (Cloudflare R2 + GitHub Releases)

### Download

[Cloudflare R2](https://pub-7f8ac9ce2a8c4e3cb5b1a89e37de7aec.r2.dev/releases/1.0.50/2093/app-release.apk)
[GitHub Release](https://github.com/JohnHika/Jawaki-pos/releases/tag/v1.0.50-2093)

### Update Sources

1. **Cloudflare R2** (Primary): `https://pub-7f8ac9ce2a8c4e3cb5b1a89e37de7aec.r2.dev/android/latest.json`
2. **GitHub Releases** (Secondary): GitHub Releases API

Automated Android build from GitHub Actions.
''';

void main() {
  main2();
  group('parseReleaseNotes', () {
    test('a CI-generated release body yields no user-facing notes', () {
      expect(parseReleaseNotes(_ciReleaseBody), isEmpty);
    });

    test('keeps real changes and strips markdown, links and list markers', () {
      final notes = parseReleaseNotes('''
## What's changed
- **New:** Manual payments need a manager's approval
- Fixes: [receipt search](https://example.com/x) finds phone numbers
3. Improved `Finance` loading speed
### Download
- app-release.apk
''');
      expect(notes.map((n) => n.text), [
        'New: Manual payments need a manager\'s approval',
        'Fixes: receipt search finds phone numbers',
        'Improved Finance loading speed',
      ]);
      expect(notes[0].category, ReleaseCategory.feature);
      expect(notes[1].category, ReleaseCategory.fix);
      expect(notes[2].category, ReleaseCategory.improvement);
    });

    test('drops build metadata sentences but keeps the human one', () {
      final notes = parseReleaseNotes(
          'Axon POS 1.0.50 starts the clean Axon release line. Build 2093 was published from 671a3db on main.');
      expect(notes.map((n) => n.text), ['Axon POS 1.0.50 starts the clean Axon release line.']);
    });

    test('one long change with commas stays one note', () {
      final notes = parseReleaseNotes(
        'Fixes: Report a problem shows its hints and drops a dead link, '
        'checkboxes follow the app theme',
      );
      expect(notes, hasLength(1));
      expect(notes.single.category, ReleaseCategory.fix);
    });

    test('caps the list and ignores blank input', () {
      expect(parseReleaseNotes('   \n '), isEmpty);
      final many = List.generate(20, (i) => '- Fix number $i').join('\n');
      expect(parseReleaseNotes(many).length, 8);
    });
  });

  group('cleanReleaseName', () {
    test('shows the product name once', () {
      expect(cleanReleaseName('Axon POS Android Axon POS 1.0.50', fallback: 'x'),
          'Axon POS 1.0.50');
      expect(cleanReleaseName('Axon POS 1.0.50', fallback: 'x'), 'Axon POS 1.0.50');
    });

    test('falls back when empty', () {
      expect(cleanReleaseName(null, fallback: 'Axon POS 1.0.50'), 'Axon POS 1.0.50');
      expect(cleanReleaseName('  ', fallback: 'Axon POS 1.0.50'), 'Axon POS 1.0.50');
    });
  });
}

// Build 2099/2100's GitHub body: the changes follow the "Update Sources"
// list after a blank line, with no heading of their own.
const _headinglessChangesBody = '''
## Axon POS Android Update

**Release:** Axon POS 1.0.57
**Internal build:** 2100
**Source:** Dual (Cloudflare R2 + GitHub Releases)

### Download
- [Cloudflare R2](https://pub-7f8ac9ce2a8c4e3cb5b1a89e37de7aec.r2.dev/releases/1.0.57/2100/app-release.apk)
- [GitHub Release](https://github.com/JohnHika/Jawaki-pos/releases/tag/v1.0.57-2100)

### Update Sources
1. **Cloudflare R2** (Primary): `https://pub-7f8ac9ce2a8c4e3cb5b1a89e37de7aec.r2.dev/android/latest.json`
2. **GitHub Releases** (Secondary): GitHub Releases API

Fixes: Approving, rejecting and fulfilling a stock request now works
Fixes: An expired sign-in now returns you to the login screen
''';

void main2() {
  test('changes listed after the technical sections are still shown', () {
    final lines = cleanReleaseNoteLines(_headinglessChangesBody);
    expect(lines, [
      'Fixes: Approving, rejecting and fulfilling a stock request now works',
      'Fixes: An expired sign-in now returns you to the login screen',
    ]);
    expect(parseReleaseNotes(_headinglessChangesBody), hasLength(2));
  });
}
