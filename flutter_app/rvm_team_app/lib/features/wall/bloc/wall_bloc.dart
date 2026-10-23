import 'package:core_bloc/core_bloc.dart';
import 'package:core_network/core_network.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/ess_repository.dart';
import '../../../domain/ess_models.dart';

/// Phase 2A: the Wall — feed, reactions, praise, celebrations, announcements.
sealed class WallEvent {
  const WallEvent();
}

class WallLoadRequested extends WallEvent {
  const WallLoadRequested();
}

class WallRefreshed extends WallEvent {
  const WallRefreshed();
}

class WallPostCreated extends WallEvent {
  const WallPostCreated(
      {required this.body,
      this.kind = 'post',
      this.scope,
      this.poll,
      this.attachments});
  final String body;
  final String kind;
  final String? scope;
  final Map<String, dynamic>? poll;
  final List<Map<String, dynamic>>? attachments;
}

class WallPraiseCreated extends WallEvent {
  const WallPraiseCreated({
    required this.employeeId,
    required this.badge,
    required this.reason,
    this.scope = 'org',
    this.attachments,
  });
  final String employeeId;
  final String badge;
  final String reason;
  final String scope;
  final List<Map<String, dynamic>>? attachments;
}

class WallReacted extends WallEvent {
  const WallReacted({required this.postId, required this.reaction});
  final String postId;
  final String? reaction; // null = remove
}

class WallPollVoted extends WallEvent {
  const WallPollVoted({required this.pollId, required this.optionIds});
  final String pollId;
  final List<String> optionIds;
}

class WallAnnouncementRead extends WallEvent {
  const WallAnnouncementRead(this.id);
  final String id;
}

class WallAnnouncementAcked extends WallEvent {
  const WallAnnouncementAcked(this.id);
  final String id;
}

class WallWished extends WallEvent {
  const WallWished(
      {required this.employeeId, required this.occasion, required this.body});
  final String employeeId;
  final String occasion;
  final String body;
}

class WallState extends Equatable {
  const WallState({
    this.status = LoadStatus.initial,
    this.posts = const [],
    this.settings,
    this.announcements = const [],
    this.celebrations,
    this.failure,
    this.submitting = false,
    this.actionFailure,
    this.actionNonce = 0,
  });

  final LoadStatus status;
  final List<WallPost> posts;
  final WallSettings? settings;
  final List<WallAnnouncement> announcements;
  final WallCelebrations? celebrations;
  final Failure? failure;
  final bool submitting;
  final Failure? actionFailure;
  final int actionNonce;

  @override
  List<Object?> get props => [
        status,
        posts,
        settings,
        announcements,
        celebrations,
        failure,
        submitting,
        actionFailure,
        actionNonce
      ];
}

class WallBloc extends Bloc<WallEvent, WallState> {
  WallBloc(this._repo) : super(const WallState()) {
    on<WallLoadRequested>((_, emit) => _load(emit));
    on<WallRefreshed>((_, emit) => _load(emit));
    on<WallPostCreated>(_onPost);
    on<WallPraiseCreated>(_onPraise);
    on<WallReacted>(_onReact);
    on<WallPollVoted>(_onVote);
    on<WallAnnouncementRead>((e, emit) => _read(e.id, emit));
    on<WallAnnouncementAcked>((e, emit) => _ack(e.id, emit));
    on<WallWished>(_onWish);
  }

  final EssRepository _repo;

