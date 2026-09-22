import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vox_browser/widgets/url_bar.dart';

const _url = 'https://example.com/some/long/path?q=1';

Widget _host({String url = _url, ValueChanged<String>? onSubmit}) =>
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            child: UrlBar(url: url, incognito: false, onSubmit: onSubmit ?? (_) {}),
          ),
        ),
      ),
    );

TextEditingController _controller(WidgetTester t) =>
    t.widget<EditableText>(find.byType(EditableText)).controller;

void main() {
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
}