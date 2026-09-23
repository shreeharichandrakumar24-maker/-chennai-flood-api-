/// Distinct error type for backend failures.
///
/// Separates "fetch failed" (connection/timeout/server error) from
/// "never fetched / no data yet" so the UI never shows the same
/// state for both.
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final bool isConnectionError;

  const ApiException(
    this.message, {
    this.statusCode,
    this.isConnectionError = false,
  });

  @override
  String toString() =>
      'ApiException: $message${statusCode != null ? ' (HTTP $statusCode)' : ''}';
}
