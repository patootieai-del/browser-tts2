import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vox_browser/widgets/url_bar.dart';
import 'package:vox_browser/core/utils/url_suggestions.dart';

const _url = 'https://example.com/some/long/path?q=1';

Widget _host({
  String url = _url,
  ValueChanged<String>? onSubmit,
  Future<List<UrlSuggestion>> Function(String)? suggest,
  FocusNode? focusNode,
}) =>
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 320,
            child: UrlBar(
                url: url,
                incognito: false,
                onSubmit: onSubmit ?? (_) {},
                suggest: suggest,
                focusNode: focusNode),
          ),
        ),
      ),
    );

TextEditingController _controller(WidgetTester t) =>
    t.widget<EditableText>(find.byType(EditableText)).controller;

void main() {
  final _all = [
    const UrlSuggestion(
        url: 'https://flutter.dev/docs', title: 'Flutter docs', visits: 3),
    const UrlSuggestion(url: 'https://example.com', title: 'Example site'),
  ];
  Future<List<UrlSuggestion>> _suggest(String q) async =>
      _all.where((s) => s.url.contains(q)).toList();
// inside main():
  testWidgets('typing shows suggestions; tapping one opens its URL',
      (tester) async {
    String? got;
    await tester.pumpWidget(_host(suggest: _suggest, onSubmit: (v) => got = v));
    await tester.enterText(find.byType(TextField), 'flut');
    await tester.pumpAndSettle();
    expect(find.text('Flutter docs'), findsOneWidget);
    expect(find.text('Example site'), findsNothing);
    await tester.tap(find.text('Flutter docs'));
    await tester.pumpAndSettle();
    expect(got, 'https://flutter.dev/docs');
  });
  testWidgets('no suggestions for the untouched (select-all) current URL',
      (tester) async {
    await tester
        .pumpWidget(_host(url: 'https://example.com', suggest: _suggest));
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNothing);
  });
  testWidgets('Enter submits what was typed, not the top suggestion',
      (tester) async {
    String? got;
    await tester.pumpWidget(_host(suggest: _suggest, onSubmit: (v) => got = v));
    await tester.enterText(find.byType(TextField), 'flut');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(got, 'flut');
  });
  testWidgets('the arrow button copies a suggestion into the field for editing',
      (tester) async {
    String? got;
    await tester.pumpWidget(_host(suggest: _suggest, onSubmit: (v) => got = v));
    await tester.enterText(find.byType(TextField), 'flut');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.north_west).first);
    await tester.pumpAndSettle();
    expect(_controller(tester).text, 'https://flutter.dev/docs');
    expect(got, isNull); // not navigated
  });

  testWidgets('tapping the URL bar selects the whole URL', (tester) async {
    await tester.pumpWidget(_host());
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    final c = _controller(tester);
    expect(c.text, _url);
    expect(c.selection.start, 0);
    expect(c.selection.end, _url.length);
  });

  testWidgets('typing replaces the selected URL', (tester) async {
    await tester.pumpWidget(_host());
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    tester.testTextInput.enterText('flutter.dev');
    await tester.pump();
    expect(_controller(tester).text, 'flutter.dev');
  });

  testWidgets('a second tap while focused places the caret (no re-select)',
      (tester) async {
    await tester.pumpWidget(_host());
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    final c = _controller(tester);
    c.selection = const TextSelection.collapsed(offset: 3);
    await tester.tapAt(tester.getCenter(find.byType(TextField)));
    await tester.pumpAndSettle();

    expect(c.selection.isCollapsed, isTrue);
  });

  testWidgets('re-activating after losing focus selects all again',
      (tester) async {
    await tester.pumpWidget(_host());
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    FocusManager.instance.primaryFocus!.unfocus();
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    final c = _controller(tester);
    expect((c.selection.start, c.selection.end), (0, _url.length));
  });

  testWidgets('abandoned edits revert to the current URL', (tester) async {
    await tester.pumpWidget(_host());
    await tester.enterText(find.byType(TextField), 'half typed');
    await tester.pump();

    FocusManager.instance.primaryFocus!.unfocus();
    await tester.pump();

    expect(_controller(tester).text, _url);
  });

  testWidgets('submitting reports the typed text', (tester) async {
    String? got;
    await tester.pumpWidget(_host(onSubmit: (v) => got = v));
    await tester.enterText(find.byType(TextField), 'flutter dev');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pump();

    expect(got, 'flutter dev');
  });

  testWidgets('follows URL changes while not editing', (tester) async {
    await tester.pumpWidget(_host(url: 'https://a.test'));
    await tester.pumpWidget(_host(url: 'https://b.test'));
    await tester.pump();
    expect(_controller(tester).text, 'https://b.test');
  });

  testWidgets('tapping elsewhere unfocuses, hides suggestions and reverts',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          SizedBox(
            width: 320,
            child: UrlBar(
                url: _url,
                incognito: false,
                onSubmit: (_) {},
                suggest: _suggest),
          ),
          const SizedBox(height: 200, width: 320, child: Text('elsewhere')),
        ]),
      ),
    ));

    await tester.enterText(find.byType(TextField), 'flut');
    await tester.pumpAndSettle();
    expect(find.text('Flutter docs'), findsOneWidget);

    await tester.tapAt(tester.getCenter(find.text('elsewhere')));
    await tester.pumpAndSettle();

    expect(find.text('Flutter docs'), findsNothing); // hidden
    expect(_controller(tester).text, _url); // reverted
    expect(FocusManager.instance.primaryFocus?.hasFocus, isNot(true));
  });

  testWidgets('an external focus node can unfocus the bar (back button path)',
      (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(_host(suggest: _suggest, focusNode: node));

    await tester.enterText(find.byType(TextField), 'flut');
    await tester.pumpAndSettle();
    expect(node.hasFocus, isTrue);
    expect(find.text('Flutter docs'), findsOneWidget);

    node.unfocus(); // what PopScope does
    await tester.pumpAndSettle();

    expect(node.hasFocus, isFalse);
    expect(find.text('Flutter docs'), findsNothing);
    expect(_controller(tester).text, _url);
  });

  testWidgets('the suggestion list matches the field width and x-position',
      (tester) async {
    await tester.pumpWidget(_host(suggest: _suggest));
    await tester.enterText(find.byType(TextField), 'flut');
    await tester.pumpAndSettle();

    final field = tester.getRect(find.byType(TextField));
    final list = tester.getRect(find.byType(ListTile).first);
    expect(list.left, moreOrLessEquals(field.left, epsilon: 1));
    expect(list.width, moreOrLessEquals(field.width, epsilon: 1));
    expect(list.top, greaterThanOrEqualTo(field.bottom));
  });
}
