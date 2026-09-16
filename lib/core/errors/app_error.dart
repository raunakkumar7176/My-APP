sealed class AppError implements Exception {
  const AppError({required this.message, this.stackTrace});

  final String message;
  final StackTrace? stackTrace;

  @override
  String toString() => 'AppError: $message';
}

final class NetworkError extends AppError {
  const NetworkError({required super.message, super.stackTrace});
}

final class AuthError extends AppError {
  const AuthError({required super.message, super.stackTrace});
}

final class DataError extends AppError {
  const DataError({required super.message, super.stackTrace});
}

final class ValidationError extends AppError {
  const ValidationError({required super.message, super.stackTrace});
}

final class UnknownError extends AppError {
  const UnknownError({required super.message, super.stackTrace});
}
