import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../data/models/change_log.dart';
import '../../providers/providers.dart';
import '../common/async_view.dart';

class ChangeLogScreen extends ConsumerWidget {
  const ChangeLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(changeLogProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Change Log'),
        actions: [
          IconButton(
            tooltip: 'Export CSV',
            icon: const Icon(Icons.download),
            onPressed: () async {
              final list = await ref.read(changeLogProvider.future);
              await _exportCsv(list);
            },
          ),
        ],
      ),
      body: AsyncView<List<ChangeLog>>(
        value: logs,
        data: (list) {
          if (list.isEmpty) {
            return const Center(
                child: Text('No changes recorded yet.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final c = list[i];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(child: Icon(_iconFor(c))),
                  title: Text('${c.action.label} · ${c.entityType}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Entity: ${c.entityId}',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (c.note != null) Text('Note: ${c.note}'),
                      Text(fmtDateTime(c.timestamp),
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                  isThreeLine: c.note != null,
                  onTap: () => _showDetail(context, c),
                ),
              );
            },
          );
        },
      ),
    );
  }

  IconData _iconFor(ChangeLog c) => switch (c.action.name) {
        'delete' => Icons.delete,
        'restore' => Icons.restore,
        'archive' => Icons.archive,
        'unarchive' => Icons.unarchive,
        _ => Icons.edit,
      };

  void _showDetail(BuildContext context, ChangeLog c) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${c.action.label} · ${c.entityType}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Timestamp: ${fmtDateTime(c.timestamp)}'),
              const SizedBox(height: 8),
              Text('Entity ID: ${c.entityId}'),
              if (c.note != null) ...[
                const SizedBox(height: 8),
                Text('Note: ${c.note}'),
              ],
              if (c.originalData != null) ...[
                const SizedBox(height: 12),
                const Text('Original:',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                Text(c.originalData!,
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 11)),
              ],
              if (c.newData != null) ...[
                const SizedBox(height: 12),
                const Text('New:',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                Text(c.newData!,
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 11)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportCsv(List<ChangeLog> list) async {
    final buf = StringBuffer();
    buf.writeln(
        'id,timestamp,entity_type,entity_id,action,note,original_data,new_data');
    for (final c in list) {
      buf.writeln([
        _csv(c.id),
        _csv(c.timestamp.toIso8601String()),
        _csv(c.entityType),
        _csv(c.entityId),
        _csv(c.action.db),
        _csv(c.note ?? ''),
        _csv(c.originalData ?? ''),
        _csv(c.newData ?? ''),
      ].join(','));
    }
    final dir = await getApplicationDocumentsDirectory();
    final stamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final file = File(p.join(dir.path, 'change_log_$stamp.csv'));
    await file.writeAsString(buf.toString());
    await Share.shareXFiles([XFile(file.path)],
        text: 'Bismillah ERP change log');
  }

  String _csv(String s) {
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }
}