  Future<void> _load(Emitter<WallState> emit) async {
    emit(WallState(
        status: LoadStatus.loading,
        posts: state.posts,
        settings: state.settings,
        announcements: state.announcements,
        celebrations: state.celebrations));
    // These reads return their failure instead of throwing. A debugger set to
    // stop on exceptions must not open on an expected 503, and a Wall whose
    // tables have not been migrated must render a retry screen, not crash.
    final settingsResult =
        state.settings == null ? await _repo.wallSettingsSafe() : null;
    final feedResult = await _repo.wallFeedSafe();
    final feed = feedResult.data;
    if (feed == null) {
      emit(WallState(
        status: LoadStatus.failure,
        posts: state.posts,
        settings: state.settings ?? settingsResult?.data,
        failure: feedResult.failure ??
            const UnknownFailure('Could not load the Wall. Pull to retry.'),
      ));
      return;
    }
    // Announcements and celebrations are optional sections: if their tables are
    // not installed, the feed still opens.
    final announcements =
        (await _repo.wallAnnouncementsSafe()).data ?? state.announcements;
    final celebrations =
        (await _repo.wallCelebrationsSafe()).data ?? state.celebrations;
    emit(WallState(
      status: feed.posts.isEmpty ? LoadStatus.empty : LoadStatus.success,
      posts: feed.posts,
      settings: state.settings ?? settingsResult?.data,
      announcements: announcements,
      celebrations: celebrations,
    ));
  }

  Future<void> _onPost(WallPostCreated e, Emitter<WallState> emit) async {
    emit(WallState(
        status: state.status,
        posts: state.posts,
        settings: state.settings,
        announcements: state.announcements,
        celebrations: state.celebrations,
        submitting: true));
    try {
      await _repo.createWallPost(
          body: e.body,
          kind: e.kind,
          scope: e.scope,
          poll: e.poll,
          attachments: e.attachments);
      emit(WallState(
        status: state.status,
        posts: state.posts,
        settings: state.settings,
        announcements: state.announcements,
        celebrations: state.celebrations,
        actionNonce: state.actionNonce + 1,
      ));
      await _load(emit);
    } on Failure catch (f) {
      emit(WallState(
          status: state.status,
          posts: state.posts,
          settings: state.settings,
          announcements: state.announcements,
          celebrations: state.celebrations,
          actionFailure: f));
    }
  }

  Future<void> _onPraise(WallPraiseCreated e, Emitter<WallState> emit) async {
    emit(WallState(
        status: state.status,
        posts: state.posts,
        settings: state.settings,
        announcements: state.announcements,
        celebrations: state.celebrations,
        submitting: true));
    try {
      final result = await _repo.createPraiseSafe(
          employeeId: e.employeeId,
          badge: e.badge,
          reason: e.reason,
          scope: e.scope,
          attachments: e.attachments);
      if (result.failure != null) {
        emit(WallState(
            status: state.status,
            posts: state.posts,
            settings: state.settings,
            announcements: state.announcements,
            celebrations: state.celebrations,
            actionFailure: result.failure));
        return;
      }
      emit(WallState(
          status: state.status,
          posts: state.posts,
          settings: state.settings,
          announcements: state.announcements,
          celebrations: state.celebrations,
          actionNonce: state.actionNonce + 1));
      await _load(emit);
    } on Failure catch (f) {
      emit(WallState(
          status: state.status,
          posts: state.posts,
          settings: state.settings,
          announcements: state.announcements,
          celebrations: state.celebrations,
          actionFailure: f));
    }
  }

  Future<void> _onReact(WallReacted e, Emitter<WallState> emit) async {
    try {
      final result = e.reaction == null
          ? await _repo.unreactToPost(e.postId)
          : await _repo.reactToPost(e.postId, e.reaction!);
      final posts = [
        for (final p in state.posts)
          p.id == e.postId
              ? WallPost(
                  id: p.id,
                  kind: p.kind,
                  scope: p.scope,
                  branchId: p.branchId,
                  author: p.author,
                  mine: p.mine,
                  body: p.body,
                  attachments: p.attachments,
                  mentions: p.mentions,
                  about: p.about,
                  edited: p.edited,
                  editedAt: p.editedAt,
                  createdAt: p.createdAt,
                  updatedAt: p.updatedAt,
                  hidden: p.hidden,
                  deleted: p.deleted,
                  badgeId: p.badgeId,
                  badgeLabel: p.badgeLabel,
                  occasion: p.occasion,
                  reactions: result.counts,
                  commentCount: p.commentCount,
                  poll: p.poll,
                  myReaction: result.myReaction,
                )
              : p,
      ];
      emit(WallState(
          status: state.status,
          posts: posts,
          settings: state.settings,
          announcements: state.announcements,
          celebrations: state.celebrations,
          actionNonce: state.actionNonce));
    } on Failure catch (f) {
      emit(WallState(
          status: state.status,
          posts: state.posts,
          settings: state.settings,
          announcements: state.announcements,
          celebrations: state.celebrations,
          actionFailure: f));
    }
  }

