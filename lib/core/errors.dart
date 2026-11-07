class AppException implements Exception {
  const AppException(this.code, this.message);

  final AppErrorCode code;
  final String message;

  @override
  String toString() => message;
}

enum AppErrorCode { swipeLimit, premiumRequired, notConnected, contactInfo, network, unknown }
