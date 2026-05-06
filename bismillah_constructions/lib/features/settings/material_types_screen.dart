import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/material_type_def.dart';
import '../../providers/providers.dart';
import '../common/async_view.dart';

/// Lets the user manage the categories that appear in the Buy Material
/// transaction form.
///
/// Built-in rows (the original five seeded by the v7 migration) can be
/// renamed but not deleted — historical inventory references their label
/// and we don't want a dropdown that silently drops legacy data. Custom
/// rows the user adds are fully removable.
class MaterialTypesScreen extends ConsumerWidget {
  const MaterialTypesScreen({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _NameDialog(title: 'New material type'),
    );
    if (name == null || name.trim().isEmpty) return;
    try {
      final repo = await ref.read(entityRepoProvider.future);
      await repo.addMaterialType(name);
      bumpLedger(ref);
      messenger.showSnackBar(SnackBar(content: Text('Added "$name".')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _rename(
      BuildContext context, WidgetRef ref, MaterialTypeDef row) async {
    final messenger = ScaffoldMessenger.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (_) =>
          _NameDialog(title: 'Rename type', initial: row.name),
    );
    if (name == null || name.trim().isEmpty || name.trim() == row.name) return;
    final repo = await ref.read(entityRepoProvider.future);
    await repo.renameMaterialType(row.id, name);
    bumpLedger(ref);
    messenger.showSnackBar(SnackBar(content: Text('Renamed to "$name".')));
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, MaterialTypeDef row) async {
    if (row.isBuiltin) return;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${row.name}"?'),
        content: const Text(
            'This removes the option from the Buy Material dropdown. '
            'Past purchases keep the label they were saved with.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    final repo = await ref.read(entityRepoProvider.future);
    await repo.deleteMaterialType(row.id);
    bumpLedger(ref);
    messenger.showSnackBar(SnackBar(content: Text('Deleted "${row.name}".')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typesAsync = ref.watch(materialTypesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Material Types'),
        actions: [
          IconButton.filledTonal(
            tooltip: 'Add type',
            icon: const Icon(Icons.add),
            onPressed: () => _add(context, ref),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: AsyncView<List<MaterialTypeDef>>(
        value: typesAsync,
        data: (rows) {
          if (rows.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                    'No material types yet. Tap + to add one (e.g. "Sand").'),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (_, i) {
              final r = rows[i];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Icon(r.isBuiltin
                        ? Icons.lock_outline
                        : Icons.category_outlined),
                  ),
                  title: Text(r.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(r.isBuiltin
                      ? 'Built-in · cannot be deleted'
                      : 'Custom'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Rename',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _rename(context, ref, r),
                      ),
                      IconButton(
                        tooltip: r.isBuiltin
                            ? 'Built-ins cannot be deleted'
                            : 'Delete',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: r.isBuiltin
                            ? null
                            : () => _delete(context, ref, r),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add type'),
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, this.initial});
  final String title;
  final String? initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Name',
          hintText: 'e.g. Sand, Tiles, Paint',
        ),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
            child: const Text('Save')),
      ],
    );
  }
}
