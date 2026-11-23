import 'package:equatable/equatable.dart';

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;
int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
double? _num(Object? v) =>
    v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
String? _str(Object? v) => v == null ? null : '$v';
Map<String, dynamic> _map(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : const {};
List<String> _strings(Object? v) =>
    v is List ? [for (final x in v) '$x'] : const [];

/// The quiz waiting or open now (#152, Scheduler_Backend #692).
class QuizRound extends Equatable {
  const QuizRound({
    required this.id,
    required this.status,
    this.deliveredAt,
    this.expiresAt,
    this.answerSeconds = 60,
    this.question,
    this.options = const [],
    this.openedAt,
    this.deadlineAt,
    this.secondsLeft,
  });

  final int id;
  final String status;
  final DateTime? deliveredAt;
  final DateTime? expiresAt;
  final int answerSeconds;
  final String? question;
  final List<String> options;
  final DateTime? openedAt;
  final DateTime? deadlineAt;
  final int? secondsLeft;

  bool get isOpen => status == 'opened' && question != null;

  factory QuizRound.fromJson(Map<String, dynamic> j) => QuizRound(
        id: _int(j['id']) ?? 0,
        status: _str(j['status']) ?? 'delivered',
        deliveredAt: _date(j['delivered_at']),
        expiresAt: _date(j['expires_at']),
        answerSeconds: _int(j['answer_seconds']) ?? 60,
        question: _str(j['question']),
        options: _strings(j['options']),
        openedAt: _date(j['opened_at']),
        deadlineAt: _date(j['deadline_at']),
        secondsLeft: _int(j['seconds_left']),
      );

  @override
  List<Object?> get props => [
        id,
        status,
        deliveredAt,
        expiresAt,
        answerSeconds,
        question,
        options,
        openedAt,
        deadlineAt,
        secondsLeft,
      ];
}

class QuizCurrent extends Equatable {
  const QuizCurrent({
    this.round,
    this.planned = 0,
    this.done = 0,
    this.serverTime,
  });

  final QuizRound? round;
  final int planned;
  final int done;
  final DateTime? serverTime;

  factory QuizCurrent.fromJson(Map<String, dynamic> j) {
    final today = _map(j['today']);
    final r = _map(j['round']);
    return QuizCurrent(
      round: r.isEmpty ? null : QuizRound.fromJson(r),
      planned: _int(today['planned']) ?? 0,
      done: _int(today['done']) ?? 0,
      serverTime: _date(j['server_time']),
    );
  }

  @override
  List<Object?> get props => [round, planned, done, serverTime];
}

class QuizOpened extends Equatable {
  const QuizOpened({
    required this.roundId,
    required this.question,
    required this.options,
    this.deadlineAt,
    this.secondsLeft = 60,
    this.serverTime,
  });

  final int roundId;
  final String question;
  final List<String> options;
  final DateTime? deadlineAt;
  final int secondsLeft;
  final DateTime? serverTime;

  factory QuizOpened.fromJson(Map<String, dynamic> j) => QuizOpened(
        roundId: _int(j['round_id']) ?? 0,
        question: _str(j['question']) ?? '',
        options: _strings(j['options']),
        deadlineAt: _date(j['deadline_at']),
        secondsLeft: _int(j['seconds_left']) ?? 60,
        serverTime: _date(j['server_time']),
      );

  @override
  List<Object?> get props =>
      [roundId, question, options, deadlineAt, secondsLeft, serverTime];
}

class QuizAnswerResult extends Equatable {
  const QuizAnswerResult({
    required this.roundId,
    required this.status,
    this.reason,
    this.correct,
    this.chosenIndex,
    this.correctIndex,
    this.explanation,
    this.kbSection,
    this.secondsTaken,
  });

  final int roundId;
  final String status;
  final String? reason;
  final bool? correct;
  final int? chosenIndex;
  final int? correctIndex;
  final String? explanation;
  final String? kbSection;
  final double? secondsTaken;

  factory QuizAnswerResult.fromJson(Map<String, dynamic> j) => QuizAnswerResult(
        roundId: _int(j['round_id']) ?? 0,
        status: _str(j['status']) ?? 'answered',
        reason: _str(j['reason']),
        correct: j['correct'] is bool ? j['correct'] as bool : null,
        chosenIndex: _int(j['chosen_index']),
        correctIndex: _int(j['correct_index']),
        explanation: _str(j['explanation']),
        kbSection: _str(j['kb_section']),
        secondsTaken: _num(j['seconds_taken']),
      );

  @override
  List<Object?> get props => [
        roundId,
        status,
        reason,
        correct,
        chosenIndex,
        correctIndex,
        explanation,
        kbSection,
        secondsTaken,
      ];
}

class QuizTally extends Equatable {
  const QuizTally({
    this.rounds = 0,
    this.answered = 0,
    this.correct = 0,
    this.wrong = 0,
    this.missed = 0,
    this.skipped = 0,
    this.accuracy,
    this.answerRate,
    this.avgSeconds,
  });

  final int rounds;
  final int answered;
  final int correct;
  final int wrong;
  final int missed;
  final int skipped;
  final double? accuracy;
  final double? answerRate;
  final double? avgSeconds;

  factory QuizTally.fromJson(Map<String, dynamic> j) => QuizTally(
        rounds: _int(j['rounds']) ?? 0,
        answered: _int(j['answered']) ?? 0,
        correct: _int(j['correct']) ?? 0,
        wrong: _int(j['wrong']) ?? 0,
        missed: _int(j['missed']) ?? 0,
        skipped: _int(j['skipped']) ?? 0,
        accuracy: _num(j['accuracy']),
        answerRate: _num(j['answer_rate']),
        avgSeconds: _num(j['avg_seconds']),
      );

  @override
  List<Object?> get props => [
        rounds,
        answered,
        correct,
        wrong,
        missed,
        skipped,
        accuracy,
        answerRate,
        avgSeconds
      ];
}

class QuizHistoryItem extends Equatable {
  const QuizHistoryItem({
    required this.roundId,
    required this.date,
    this.kbSection,
    this.status = 'answered',
    this.correct,
    this.secondsTaken,
    this.answeredAt,
  });

  final int roundId;
  final String date;
  final String? kbSection;
  final String status;
  final bool? correct;
  final double? secondsTaken;
  final DateTime? answeredAt;

  factory QuizHistoryItem.fromJson(Map<String, dynamic> j) => QuizHistoryItem(
        roundId: _int(j['round_id']) ?? 0,
        date: _str(j['date']) ?? '',
        kbSection: _str(j['kb_section']),
        status: _str(j['status']) ?? 'answered',
        correct: j['correct'] is bool ? j['correct'] as bool : null,
        secondsTaken: _num(j['seconds_taken']),
        answeredAt: _date(j['answered_at']),
      );

  @override
  List<Object?> get props =>
      [roundId, date, kbSection, status, correct, secondsTaken, answeredAt];
}

class QuizMe extends Equatable {
  const QuizMe({
    this.today = const QuizTally(),
    this.week = const QuizTally(),
    this.month = const QuizTally(),
    this.streak = 0,
    this.history = const [],
  });

  final QuizTally today;
  final QuizTally week;
  final QuizTally month;
  final int streak;
  final List<QuizHistoryItem> history;

  factory QuizMe.fromJson(Map<String, dynamic> j) => QuizMe(
        today: QuizTally.fromJson(_map(j['today'])),
        week: QuizTally.fromJson(_map(j['week'])),
        month: QuizTally.fromJson(_map(j['month'])),
        streak: _int(j['streak']) ?? 0,
        history: [
          for (final row
              in (j['history'] is List ? j['history'] as List : const []))
            QuizHistoryItem.fromJson(_map(row)),
        ],
      );

  @override
  List<Object?> get props => [today, week, month, streak, history];
}

class QuizPersonResult extends Equatable {
  const QuizPersonResult({
    required this.name,
    this.accuracy,
    this.answered = 0,
    this.missed = 0,
    this.avgSeconds,
  });

  final String name;
  final double? accuracy;
  final int answered;
  final int missed;
  final double? avgSeconds;

  factory QuizPersonResult.fromJson(Map<String, dynamic> j) => QuizPersonResult(
        name: _str(j['name']) ?? 'Employee',
        accuracy: _num(j['accuracy']),
        answered: _int(j['answered']) ?? 0,
        missed: _int(j['missed']) ?? 0,
        avgSeconds: _num(j['avg_seconds']),
      );

  @override
  List<Object?> get props => [name, accuracy, answered, missed, avgSeconds];
}

class QuizResults extends Equatable {
  const QuizResults({this.people = const [], this.accuracy});

  final List<QuizPersonResult> people;
  final double? accuracy;

  factory QuizResults.fromJson(Map<String, dynamic> j) {
    final totals = _map(j['totals']);
    return QuizResults(
      people: [
        for (final row
            in (j['people'] is List ? j['people'] as List : const []))
          QuizPersonResult.fromJson(_map(row)),
      ],
      accuracy: _num(totals['accuracy']),
    );
  }

  @override
  List<Object?> get props => [people, accuracy];
}
