import 'package:core_network/core_network.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'theme_local_store.dart';
import 'theme_preference.dart';
import 'theme_preferences_repository.dart';

@immutable
class ThemeState extends Equatable {
  const ThemeState({
    this.choice = ThemeChoice.system,
    this.open = false,
    this.mode = ThemeMode.light,
    this.loaded = false,
    this.saving = false,
    this.pendingSave = false,
  });

  /// The person's saved choice. Only meaningful while [open] is true.
  final ThemeChoice choice;

  /// Whether the `theme` switch is open to this person.
  final bool open;

  /// What `MaterialApp` should use. Always [ThemeMode.light] while closed.
  final ThemeMode mode;

  /// Whether a server/local answer has been applied at least once.
  final bool loaded;

  final bool saving;

  /// A save failed for a reason that may heal (offline); retry on resume.
  final bool pendingSave;

  ThemeState copyWith({
    ThemeChoice? choice,
    bool? open,
    ThemeMode? mode,
    bool? loaded,
    bool? saving,
    bool? pendingSave,
  }) {
    return ThemeState(
      choice: choice ?? this.choice,
      open: open ?? this.open,
      mode: mode ?? this.mode,
      loaded: loaded ?? this.loaded,
      saving: saving ?? this.saving,
      pendingSave: pendingSave ?? this.pendingSave,
    );
  }

  @override
  List<Object?> get props => [choice, open, mode, loaded, saving, pendingSave];
}

/// Owns the app's Light/Dark/System choice.
///
/// Rules from #121:
///  * a local cache paints the right theme before the network answers;
///  * the server decides whether the switch is open; while closed, Light wins;
///  * a change applies immediately and is saved with one Idempotency-Key;
///  * an offline save stays on the phone and is retried on resume;
///  * sign-out returns the app to Light.
class ThemeCubit extends Cubit<ThemeState> {
  ThemeCubit({
    required ThemePreferencesRepository repository,
    required ThemeLocalStore localStore,
  })  : _repository = repository,
        _localStore = localStore,
        super(const ThemeState());

  final ThemePreferencesRepository _repository;
  final ThemeLocalStore _localStore;

  bool _loading = false;
  String? _pendingKey;

  /// Called on sign-in and on the first frame. Reads the cache, then the server.
  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    try {
      final cached = await _localStore.read();
      if (cached != null && cached.open) {
        _emitPreference(cached, loaded: state.loaded);
      } else if (cached != null) {
        _emitClosed();
      }
      await _fetch();
    } finally {
      _loading = false;
    }
  }

  /// Called when the app returns to the foreground.
  Future<void> resume() async {
    if (state.pendingSave) {
      // Retry the save first. A successful save is authoritative, so do not
      // immediately overwrite it with a GET that may still answer the old value.
      await _saveCurrent();
      if (!state.pendingSave) return;
      return;
    }
    await _fetch();
  }

  /// Picks a new appearance. Applies at once, then saves.
  Future<void> select(ThemeChoice choice) async {
    if (!state.open || state.saving) return;

    _pendingKey ??= IdempotencyInterceptor.newKey();
    emit(state.copyWith(
      choice: choice,
      mode: choice.mode,
      saving: true,
      pendingSave: false,
      loaded: true,
    ));
    await _localStore.write(ThemePreference(choice: choice, open: true));
    await _saveCurrent();
  }

  /// Sign-out returns the app to Light and forgets the cached choice, so the
  /// next person on this phone gets their own server answer.
  Future<void> signOut() async {
    _pendingKey = null;
    await _localStore.clear();
    emit(const ThemeState(loaded: true));
  }

  Future<void> _saveCurrent() async {
    final choice = state.choice;
    _pendingKey ??= IdempotencyInterceptor.newKey();
    final key = _pendingKey!;
    emit(state.copyWith(saving: true, pendingSave: false));
    try {
      final saved =
          await _repository.save(choice, idempotencyKey: key);
      _pendingKey = null;
      if (!saved.open) {
        await _localStore.clear();
        _emitClosed();
        return;
      }
      await _localStore.write(saved);
      _emitPreference(saved, loaded: true);
    } on NotFoundFailure {
      // The switch closed under us, or the backend is not ready: roll back.
      _pendingKey = null;
      await _localStore.clear();
      _emitClosed();
    } on ForbiddenFailure {
      _pendingKey = null;
      await _localStore.clear();
      _emitClosed();
    } on Failure {
      // Keep the local choice; an offline save is retried on the next resume.
      emit(state.copyWith(
        saving: false,
        pendingSave: true,
        loaded: true,
      ));
    }
  }

  Future<void> _fetch() async {
    try {
      final pref = await _repository.load();
      if (!pref.open) {
        await _localStore.clear();
        _emitClosed();
        return;
      }
      await _localStore.write(pref);
      _emitPreference(pref, loaded: true);
    } on NotFoundFailure {
      await _localStore.clear();
      _emitClosed();
    } on ForbiddenFailure {
      await _localStore.clear();
      _emitClosed();
    } on Failure {
      // Offline or a server error: keep the cached choice; do not sign out and
      // do not show an error loop. The next resume asks again.
      emit(state.copyWith(loaded: true));
    }
  }

  void _emitPreference(ThemePreference pref, {required bool loaded}) {
    emit(state.copyWith(
      choice: pref.choice,
      open: pref.open,
      mode: pref.open ? pref.choice.mode : ThemeMode.light,
      loaded: loaded,
      saving: false,
      pendingSave: false,
    ));
  }

  void _emitClosed() {
    emit(state.copyWith(
      choice: ThemeChoice.light,
      open: false,
      mode: ThemeMode.light,
      loaded: true,
      saving: false,
      pendingSave: false,
    ));
  }
}
