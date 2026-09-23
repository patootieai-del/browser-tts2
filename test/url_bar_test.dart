import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vox_browser/core/utils/url_suggestions.dart';
import 'package:vox_browser/widgets/url_bar.dart';

const _url = 'https://example.com/some/long/path?q=1';
const _panel = Key('urlSuggestionPanel');

final _all = [
  const UrlSuggestion(url: 'https://flutter.dev/docs', title: 'Flutter docs', visits: 3),
  const UrlSuggestion(url: 'https://example.com', title: 'Example site'),
];
Future<List<UrlSuggestion>> _suggest(String q) async =>
    _all.where((s) => s.url.contains(q)).toList();
Future<List<UrlSuggestion>> _recent() async => _all;

Widget _host({
  String url = _url,
  ValueChanged<String>? onSubmit,
  Future<List<UrlSuggestion>> Function(String)? suggest = _suggest,
  Future<List<UrlSuggestion>> Function()? recent = _recent,
  FocusNode? focusNode,
  Future<void> Function(String)? onCopy,
  Future<void> Function(String)? onShare,
  Widget? below,
}) =>
    MaterialApp(
      home: Scaffold(
        body: Column(children: [
          Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 320,
              child: UrlBar(
                url: url,
                incognito: false,
                onSubmit: onSubmit ?? (_) {},
                suggest: suggest,
                recent: recent,
                focusNode: focusNode,
                onCopy: onCopy,
                onShare: onShare,
              ),
            ),
          ),
          const Spacer(),
          if (below != null) below,
          const SizedBox(height: 16),
        ]),
      ),
    );

TextEditingController _controller(WidgetTester t) =>
    t.widget<EditableText>(find.byType(EditableText)).controller;

Future<void> _activate(WidgetTester t) async {
  await t.tap(find.byType(TextField));
  await t.pumpAndSettle();
}

