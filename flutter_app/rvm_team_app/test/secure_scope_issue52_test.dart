import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rvm_team_app/features/shell/team_shell.dart';
import 'package:rvm_team_app/features/shell/tab_registry.dart';
import 'package:rvm_team_app/platform/secure_window.dart';
import 'package:rvm_team_app/widgets/secure_scope.dart';

/// team_app #52, item 1: the screenshot block. MainActivity sets and clears
/// FLAG_SECURE on the `team_rvm/secure_window` channel; [SecureWindow] counts
/// the screens that need it; [SecureScope] holds it only while its screen is
/// on screen, and a shell tab only while it is the selected one. The channel
/// is mocked here, so each test sees exactly what MainActivity would be told.
const _channel = MethodChannel(SecureWindow.channelName);

/// The methods MainActivity was sent, in order.
List<String> _mockChannel() {
  final calls = <String>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
    calls.add(call.method);
    return null;
  });
  addTearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null));
  return calls;
}

class _Screen extends StatelessWidget {
  const _Screen(this.label, {this.next, this.sheet = false});

  final String label;
  final WidgetBuilder? next;
  final bool sheet;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(label)),
        body: Column(
          children: [
            if (next != null)
              TextButton(
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: next!)),
                child: const Text('open'),
              ),
            if (sheet)
              TextButton(
                onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    builder: (_) => const SizedBox(
                        height: 120, child: Text('Absent reason'))),
                child: const Text('sheet'),
              ),
          ],
        ),
      );
}

