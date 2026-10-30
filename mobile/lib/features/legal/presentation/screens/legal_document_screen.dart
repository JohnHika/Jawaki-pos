import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/legal/policy_catalog.dart';

class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({super.key, this.documentSlug});

  final String? documentSlug;

  @override
  Widget build(BuildContext context) {
    final document = documentSlug == null
        ? null
        : policyDocument(documentSlug!, standalone: true);
    return Scaffold(
      appBar: AppBar(title: Text(document?.title ?? 'Policies & data')),
      body: document == null
          ? documentSlug == null
              ? const _PolicyIndex()
              : const _UnavailablePolicy()
          : _PolicyBody(document: document),
    );
  }
}

class _PolicyIndex extends StatelessWidget {
  const _PolicyIndex();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Standalone app policies',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          'Learn what stays on this device and what is shared when you choose Axon AI.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        for (final policy in kStandalonePolicyDocuments)
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
          'Effective $kStandalonePolicyEffectiveDate · $kPolicyContactEmail',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _UnavailablePolicy extends StatelessWidget {
  const _UnavailablePolicy();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.info_outline_rounded, size: 36),
              const SizedBox(height: 12),
              const Text(
                'That policy does not apply to the standalone app.',
                textAlign: TextAlign.center,
              ),
              TextButton.icon(
                onPressed: () => context.push('/legal'),
                icon: const Icon(Icons.article_outlined),
                label: const Text('View applicable policies'),
              ),
            ],
          ),
        ),
      );
}

class _PolicyBody extends StatelessWidget {
  const _PolicyBody({required this.document});

  final PolicyDocument document;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
        children: [
          Text(document.summary,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Version ${document.version} · Effective $kStandalonePolicyEffectiveDate',
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
