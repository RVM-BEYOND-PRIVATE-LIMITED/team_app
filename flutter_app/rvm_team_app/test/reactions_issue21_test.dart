import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rvm_team_app/domain/ess_models.dart';
import 'package:rvm_team_app/features/wall/wall_widgets.dart';

/// Regression tests for issues_image/issue21: reactions must look like
/// Facebook — a stacked summary + total and Like | Comment actions with a
/// long-press picker — not six always-visible chips with 0 counts.
WallPost _post({String? myReaction}) => WallPost(
      id: 'p1',
      kind: 'post',
      mine: false,
      edited: false,
      hidden: false,
      deleted: false,
      body: 'hello',
      commentCount: 2,
      myReaction: myReaction,
      reactions: const WallReactionCounts(
        counts: {'like': 2, 'love': 1, 'laugh': 0, 'clap': 0, 'insightful': 0, 'curious': 0},
        total: 3,
      ),
      author: const WallPerson(id: 'u1', fullName: 'Rishi Ojha'),
    );

void main() {
  testWidgets('feed shows FB summary, Like and Comment, no zero chips',
      (tester) async {
    String? last;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WallPostCard(
          post: _post(),
          onReact: (r) => last = r,
          onOpen: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Facebook summary: stacked emojis + total 3, comments on the right.
    expect(find.text('3'), findsWidgets);
    expect(find.textContaining('2 comments'), findsOneWidget);
    // Facebook actions.
    expect(find.text('Like'), findsOneWidget);
    expect(find.text('Comment'), findsOneWidget);
    // Old layout had six chips each with a 0 — they must be gone.
    expect(find.textContaining('❤️0'), findsNothing);
    expect(find.textContaining('😄0'), findsNothing);
    expect(find.text('👍0'), findsNothing);

    // Tap Like toggles 'like'.
    await tester.tap(find.text('Like'));
    await tester.pumpAndSettle();
    expect(last, 'like');
  });

  testWidgets('liked post shows reaction label and tap removes it',
      (tester) async {
    String? last = 'unset';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WallPostCard(
          post: _post(myReaction: 'love'),
          onReact: (r) => last = r,
          onOpen: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Love'), findsOneWidget);
    await tester.tap(find.text('Love'));
    await tester.pumpAndSettle();
    expect(last, isNull);
  });
}