void main() {
  group('focus behaviour', () {
    testWidgets('activating the bar clears it', (tester) async {
      await tester.pumpWidget(_host());
      expect(_controller(tester).text, _url);
      await _activate(tester);
      expect(_controller(tester).text, '');
    });

    testWidgets('abandoned edits revert to the current URL', (tester) async {
      await tester.pumpWidget(_host());
      await tester.enterText(find.byType(TextField), 'half typed');
      await tester.pump();
      FocusManager.instance.primaryFocus!.unfocus();
      await tester.pumpAndSettle();
      expect(_controller(tester).text, _url);
    });

    testWidgets('tapping elsewhere unfocuses, hides suggestions, reverts',
        (tester) async {
      await tester.pumpWidget(_host(below: const Text('elsewhere')));
      await tester.enterText(find.byType(TextField), 'flut');
      await tester.pumpAndSettle();
      expect(find.text('Flutter docs'), findsOneWidget);

      await tester.tapAt(tester.getCenter(find.text('elsewhere')));
      await tester.pumpAndSettle();

      expect(find.byKey(_panel), findsNothing);
      expect(_controller(tester).text, _url);
      expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
          isFalse);
    });

    testWidgets('an external focus node can unfocus it (back button path)',
        (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(_host(focusNode: node));
      await _activate(tester);
      expect(find.byKey(_panel), findsOneWidget);

      node.unfocus();
      await tester.pumpAndSettle();

      expect(find.byKey(_panel), findsNothing);
      expect(_controller(tester).text, _url);
    });

    testWidgets('follows URL changes while not editing', (tester) async {
      await tester.pumpWidget(_host(url: 'https://a.test'));
      await tester.pumpWidget(_host(url: 'https://b.test'));
      await tester.pump();
      expect(_controller(tester).text, 'https://b.test');
    });
  });

  group('recent history when empty', () {
    testWidgets('shows most recent pages and the current-URL header',
        (tester) async {
      await tester.pumpWidget(_host());
      await _activate(tester);

      expect(find.text('Recent'), findsOneWidget);
      expect(find.text('Flutter docs'), findsOneWidget);
      expect(find.text('Example site'), findsOneWidget);
      expect(find.text(_url), findsOneWidget); // header (field is empty)
    });

    testWidgets('the page you are on is not suggested', (tester) async {
      await tester.pumpWidget(_host(
        recent: () async => [
          const UrlSuggestion(url: _url, title: 'This very page'),
          ..._all,
        ],
      ));
      await _activate(tester);
      expect(find.text('This very page'), findsNothing);
      expect(find.text('Flutter docs'), findsOneWidget);
    });

    testWidgets('header is still shown when there is no history',
        (tester) async {
      await tester.pumpWidget(_host(recent: () async => const []));
      await _activate(tester);
      expect(find.byKey(_panel), findsOneWidget);
      expect(find.text(_url), findsOneWidget);
    });
  });

  group('header actions', () {
    testWidgets('has edit, copy and share buttons', (tester) async {
      await tester.pumpWidget(_host());
      await _activate(tester);
      expect(find.byTooltip('Edit address'), findsOneWidget);
      expect(find.byTooltip('Copy address'), findsOneWidget);
      expect(find.byTooltip('Share address'), findsOneWidget);
    });

    testWidgets('edit puts the URL in the field with the caret at the end',
        (tester) async {
      await tester.pumpWidget(_host());
      await _activate(tester);

      await tester.tap(find.byTooltip('Edit address'));
      await tester.pumpAndSettle();

      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.controller.text, _url);
      expect(editable.controller.selection.isCollapsed, isTrue);
      expect(editable.controller.selection.baseOffset, _url.length);
      expect(editable.focusNode.hasFocus, isTrue);
      // editing the unchanged URL offers nothing else to pick
      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets('copy reports the URL and closes the panel', (tester) async {
      String? copied;
      await tester.pumpWidget(_host(onCopy: (u) async => copied = u));
      await _activate(tester);

      await tester.tap(find.byTooltip('Copy address'));
      await tester.pumpAndSettle();

      expect(copied, _url);
      expect(find.byKey(_panel), findsNothing);
      expect(_controller(tester).text, _url);
    });

    testWidgets('default copy writes to the clipboard', (tester) async {
      String? clip;
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clip = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      await tester.pumpWidget(_host());
      await _activate(tester);
      await tester.tap(find.byTooltip('Copy address'));
      await tester.pumpAndSettle();

      expect(clip, _url);
      expect(find.text('Address copied'), findsOneWidget);
    });

    testWidgets('share reports the URL and closes the panel', (tester) async {
      String? shared;
      await tester.pumpWidget(_host(onShare: (u) async => shared = u));
      await _activate(tester);

      await tester.tap(find.byTooltip('Share address'));
      await tester.pumpAndSettle();

      expect(shared, _url);
      expect(find.byKey(_panel), findsNothing);
    });

    testWidgets('actions are disabled when there is no URL', (tester) async {
      await tester.pumpWidget(_host(url: ''));
      await _activate(tester);
      final edit = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.edit));
      expect(edit.onPressed, isNull);
    });
  });

  group('suggestions', () {
    testWidgets('typing shows suggestions; tapping one opens its URL',
        (tester) async {
      String? got;
      await tester.pumpWidget(_host(onSubmit: (v) => got = v));
      await tester.enterText(find.byType(TextField), 'flut');
      await tester.pumpAndSettle();

      expect(find.text('Flutter docs'), findsOneWidget);
      expect(find.text('Example site'), findsNothing);

      await tester.tap(find.text('Flutter docs'));
      await tester.pumpAndSettle();
      expect(got, 'https://flutter.dev/docs');
      expect(find.byKey(_panel), findsNothing);
    });

    testWidgets('Enter submits what was typed, not the top suggestion',
        (tester) async {
      String? got;
      await tester.pumpWidget(_host(onSubmit: (v) => got = v));
      await tester.enterText(find.byType(TextField), 'flut');
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pumpAndSettle();
      expect(got, 'flut');
    });

    testWidgets('the arrow copies a suggestion into the field for editing',
        (tester) async {
      String? got;
      await tester.pumpWidget(_host(onSubmit: (v) => got = v));
      await tester.enterText(find.byType(TextField), 'flut');
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.north_west).first);
      await tester.pumpAndSettle();

      expect(_controller(tester).text, 'https://flutter.dev/docs');
      expect(got, isNull);
    });
  });

  group('layout', () {
    testWidgets('tablet: dropdown matches the field x-position and width',
        (tester) async {
      // default test surface is 800x600 => shortest side 600 => not a phone
      await tester.pumpWidget(_host());
      await _activate(tester);

      final field = tester.getRect(find.byType(TextField));
      final panel = tester.getRect(find.byKey(_panel));
      expect(panel.left, moreOrLessEquals(field.left, epsilon: 1));
      expect(panel.width, moreOrLessEquals(field.width, epsilon: 1));
      expect(panel.top, greaterThanOrEqualTo(field.bottom));
      expect(panel.height, lessThan(600)); // a dropdown, not a full page
    });

    testWidgets('phone: the panel fills the page under the field',
        (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host());
      await _activate(tester);

      final field = tester.getRect(find.byType(TextField));
      final panel = tester.getRect(find.byKey(_panel));
      expect(panel.left, 0);
      expect(panel.width, 400);
      expect(panel.bottom, moreOrLessEquals(800, epsilon: 1));
      expect(panel.top, greaterThanOrEqualTo(field.bottom));
    });

    testWidgets('phone: the panel stops above the keyboard', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host());
      await _activate(tester);

      final panel = tester.getRect(find.byKey(_panel));
      expect(panel.bottom, moreOrLessEquals(500, epsilon: 1));
    });
  });
}