import 'dart:io';

import 'package:core_bloc/core_bloc.dart';
import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rvm_team_app/data/datasources/me_remote_data_source.dart';
import 'package:rvm_team_app/data/repositories/me_repository.dart';
import 'package:rvm_team_app/features/me/bloc/account_action_bloc.dart';

/// Permanent regression for issues_image/issue13: first-install offline must
/// never show raw `SocketException: Failed host lookup …` in the dialog.
/// Every path resolves to a friendly typed message.
Dio _dnsFailingDio() {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) => handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.unknown,
          error: const SocketException(
            "Failed host lookup: 'gzgkhrqdiphx.supabase.co'",
            osError: OSError('No address associated with hostname', 7),
          ),
        ),
        true,
      ),
    ),
  );
  return dio;
}

MeRepository _repo() => MeRepository(
      remote: MeRemoteDataSource(_dnsFailingDio()),
      connectivity: ConnectivityService(probe: () async => true),
    );

Future<AccountActionState> _run(AccountActionEvent event) async {
  final bloc = AccountActionBloc(_repo());
  bloc.add(event);
  final state = await bloc.stream.firstWhere(
    (s) => s.status == WriteStatus.success || s.status == WriteStatus.failure,
  );
  await bloc.close();
  return state;
}

void main() {
  test('offline DNS on password change shows friendly line, never raw',
      () async {
    final state = await _run(const AccountChangePassword(
        oldPassword: 'old12345', newPassword: 'new12345'));
    expect(state.status, WriteStatus.failure);
    expect(state.error, isNotNull);
    expect(state.error, 'No internet connection');
    expect(state.error, isNot(contains('SocketException')));
    expect(state.error, isNot(contains('Failed host lookup')));
  });

  test('offline DNS on photo upload shows friendly line, never raw', () async {
    final state = await _run(
        const AccountUploadPhoto(bytes: [1, 2, 3], filename: 'a.jpg'));
    expect(state.status, WriteStatus.failure);
    expect(state.error, isNotNull);
    expect(state.error, isNot(contains('SocketException')));
  });
}
