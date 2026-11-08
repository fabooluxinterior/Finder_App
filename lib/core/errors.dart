class AppException implements Exception {
  const AppException(this.code, this.message);

  final AppErrorCode code;
  final String message;

  @override
  String toString() => message;
}

enum AppErrorCode {
  subscriptionRequired,
  notConnected,
  contactInfo,
  rateLimited,
  mfaRequired,
  deviceLimit,
  imageRejected,
  encryption,
  network,
  unknown,
}
