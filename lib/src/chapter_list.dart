import 'package:flutter/material.dart';

import 'controller.dart';
import 'models.dart';
import 'translation_choices.dart';

class ChapterList extends StatelessWidget {
  const ChapterList({super.key, required this.controller});

  final DownloadController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
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
                      : (_) => c.selectAll(count != keys.length, volume: row),
                ),
                onTap: () => c.toggleVolumeExpanded(row),
                trailing: IconButton(
                  key: ValueKey('volume-expansion:$row'),
                  tooltip: collapsed
                      ? 'Розгорнути том $row'
                      : 'Згорнути том $row',
                  icon: Icon(collapsed ? Icons.expand_more : Icons.expand_less),
                  onPressed: () => c.toggleVolumeExpanded(row),
                ),
              ),
              if (!collapsed && branches != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(40, 0, 20, 12),
                  child: TranslationChoices(
                    key: ValueKey('volume-translation:$row'),
                    label: 'Переклад тому',
                    choices: {
                      for (final id in branches) id: names[id] ?? 'Гілка $id',
                    },
                    value: c.selectedVolumeBranch(row),
                    onChanged: c.busy
                        ? null
                        : (value) => c.setVolumeBranch(row, value),
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
                  : (value) => c.toggle(ch, value ?? false),
            ),
            if (!c.volumeBranchChoices.containsKey(ch.volume))
              Padding(
                padding: const EdgeInsets.fromLTRB(56, 0, 20, 12),
                child: TranslationChoices(
                  key: ValueKey('chapter-translation:${ch.key}'),
                  label: 'Переклад глави',
                  choices: {
                    for (final id in c.novel!.chapterChoices[ch.key]!.keys)
                      id: names[id] ?? 'Гілка $id',
                  },
                  value: selection.branch.id,
                  onChanged: c.busy
                      ? null
                      : (value) => c.setChapterBranch(ch.key, value),
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
