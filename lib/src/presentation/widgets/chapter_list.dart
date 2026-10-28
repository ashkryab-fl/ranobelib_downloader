import 'package:flutter/material.dart';

import '../cubit/download_cubit.dart';
import '../cubit/download_state.dart';
import '../../domain/models.dart';
import 'translation_choices.dart';

class ChapterList extends StatelessWidget {
  const ChapterList({super.key, required this.controller, required this.state});

  final DownloadCubit controller;
  final DownloadState state;

  @override
  Widget build(BuildContext context) {
    final c = state;
    final names = c.novel?.branchNames ?? {};
    return SliverList.builder(
      itemCount: c.chapterRows.length,
      itemBuilder: (context, index) {
        final row = c.chapterRows[index];
        if (row is String) {
          final keys = c.volumeKeys[row]!;
          final count = keys.where(c.selected.contains).length;
          final branches = c.volumeBranchChoices[row];
          final collapsed = c.collapsedVolumes.contains(row);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                key: ValueKey('volume-header:$row'),
                tileColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
                title: Text(
                  'Том $row',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                subtitle: Text('$count / ${keys.length} глав'),
                leading: Checkbox(
                  key: ValueKey('volume-selection:$row'),
                  tristate: true,
                  value: count == 0
                      ? false
                      : count == keys.length
                      ? true
                      : null,
                  onChanged: c.busy
                      ? null
                      : (_) => controller.selectAll(
                          count != keys.length,
                          volume: row,
                        ),
                ),
                onTap: () => controller.toggleVolumeExpanded(row),
                trailing: IconButton(
                  key: ValueKey('volume-expansion:$row'),
                  tooltip: collapsed
                      ? 'Развернуть том $row'
                      : 'Свернуть том $row',
                  icon: Icon(collapsed ? Icons.expand_more : Icons.expand_less),
                  onPressed: () => controller.toggleVolumeExpanded(row),
                ),
              ),
              if (!collapsed && branches != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(40, 0, 20, 12),
                  child: TranslationChoices(
                    key: ValueKey('volume-translation:$row'),
                    label: 'Перевод тома',
                    choices: {
                      for (final id in branches) id: names[id] ?? 'Ветка $id',
                    },
                    value: c.selectedVolumeBranch(row),
                    onChanged: c.busy
                        ? null
                        : (value) => controller.setVolumeBranch(row, value),
                  ),
                ),
            ],
          );
        }
        final selection = row as ChapterSelection;
        final ch = selection.chapter;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CheckboxListTile(
              dense: true,
              title: Text(ch.title),
              value: c.selected.contains(ch.key),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: const EdgeInsets.fromLTRB(32, 0, 20, 0),
              onChanged: c.busy
                  ? null
                  : (value) => controller.toggle(ch, value ?? false),
            ),
            if (!c.volumeBranchChoices.containsKey(ch.volume))
              Padding(
                padding: const EdgeInsets.fromLTRB(56, 0, 20, 12),
                child: TranslationChoices(
                  key: ValueKey('chapter-translation:${ch.key}'),
                  label: 'Перевод главы',
                  choices: {
                    for (final id in c.novel!.chapterChoices[ch.key]!.keys)
                      id: names[id] ?? 'Ветка $id',
                  },
                  value: selection.branch.id,
                  onChanged: c.busy
                      ? null
                      : (value) => controller.setChapterBranch(ch.key, value),
                ),
              ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Divider(height: 16),
            ),
          ],
        );
      },
    );
  }
}