void main() {
  group('SecureWindow', () {
    test('the first holder turns the block on and the last turns it off',
        () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final calls = _mockChannel();
      final window = SecureWindow();

      window.acquire();
      window.acquire();
      expect(window.holders, 2);
      window.release();
      expect(window.isOn, isTrue);
      window.release();
      window.release(); // one release too many changes nothing
      await pumpEventQueue();

      expect(calls, ['enable', 'disable']);
      expect(window.isOn, isFalse);
    });

    test('sends nothing where there is no FLAG_SECURE (iOS, web)', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final calls = _mockChannel();
      final window = SecureWindow(supported: () => false);

      window
        ..acquire()
        ..release();
      await pumpEventQueue();

      expect(calls, isEmpty);
    });

    test('MainActivity answers the same channel and both methods', () {
      final activity =
          File('android/app/src/main/kotlin/com/rvm/rvmteam/MainActivity.kt')
              .readAsStringSync();

      expect(activity, contains('"${SecureWindow.channelName}"'));
      expect(activity, contains('"enable" -> runOnUiThread'));
      expect(activity,
          contains('window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)'));
      expect(activity, contains('"disable" -> runOnUiThread'));
      expect(
          activity,
          contains(
              'window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)'));
    });
  });

  group('SecureScope on a route', () {
    testWidgets('on while its screen is pushed, off once it is popped',
        (tester) async {
      final calls = _mockChannel();
      final window = SecureWindow();
      await tester.pumpWidget(MaterialApp(
        home: _Screen('Home',
            next: (_) =>
                SecureScope(window: window, child: const _Screen('Roster'))),
      ));
      expect(calls, isEmpty, reason: 'Home is not sensitive');

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(calls, ['enable']);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(calls, ['enable', 'disable']);
      expect(window.isOn, isFalse);
    });

    testWidgets('stays on under a bottom sheet: the screen is still visible',
        (tester) async {
      final calls = _mockChannel();
      final window = SecureWindow();
      await tester.pumpWidget(MaterialApp(
        home: SecureScope(
            window: window, child: const _Screen('Roster', sheet: true)),
      ));
      await tester.tap(find.text('sheet'));
      await tester.pumpAndSettle();

      expect(find.text('Absent reason'), findsOneWidget);
      expect(calls, ['enable']);
      expect(window.isOn, isTrue);
    });

    testWidgets('off under an opaque screen, on again when it is popped',
        (tester) async {
      final calls = _mockChannel();
      final window = SecureWindow();
      await tester.pumpWidget(MaterialApp(
        home: SecureScope(
          window: window,
          child: _Screen('Roster', next: (_) => const _Screen('Wall')),
        ),
      ));
      expect(calls, ['enable']);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(calls, ['enable', 'disable'],
          reason: 'a screen that is not sensitive is on top');

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(calls, ['enable', 'disable', 'enable']);
    });

    testWidgets('a sensitive screen over a sensitive one never drops it',
        (tester) async {
      final calls = _mockChannel();
      final window = SecureWindow();
      await tester.pumpWidget(MaterialApp(
        home: SecureScope(
          window: window,
          child: _Screen('Roster',
              next: (_) =>
                  SecureScope(window: window, child: const _Screen('Student'))),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(calls, ['enable'], reason: 'counted, never off in between');
      expect(window.holders, 1);
    });

    testWidgets('nested scopes count as holders of one block', (tester) async {
      final calls = _mockChannel();
      final window = SecureWindow();
      Widget app({required bool inner, required bool outer}) => MaterialApp(
            home: outer
                ? SecureScope(
                    window: window,
                    child: inner
                        ? SecureScope(
                            window: window, child: const _Screen('Lead'))
                        : const _Screen('Lead'),
                  )
                : const _Screen('Lead'),
          );

      await tester.pumpWidget(app(inner: true, outer: true));
      expect(window.holders, 2);
      await tester.pumpWidget(app(inner: false, outer: true));
      expect(window.holders, 1);
      await tester.pumpWidget(app(inner: false, outer: false));
      await tester.pump();

      expect(calls, ['enable', 'disable']);
    });

    testWidgets('enabled: false leaves the window alone until it turns true',
        (tester) async {
      final calls = _mockChannel();
      final window = SecureWindow();
      Widget app(bool enabled) => MaterialApp(
          home: SecureScope(
              window: window, enabled: enabled, child: const _Screen('Lead')));

      await tester.pumpWidget(app(false));
      expect(calls, isEmpty);
      await tester.pumpWidget(app(true));
      await tester.pumpWidget(app(false));
      await tester.pump();

      expect(calls, ['enable', 'disable']);
    });
  });

  group('the shell', () {
    TeamTab tab(String id, {bool sensitive = false}) => TeamTab(
          id: id,
          label: id,
          icon: Icons.circle_outlined,
          selectedIcon: Icons.circle,
          body: Text('$id body'),
          sensitive: sensitive,
        );

    Widget shell(List<TeamTab> tabs, int index) => MaterialApp(
          home: Scaffold(
            body: IndexedStack(
              index: index,
              children: [
                for (var i = 0; i < tabs.length; i++)
                  shellTabBody(tabs[i], selected: i == index),
              ],
            ),
          ),
        );

    testWidgets('a sensitive tab blocks screenshots only while selected',
        (tester) async {
      final calls = _mockChannel();
      final tabs = [tab('home'), tab('dialer', sensitive: true), tab('wall')];

      await tester.pumpWidget(shell(tabs, 0));
      expect(calls, isEmpty,
          reason: 'the dialer is built in the stack but not on screen');

      await tester.pumpWidget(shell(tabs, 1));
      await tester.pumpWidget(shell(tabs, 2));
      await tester.pumpWidget(shell(tabs, 1));
      await tester.pumpWidget(shell(tabs, 0));
      await tester.pump();

      expect(calls, ['enable', 'disable', 'enable', 'disable']);
      expect(SecureWindow.instance.isOn, isFalse);
    });

    testWidgets('a tab that is not sensitive is its body as it is',
        (tester) async {
      final home = tab('home');
      expect(shellTabBody(home, selected: true), same(home.body));
      expect(shellTabBody(home, selected: false), same(home.body));
    });
  });
}