  Future<void> _onVote(WallPollVoted e, Emitter<WallState> emit) async {
    try {
      await _repo.votePoll(pollId: e.pollId, optionIds: e.optionIds);
      await _load(emit);
    } on Failure catch (f) {
      emit(WallState(
          status: state.status,
          posts: state.posts,
          settings: state.settings,
          announcements: state.announcements,
          celebrations: state.celebrations,
          actionFailure: f));
    }
  }

  Future<void> _onWish(WallWished e, Emitter<WallState> emit) async {
    try {
      await _repo.sendWish(
          employeeId: e.employeeId, occasion: e.occasion, body: e.body);
      final celebrations = await _repo.wallCelebrations();
      emit(WallState(
          status: state.status,
          posts: state.posts,
          settings: state.settings,
          announcements: state.announcements,
          celebrations: celebrations,
          actionNonce: state.actionNonce + 1));
    } on Failure catch (f) {
      emit(WallState(
          status: state.status,
          posts: state.posts,
          settings: state.settings,
          announcements: state.announcements,
          celebrations: state.celebrations,
          actionFailure: f));
    }
  }

  Future<void> _read(String id, Emitter<WallState> emit) async {
    try {
      await _repo.readAnnouncement(id);
      final list = [
        for (final a in state.announcements)
          a.id == id
              ? WallAnnouncement(
                  id: a.id,
                  title: a.title,
                  body: a.body,
                  attachments: a.attachments,
                  author: a.author,
                  mine: a.mine,
                  audienceLabel: a.audienceLabel,
                  needsAck: a.needsAck,
                  closesOn: a.closesOn,
                  pinned: a.pinned,
                  publishedAt: a.publishedAt,
                  createdAt: a.createdAt,
                  readAt: DateTime.now(),
                  ackAt: a.ackAt)
              : a,
      ];
      emit(WallState(
          status: state.status,
          posts: state.posts,
          settings: state.settings,
          announcements: list,
          celebrations: state.celebrations,
          actionNonce: state.actionNonce));
    } on Failure {
      // Reading is best-effort.
    }
  }

  Future<void> _ack(String id, Emitter<WallState> emit) async {
    try {
      await _repo.ackAnnouncement(id);
      final list = [
        for (final a in state.announcements)
          a.id == id
              ? WallAnnouncement(
                  id: a.id,
                  title: a.title,
                  body: a.body,
                  attachments: a.attachments,
                  author: a.author,
                  mine: a.mine,
                  audienceLabel: a.audienceLabel,
                  needsAck: a.needsAck,
                  closesOn: a.closesOn,
                  pinned: a.pinned,
                  publishedAt: a.publishedAt,
                  createdAt: a.createdAt,
                  readAt: a.readAt ?? DateTime.now(),
                  ackAt: DateTime.now())
              : a,
      ];
      emit(WallState(
          status: state.status,
          posts: state.posts,
          settings: state.settings,
          announcements: list,
          celebrations: state.celebrations,
          actionNonce: state.actionNonce + 1));
    } on Failure catch (f) {
      emit(WallState(
          status: state.status,
          posts: state.posts,
          settings: state.settings,
          announcements: state.announcements,
          celebrations: state.celebrations,
          actionFailure: f));
    }
  }
}
