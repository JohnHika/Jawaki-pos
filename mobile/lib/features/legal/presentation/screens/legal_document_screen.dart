import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/legal/policy_catalog.dart';

class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({super.key, this.documentSlug});

  final String? documentSlug;

  @override
  Widget build(BuildContext context) {
    final document = documentSlug == null ? null : policyDocument(documentSlug!);
    return Scaffold(
      appBar: AppBar(title: Text(document?.title ?? 'Legal & policies')),
      body: document == null
          ? const _PolicyIndex()
          : _PolicyBody(document: document),
    );
  }
}

class _PolicyIndex extends StatelessWidget {
  const _PolicyIndex();

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Counterbase policies',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(
            'Read the current terms for your workspace, billing, data, and payments.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          for (final policy in kPolicyDocuments)
            Card(
              child: ListTile(
                title: Text(policy.title),
                subtitle: Text(policy.summary),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/legal/${policy.slug}'),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            'Effective $kPolicyEffectiveDate · $kPolicyContactEmail',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
}

class _PolicyBody extends StatelessWidget {
  const _PolicyBody({required this.document});

  final PolicyDocument document;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
        children: [
          Text(document.summary, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Version ${document.version} · Effective $kPolicyEffectiveDate',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          for (final section in document.sections) ...[
            Text(section.title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    )),
            const SizedBox(height: 6),
            Text(section.body,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      height: 1.45,
                    )),
            const SizedBox(height: 18),
          ],
          TextButton.icon(
            onPressed: () => context.push('/legal'),
            icon: const Icon(Icons.article_outlined),
            label: const Text('View all policies'),
          ),
        ],
      );
}
