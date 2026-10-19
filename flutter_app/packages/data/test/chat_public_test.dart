import 'package:core_network/core_network.dart';
import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockChatDs extends Mock implements ChatRemoteDataSource {}

class _MockPublicDs extends Mock implements PublicRemoteDataSource {}

class _MockJobsDs extends Mock implements JobsRemoteDataSource {}

class _MockConnectivity extends Mock implements ConnectivityService {}

void main() {
  group('Chat + public parsers', () {
    test('chatThread maps sender_type → fromCandidate and reads conversation_id', () {
      final t = Parse.chatThread({
        'conversation_id': 'conv-1',
        'messages': [
          {'id': 'm1', 'sender_type': 'admin', 'content': 'Hi', 'is_read': true, 'created_at': '2026-07-01'},
          {'id': 'm2', 'sender_type': 'candidate', 'content': 'Hello', 'created_at': '2026-07-01'},
        ],
      });
      expect(t.conversationId, 'conv-1');
      expect(t.messages, hasLength(2));
      expect(t.messages[0].fromCandidate, isFalse);
      expect(t.messages[1].fromCandidate, isTrue);
      expect(t.messages[0].isRead, isTrue);
    });

    test('candidateAnnouncements reads a bare list and maps body', () {
      final a = Parse.candidateAnnouncements([
        {'id': 'a1', 'title': 'Placement drive', 'body': 'On Friday', 'created_at': '2026-07-02'}
      ]);
      expect(a.single.title, 'Placement drive');
      expect(a.single.body, 'On Friday');
    });

    test('candidateAnnouncements tolerates an empty list', () {
      expect(Parse.candidateAnnouncements(const []), isEmpty);
      expect(Parse.candidateAnnouncements({'unexpected': true}), isEmpty);
    });

    test('activeOffer returns null when {offer:null}, an Offer when present', () {
      expect(Parse.activeOffer({'offer': null}), isNull);
      final o = Parse.activeOffer({
        'offer': {'id': 'o1', 'name': 'Diwali', 'message': 'Save now', 'price_paise': 150000}
      });
      expect(o, isNotNull);
      expect(o!.name, 'Diwali');
      expect(o.priceRupees, 1500);
    });
  });

  group('ChatRepository', () {
    late _MockChatDs ds;
    late _MockConnectivity conn;
    late ChatRepository repo;
    setUp(() {
      ds = _MockChatDs();
      conn = _MockConnectivity();
      repo = ChatRepository(remote: ds, connectivity: conn);
    });

    test('online → returns the thread', () async {
      when(() => conn.isOnline).thenAnswer((_) async => true);
      when(() => ds.thread()).thenAnswer((_) async => const ChatThread(conversationId: 'c1'));
      expect((await repo.thread()).conversationId, 'c1');
    });

    test('offline → send never touches the data source', () async {
      when(() => conn.isOnline).thenAnswer((_) async => false);
      await expectLater(repo.send('hi'), throwsA(isA<NoConnectionFailure>()));
      verifyNever(() => ds.send(any()));
    });
  });

  group('PublicRepository extras', () {
    late _MockPublicDs ds;
    late _MockConnectivity conn;
    late PublicRepository repo;
    setUp(() {
      ds = _MockPublicDs();
      conn = _MockConnectivity();
      repo = PublicRepository(remote: ds, connectivity: conn);
    });

    test('online → submitBanAppeal returns the reference id', () async {
      when(() => conn.isOnline).thenAnswer((_) async => true);
      when(() => ds.submitBanAppeal(
            name: any(named: 'name'),
            email: any(named: 'email'),
            phone: any(named: 'phone'),
            message: any(named: 'message'),
          )).thenAnswer((_) async => 'APPEAL-20260703-ABCDEF');
      final ref = await repo.submitBanAppeal(
          name: 'A', email: 'a@b.com', phone: '9876543210', message: 'x' * 25);
      expect(ref, startsWith('APPEAL-'));
    });

    test('offline → submitBanAppeal never touches the data source', () async {
      when(() => conn.isOnline).thenAnswer((_) async => false);
      await expectLater(
        repo.submitBanAppeal(name: 'A', email: 'a@b.com', phone: '9876543210', message: 'x' * 25),
        throwsA(isA<NoConnectionFailure>()),
      );
      verifyNever(() => ds.submitBanAppeal(
            name: any(named: 'name'),
            email: any(named: 'email'),
            phone: any(named: 'phone'),
            message: any(named: 'message'),
          ));
    });

    test('online → activeOffer passes through null (no offer running)', () async {
      when(() => conn.isOnline).thenAnswer((_) async => true);
      when(() => ds.activeOffer()).thenAnswer((_) async => null);
      expect(await repo.activeOffer(), isNull);
    });

    test('online → activeOffer passes through a live offer', () async {
      when(() => conn.isOnline).thenAnswer((_) async => true);
      when(() => ds.activeOffer())
          .thenAnswer((_) async => const Offer(id: 'o1', name: 'Diwali', pricePaise: 150000));
      final o = await repo.activeOffer();
      expect(o?.name, 'Diwali');
      expect(o?.priceRupees, 1500);
    });
  });

  group('JobsRepository.candidateAnnouncements', () {
    late _MockJobsDs ds;
    late _MockConnectivity conn;
    late JobsRepository repo;
    setUp(() {
      ds = _MockJobsDs();
      conn = _MockConnectivity();
      repo = JobsRepository(remote: ds, connectivity: conn);
    });

    test('online → returns the announcements', () async {
      when(() => conn.isOnline).thenAnswer((_) async => true);
      when(() => ds.candidateAnnouncements()).thenAnswer((_) async =>
          const [AnnouncementItem(id: 'a1', title: 'Drive', category: AnnouncementCategory.institute)]);
      expect((await repo.candidateAnnouncements()).single.title, 'Drive');
    });

    test('offline → NoConnectionFailure, data source untouched', () async {
      when(() => conn.isOnline).thenAnswer((_) async => false);
      await expectLater(repo.candidateAnnouncements(), throwsA(isA<NoConnectionFailure>()));
      verifyNever(() => ds.candidateAnnouncements());
    });
  });
}
