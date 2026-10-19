import 'package:core_network/core_network.dart';
import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockDs extends Mock implements CoursesRemoteDataSource {}

class _MockConnectivity extends Mock implements ConnectivityService {}

class _FakeDraft extends Fake implements CourseDraft {}

void main() {
  setUpAll(() => registerFallbackValue(_FakeDraft()));

  group('Course parser', () {
    test('list reads book_count + price_formatted', () {
      final list = Parse.courses([
        {'id': 'c1', 'name': 'Full Stack', 'price': 12000, 'book_count': 2, 'price_formatted': '₹12,000.00'},
      ]);
      final c = list.single;
      expect(c.name, 'Full Stack');
      expect(c.price, 12000);
      expect(c.bookCount, 2);
      expect(c.priceFormatted, '₹12,000.00');
      expect(c.books, isEmpty);
    });

    test('detail reads the linked books (title from title|name)', () {
      final c = Parse.courseOf({
        'id': 'c1',
        'name': 'FS',
        'price': 12000,
        'books': [
          {'id': 'b1', 'title': 'Dart Basics', 'price': 500},
          {'id': 'b2', 'name': 'Flutter Deep Dive'},
        ],
      });
      expect(c.books.length, 2);
      expect(c.books.first.title, 'Dart Basics');
      expect(c.books.first.price, 500);
      expect(c.books.last.title, 'Flutter Deep Dive');
    });
  });

  group('CourseDraft toJson', () {
    test('sends name/price/book_ids', () {
      expect(const CourseDraft(name: 'X', price: 100, bookIds: ['b1']).toJson(),
          {'name': 'X', 'price': 100, 'book_ids': ['b1']});
    });
  });

  group('CoursesRepository', () {
    late _MockDs ds;
    late _MockConnectivity conn;
    late CoursesRepository repo;

    setUp(() {
      ds = _MockDs();
      conn = _MockConnectivity();
      repo = CoursesRepository(remote: ds, connectivity: conn);
      when(() => conn.isOnline).thenAnswer((_) async => true);
    });

    test('delete forwards id', () async {
      when(() => ds.delete(any())).thenAnswer((_) async {});
      await repo.delete('c1');
      verify(() => ds.delete('c1')).called(1);
    });

    test('offline → NoConnectionFailure', () async {
      when(() => conn.isOnline).thenAnswer((_) async => false);
      await expectLater(repo.byId('c1'), throwsA(isA<NoConnectionFailure>()));
      verifyNever(() => ds.byId(any()));
    });
  });
}
