// Arche Axon's own tool for Counterbase licences. Not part of the app.
//
//   dart run tool/licence/licence_tool.dart keygen <folder-outside-the-project>
//   dart run tool/licence/licence_tool.dart issue --key <file> --shop <id>
//       --plan CORE|BUSINESS|ENTERPRISE --due 2026-12-04 [--trial]
//
// `keygen` writes the private key to a file and prints only the public key.
// Put the public key in lib/features/licence/domain/licence_keys.dart. Keep the
// private key file safe and never inside the project folder: anyone who holds
// it can make licences.
import 'dart:convert';
import 'dart:io';

import 'package:axon_pos/features/licence/domain/licence_codec.dart';
import 'package:cryptography/cryptography.dart';

String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

bool _insideGitRepo(Directory dir) {
  var current = dir.absolute;
  while (true) {
    if (Directory('${current.path}${Platform.pathSeparator}.git').existsSync()) {
      return true;
    }
    final parent = current.parent;
    if (parent.path == current.path) return false;
    current = parent;
  }
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Use "keygen <folder>" or "issue ..." (see the top of this file).');
    exit(64);
  }

  switch (args.first) {
    case 'keygen':
      await _keygen(args.skip(1).toList());
    case 'issue':
      await _issue(args.skip(1).toList());
    default:
      stderr.writeln('Unknown command: ${args.first}');
      exit(64);
  }
}

Future<void> _keygen(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('Usage: keygen <folder-outside-the-project>');
    exit(64);
  }
  final dir = Directory(args.single);
  if (_insideGitRepo(dir)) {
    stderr.writeln(
        'That folder is inside a Git project. Choose a private folder elsewhere so the key is never committed.');
    exit(65);
  }
  dir.createSync(recursive: true);
  final file = File('${dir.path}${Platform.pathSeparator}licence_private.key');
  if (file.existsSync()) {
    stderr.writeln('A key already exists there. Refusing to replace it.');
    exit(65);
  }

  final pair = await Ed25519().newKeyPair();
  final seed = await pair.extractPrivateKeyBytes();
  final pub = await pair.extractPublicKey();
  file.writeAsStringSync(_b64(seed));

  stdout.writeln('Private key saved to: ${file.path}');
  stdout.writeln('Keep it safe. Do not put it in the project or share it.');
  stdout.writeln('');
  stdout.writeln('Public key (put this in licence_keys.dart):');
  stdout.writeln(_b64(pub.bytes));
}

Future<void> _issue(List<String> args) async {
  String? get(String name) {
    final i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final keyPath = get('--key');
  final shop = get('--shop');
  final plan = get('--plan');
  final due = get('--due');
  final trial = args.contains('--trial');
  if (keyPath == null || shop == null || plan == null || due == null) {
    stderr.writeln('Needs --key, --shop, --plan and --due.');
    exit(64);
  }
  final dueAt = DateTime.tryParse(due);
  if (dueAt == null) {
    stderr.writeln('--due must be a date such as 2026-12-04.');
    exit(64);
  }
  if (!const {'CORE', 'BUSINESS', 'ENTERPRISE'}.contains(plan.toUpperCase())) {
    stderr.writeln('--plan must be CORE, BUSINESS or ENTERPRISE.');
    exit(64);
  }

  final seed = base64Url.decode(base64Url.normalize(File(keyPath).readAsStringSync().trim()));
  final pair = await Ed25519().newKeyPairFromSeed(seed);
  final token = await signLicence(
    LicenceClaims(
      shopId: shop,
      plan: plan,
      issuedAt: DateTime.now().toUtc(),
      dueAt: dueAt.toUtc(),
      everPaid: !trial,
    ),
    pair,
  );
  stdout.writeln(token);
}
