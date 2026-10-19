import 'package:core_bloc/core_bloc.dart';
import 'package:core_network/core_network.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/ess_repository.dart';
import '../../../domain/ess_models.dart';

/// D6/D8: the notifications Inbox, unread count, read/read-all and the category opt-outs.
sealed class NotificationsEvent {
  const NotificationsEvent();
}

class NotificationsLoadRequested extends NotificationsEvent {
  const NotificationsLoadRequested();
}

class NotificationsRefreshed extends NotificationsEvent {
  const NotificationsRefreshed();
}

class NotificationReadRequested extends NotificationsEvent {
  const NotificationReadRequested(this.id);
  final String id;
}

class NotificationsReadAllRequested extends NotificationsEvent {
  const NotificationsReadAllRequested();
}

class NotificationSettingToggled extends NotificationsEvent {
  const NotificationSettingToggled({required this.category, required this.enabled});
  final String category;
  final bool enabled;
}

class NotificationsState extends Equatable {
  const NotificationsState({
    this.status = LoadStatus.initial,
    this.page,
    this.settings,
    this.failure,
    this.savingSettings = false,
  });

  final LoadStatus status;
  final NotificationPage? page;
  final NotificationSettings? settings;
  final Failure? failure;
  final bool savingSettings;

  int get unread => page?.unread ?? 0;

  @override
  List<Object?> get props => [status, page, settings, failure, savingSettings];
}

class NotificationsBloc extends Bloc<NotificationsEvent, NotificationsState> {
  NotificationsBloc(this._repo) : super(const NotificationsState()) {
    on<NotificationsLoadRequested>((_, emit) => _load(emit));
    on<NotificationsRefreshed>((_, emit) => _load(emit));
    on<NotificationReadRequested>(_onRead);
    on<NotificationsReadAllRequested>(_onReadAll);
    on<NotificationSettingToggled>(_onToggle);
  }

  final EssRepository _repo;

  Future<void> _load(Emitter<NotificationsState> emit) async {
    emit(NotificationsState(status: LoadStatus.loading, page: state.page, settings: state.settings));
    try {
      final page = await _repo.notifications();
      NotificationSettings? settings = state.settings;
      try {
        settings = await _repo.notificationSettings();
      } on Failure {
        // The list is the important read; settings can fail on their own.
      }
      emit(NotificationsState(
        status: page.notifications.isEmpty ? LoadStatus.empty : LoadStatus.success,
        page: page,
        settings: settings,
      ));
    } on Failure catch (f) {
      emit(NotificationsState(status: LoadStatus.failure, failure: f, settings: state.settings));
    }
  }

  Future<void> _onRead(NotificationReadRequested e, Emitter<NotificationsState> emit) async {
    final page = state.page;
    if (page == null) return;
    final list = [
      for (final n in page.notifications)
        n.id == e.id && n.unread
            ? AppNotification(
                id: n.id,
                category: n.category,
                title: n.title,
                body: n.body,
                data: n.data,
                readAt: DateTime.now(),
                createdAt: n.createdAt,
              )
            : n,
    ];
    final unread = list.where((n) => n.unread).length;
    emit(NotificationsState(
      status: state.status,
      page: NotificationPage(notifications: list, unread: unread, truncated: page.truncated),
      settings: state.settings,
    ));
    try {
      await _repo.readNotification(e.id);
    } on Failure {
      // The optimistic tick stays; the next refresh settles it.
    }
  }

  Future<void> _onReadAll(_, Emitter<NotificationsState> emit) async {
    final page = state.page;
    if (page == null) return;
    final now = DateTime.now();
    final list = [
      for (final n in page.notifications)
        n.unread
            ? AppNotification(
                id: n.id, category: n.category, title: n.title, body: n.body, data: n.data, readAt: now, createdAt: n.createdAt)
            : n,
    ];
    emit(NotificationsState(
      status: state.status,
      page: NotificationPage(notifications: list, unread: 0, truncated: page.truncated),
      settings: state.settings,
    ));
    try {
      await _repo.readAllNotifications();
    } on Failure {
      // Next refresh settles it.
    }
  }

  Future<void> _onToggle(NotificationSettingToggled e, Emitter<NotificationsState> emit) async {
    final settings = state.settings;
    if (settings == null) return;
    final disabled = settings.disabled.toSet();
    if (e.enabled) {
      disabled.remove(e.category);
    } else {
      disabled.add(e.category);
    }
    emit(NotificationsState(
      status: state.status,
      page: state.page,
      settings: NotificationSettings(categories: settings.categories, quietFrom: settings.quietFrom, quietTo: settings.quietTo),
      savingSettings: true,
    ));
    try {
      final saved = await _repo.saveNotificationSettings(disabled.toList());
      emit(NotificationsState(status: state.status, page: state.page, settings: saved));
    } on Failure catch (f) {
      emit(NotificationsState(status: state.status, page: state.page, settings: settings, failure: f));
    }
  }
}
