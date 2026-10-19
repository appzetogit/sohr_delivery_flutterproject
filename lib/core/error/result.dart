import 'package:freezed_annotation/freezed_annotation.dart';

part 'result.freezed.dart';

@freezed
class Result<T, E> with _$Result<T, E> {
  const factory Result.success(T data) = _Success;
  const factory Result.failure(E error) = _Failure;
}

// Common application error classes
abstract class AppError {
  final String message;
  AppError(this.message);
}

class NetworkError extends AppError {
  NetworkError(super.message);
}

class DatabaseError extends AppError {
  DatabaseError(super.message);
}

class UnknownError extends AppError {
  UnknownError(super.message);
}

/// Going online was refused because the wallet is under the admin's minimum.
/// Its own type so the UI can answer with the top-up dialog instead of a
/// generic snackbar — every other availability failure is still a snackbar.
class WalletBlockedError extends AppError {
  WalletBlockedError(super.message);
}
