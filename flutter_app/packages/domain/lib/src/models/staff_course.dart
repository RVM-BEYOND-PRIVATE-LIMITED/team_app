/// Scheduler course catalog — a named course with a price, a count of linked
/// books (list view), and the full book list (detail view). Courses are
/// attached to admissions. Create/update also manage the linked books via an
/// RPC; those forms are deferred in mobile (they need a books picker, and an
/// omitted book_ids list wipes the associations).
class Course {
  const Course({
    required this.id,
    required this.name,
    this.price,
    this.priceFormatted,
    this.bookCount = 0,
    this.books = const [],
  });

  final String id;
  final String name;
  final num? price;

  /// Backend-formatted INR string (e.g. "₹12,000.00").
  final String? priceFormatted;

  /// Count of linked books (list view).
  final int bookCount;

  /// The linked books (detail view only).
  final List<CourseBook> books;
}

/// A book linked to a course (from the detail endpoint's `books(*)` join).
class CourseBook {
  const CourseBook({required this.id, required this.title, this.price});
  final String id;
  final String title;
  final num? price;
}

/// Create/update payload for POST/PUT /courses. [bookIds] replaces the linked
/// book set — an omitted/empty list clears all associations, so this must only
/// be built by a form that surfaces a books picker.
class CourseDraft {
  const CourseDraft({required this.name, required this.price, this.bookIds = const []});

  final String name;
  final num price;
  final List<String> bookIds;

  Map<String, dynamic> toJson() => {
        'name': name,
        'price': price,
        'book_ids': bookIds,
      };
}
