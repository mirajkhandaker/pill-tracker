import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/prescription.dart';
import '../providers/prescription_providers.dart';
import 'edit_prescription_screen.dart';
import 'prescription_detail_screen.dart';

/// All prescriptions: current ones first, then past (ended) ones.
class PrescriptionsScreen extends ConsumerWidget {
  const PrescriptionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(allPrescriptionsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Prescriptions')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const EditPrescriptionScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New prescription'),
      ),
      body: all.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: OutlinedButton(
            onPressed: () => ref.invalidate(allPrescriptionsProvider),
            child: const Text('Could not load — retry'),
          ),
        ),
        data: (list) {
          if (list.isEmpty) return const _Empty();
          final current = list.where((p) => p.isActive).toList();
          final past = list.where((p) => !p.isActive).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              if (current.isNotEmpty) ...[
                const _Header('Current'),
                for (final p in current) PrescriptionCard(prescription: p),
              ],
              if (past.isNotEmpty) ...[
                const _Header('Past'),
                for (final p in past) PrescriptionCard(prescription: p),
              ],
            ],
          );
        },
      ),
    );
  }
}

class PrescriptionCard extends ConsumerWidget {
  const PrescriptionCard({super.key, required this.prescription});
  final Prescription prescription;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final p = prescription;
    final medicines = ref
        .watch(prescriptionMedicinesProvider(p.id))
        .asData
        ?.value;
    final ongoing = medicines?.where((m) => m.isActive).length;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PrescriptionDetailScreen(prescriptionId: p.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                Icons.receipt_long,
                size: 32,
                color: p.isActive
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.shortTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      p.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (medicines != null)
                      Text(
                        p.isActive
                            ? _count(ongoing!, 'medicine')
                            : 'Ended · ${_count(medicines.length, 'medicine')}',
                        style: theme.textTheme.bodyMedium,
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  static String _count(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 6),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.bold),
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 60),
        Icon(Icons.receipt_long, size: 96, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          'No prescriptions yet',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Add a prescription after each doctor visit to keep its medicines '
          'together. When you get a new one, PillTrack helps you switch over '
          'and keeps the old one in your history.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
      ],
    );
  }
}
