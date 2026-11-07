/// Authorization headers for the media delivery function. Images are never
/// served from public or signed storage URLs: every request carries the
/// user's short-lived access token and is authorised server-side, so a
/// copied image link is useless on its own.
class MediaAuth {
  MediaAuth._();
  static String? baseUrl;
  static Map<String, String> Function()? headers;

  static bool isMediaUrl(String url) => baseUrl != null && url.startsWith(baseUrl!);
}
