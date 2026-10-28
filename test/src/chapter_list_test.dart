import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ranobeli_downloader/src/presentation/widgets/chapter_list.dart';
import 'package:ranobeli_downloader/src/presentation/cubit/download_cubit.dart';
import 'package:ranobeli_downloader/src/presentation/cubit/download_state.dart';
import 'package:ranobeli_downloader/src/domain/models.dart';
import 'package:ranobeli_downloader/src/presentation/widgets/translation_choices.dart';

Novel translationFixture() => Novel(
  'translations',
  {},
  Chapter.fromResponse([
    for (final (volume, number, branches, name) in [
      ('1', '1', [1, 2], 'Початок'),
      ('1', '1', [3], 'Інша назва'),
      ('1', '2', [3, 2, 1], ''),
      ('2', '1', [1, 2], ''),
      ('2', '2', [2, 3], ''),
      ('3', '1', [9], ''),
    ])
      {
        'volume': volume,
        'number': number,
        'name': name,
        'branches': [
          for (final id in branches)
            {
              'branch_id': id,
              'teams': [
                {
                  'name': id == 9
                      ? List.filled(20, 'Довга назва команди').join(' ')
                      : 'Команда $id',
                },
              ],
            },
        ],
      },
  ]),
);

void main() {
  late DownloadCubit controller;

  setUp(() {
    controller = DownloadCubit()..setNovelForTesting(translationFixture());
  });
  tearDown(() => controller.close());

  test('shares a volume selector only for identical available branch sets', () {
    expect(controller.state.chapters, hasLength(5));
    expect(controller.state.volumeBranchChoices['1'], ['1', '2', '3']);
    expect(controller.state.volumeBranchChoices.containsKey('2'), isFalse);
    expect(controller.state.volumeBranchChoices['3'], ['9']);
  });

  test('chapter changes retain checks and the matching variant metadata', () {
    controller.selectAll(false, volume: '1');
    final selected = {...controller.state.selected};
    final otherChapters = controller.state.chapters.skip(1).toList();
    controller.setChapterBranch('1/1', '3');

    expect(controller.state.chapters.first.branch.id, '3');
    expect(controller.state.chapters.first.chapter.name, 'Інша назва');
    expect(controller.state.chapters.skip(1), otherChapters);
    expect(controller.state.selected, selected);
    expect(controller.state.selectedVolumeBranch('1'), isNull);
    expect(
      controller.state.chapterRows
          .whereType<ChapterSelection>()
          .first
          .branch
          .id,
      '3',
    );

    controller.setChapterBranch('1/1', 'missing');
    expect(controller.state.chapters.first.branch.id, '3');
  });

  test(
    'volume changes include unchecked chapters and leave other volumes alone',
    () {
      controller.toggle(controller.state.chapters.first.chapter, false);
      final selected = {...controller.state.selected};
      final otherVolumes = controller.state.chapters.skip(2).toList();
      controller.setVolumeBranch('1', '3');

      expect(controller.state.chapters.take(2).map((s) => s.branch.id), [
        '3',
        '3',
      ]);
      expect(controller.state.selectedVolumeBranch('1'), '3');
      expect(controller.state.chapters.skip(2), otherVolumes);
      expect(controller.state.selected, selected);

      controller.setVolumeBranch('2', '1');
      expect(controller.state.chapters.skip(2), otherVolumes);
    },
  );

  test('local selectors cannot change a download in progress', () async {
    final before = controller.state.chapters;
    await controller.run(() async {
      controller.setChapterBranch('2/1', '2');
      controller.setVolumeBranch('1', '3');
      expect(controller.state.chapters, equals(before));
    });
  });

  test(
    'global selection switches available translations without hiding chapters',
    () {
      controller.setVolumeBranch('1', '3');
      controller.setBranch('2');
      expect(controller.state.chapters.map((s) => s.branch.id), [
        '2',
        '2',
        '2',
        '2',
        '9',
      ]);
      expect(controller.state.volumeKeys.keys, ['1', '2', '3']);
      controller.setBranch(null);
      expect(controller.state.chapters, hasLength(5));
      expect(controller.state.selectedVolumeBranch('1'), '1');
    },
  );

  test(
    'global selection preserves current alternatives, checks and collapsed volumes',
    () {
      controller.setChapterBranch('2/2', '3');
      controller.toggle(controller.state.chapters.first.chapter, false);
      controller.toggleVolumeExpanded('1');
      final keys = controller.state.chapters.map((s) => s.chapter.key).toList();
      final selected = {...controller.state.selected};

      controller.setBranch('1');

      expect(controller.state.chapters.map((s) => s.chapter.key), keys);
      expect(controller.state.chapters.map((s) => s.branch.id), [
        '1',
        '1',
        '1',
        '3',
        '9',
      ]);
      expect(controller.state.selected, selected);
      expect(controller.state.collapsedVolumes, {'1'});

      controller.setBranch('9');
      expect(controller.state.chapters.map((s) => s.branch.id), [
        '1',
        '1',
        '1',
        '3',
        '9',
      ]);
      controller.setBranch('2');
      expect(controller.state.chapters.map((s) => s.branch.id), [
        '2',
        '2',
        '2',
        '2',
        '9',
      ]);
      expect(controller.state.selected, selected);

      controller.setBranch(null);
      expect(controller.state.chapters.map((s) => s.chapter.key), keys);
      expect(controller.state.selected, selected);
      expect(controller.state.collapsedVolumes, {'1'});

      controller.selectAll(false);
      controller.setBranch('1');
      expect(controller.state.selected, isEmpty);
    },
  );

  Future<void> showChapters(WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocBuilder<DownloadCubit, DownloadState>(
            bloc: controller,
            builder: (_, _) => CustomScrollView(
              slivers: [
                ChapterList(controller: controller, state: controller.state),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Finder group(String key) => find.byKey(ValueKey(key));

  Finder choice(String groupKey, String branch) => find.descendant(
    of: group(groupKey),
    matching: find.byKey(ValueKey(branch)),
  );

  void expectChoice(String groupKey, String branch) {
    final radios = find.descendant(
      of: group(groupKey),
      matching: find.byType(Radio<String>),
    );
    final states = radios.evaluate().map((e) {
      final radio = e.widget as Radio<String>;
      return RadioGroup.maybeOf<String>(e)!.groupValue == radio.value;
    });
    expect(states.where((checked) => checked), hasLength(1));
    final tile = choice(groupKey, branch).evaluate().single;
    expect(RadioGroup.maybeOf<String>(tile)!.groupValue, branch);
  }

  testWidgets(
    'translation radio buttons switch with one tap and stay exclusive',
    (tester) async {
      await showChapters(tester);
      expect(group('volume-translation:1'), findsOneWidget);
      expect(group('chapter-translation:1/1'), findsNothing);
      expect(group('chapter-translation:1/2'), findsNothing);
      expect(group('volume-translation:2'), findsNothing);
      expect(group('chapter-translation:2/1'), findsOneWidget);
      expect(group('chapter-translation:2/2'), findsOneWidget);
      expect(group('volume-translation:3'), findsOneWidget);
      expect(find.byType(DropdownButton<String>), findsNothing);
      expect(tester.takeException(), isNull);

      controller.toggle(controller.state.chapters.first.chapter, false);
      await tester.pump();
      await tester.tap(choice('volume-translation:1', '3'));
      await tester.pump();
      expect(controller.state.selectedVolumeBranch('1'), '3');
      expect(controller.state.selected.contains('1/1'), isFalse);
      expectChoice('volume-translation:1', '3');

      await tester.tap(choice('volume-translation:1', '3'));
      await tester.pump();
      expectChoice('volume-translation:1', '3');

      await tester.tap(choice('chapter-translation:2/1', '2'));
      await tester.pump();
      expect(
        controller.state.chapters
            .firstWhere((s) => s.chapter.key == '2/1')
            .branch
            .id,
        '2',
      );
      expectChoice('chapter-translation:2/1', '2');
      expectChoice('chapter-translation:2/2', '2');
      expectChoice('volume-translation:3', '9');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disables translation radio buttons while busy', (tester) async {
    await showChapters(tester);
    await controller.run(() async {
      await tester.pump();
      for (final choices in find.byType(TranslationChoices).evaluate()) {
        expect((choices.widget as TranslationChoices).onChanged, isNull);
      }
      expect(
        tester
            .widget<RadioListTile<String>>(choice('volume-translation:1', '3'))
            .enabled,
        isFalse,
      );
    });
    await tester.pump();
    expect(
      tester
          .widget<RadioListTile<String>>(choice('volume-translation:1', '3'))
          .enabled,
      isTrue,
    );
  });

  testWidgets('collapses the whole volume and restores its choices', (
    tester,
  ) async {
    await showChapters(tester);
    controller.toggle(controller.state.chapters.first.chapter, false);
    controller.setVolumeBranch('1', '3');
    final selected = {...controller.state.selected};
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('volume-expansion:1')));
    await tester.pump();
    expect(controller.state.collapsedVolumes, contains('1'));
    expect(group('volume-header:1'), findsOneWidget);
    expect(group('volume-translation:1'), findsNothing);
    expect(find.text('Глава 1 — Інша назва'), findsNothing);
    expect(
      find.text('Глава 2'),
      findsOneWidget,
    ); // The other volume stays open.
    expect(group('chapter-translation:2/1'), findsOneWidget);
    expect(controller.state.selected, selected);
    expect(controller.state.selectedVolumeBranch('1'), '3');

    await tester.tap(find.text('Том 1'));
    await tester.pump();
    expect(controller.state.collapsedVolumes, isNot(contains('1')));
    expect(find.text('Глава 1 — Інша назва'), findsOneWidget);
    expectChoice('volume-translation:1', '3');
    expect(controller.state.selected, selected);
  });

  testWidgets('selects collapsed volumes without expanding them', (
    tester,
  ) async {
    await showChapters(tester);
    await tester.tap(find.text('Том 2'));
    await tester.pump();
    expect(group('chapter-translation:2/1'), findsNothing);
    expect(group('chapter-translation:2/2'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('volume-selection:2')));
    await tester.pump();
    expect(controller.state.selected, isNot(contains('2/1')));
    expect(controller.state.selected, isNot(contains('2/2')));
    expect(controller.state.collapsedVolumes, contains('2'));
    expect(controller.state.selected, contains('1/1'));

    await tester.tap(find.byKey(const ValueKey('volume-selection:2')));
    await tester.pump();
    expect(controller.state.selected, containsAll(['2/1', '2/2']));
    expect(controller.state.collapsedVolumes, contains('2'));
    expect(tester.takeException(), isNull);
  });
}
