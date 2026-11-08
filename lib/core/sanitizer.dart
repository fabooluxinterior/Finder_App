/// Client-side contact-info filter. Mirrors `public.contains_contact_info`
/// in the database so violations are caught before a round trip.
class ContactSanitizer {
  ContactSanitizer._();

  static final _phone = RegExp(r'\+?\d[\d\s\-().]{7,}\d');
  static final _handle = RegExp(r'(^|[^A-Za-z0-9_])@[A-Za-z0-9_.]{2,}');
  static final _url = RegExp(r'(https?://|www\.)\S+', caseSensitive: false);
  static final _domain = RegExp(r'\b[a-z0-9-]+\.(com|in|net|org|io|me|co|app|link|ly|gg|xyz)(/\S*)?\b', caseSensitive: false);

  /// Spelled-out platform invitations ("my insta is ...", "snap me").
  static final _platform = RegExp(
    r'\b(insta(gram)?|snap(chat)?|whats\s?app|telegram|ig)\b\s*(id|handle|is|:|-)\s*:?\s*[A-Za-z0-9_.]{3,}',
    caseSensitive: false,
  );

  static const _mask = '•••';

  static bool containsContactInfo(String text) =>
      _phone.hasMatch(text) ||
      _handle.hasMatch(text) ||
      _url.hasMatch(text) ||
      _domain.hasMatch(text) ||
      _platform.hasMatch(text);

  /// Strips contact info and collapses leftover whitespace.
  static String sanitize(String text) {
    var out = text
        .replaceAll(_url, _mask)
        .replaceAll(_domain, _mask)
        .replaceAll(_platform, _mask)
        .replaceAll(_phone, _mask)
        .replaceAllMapped(_handle, (m) => '${m.group(1)}$_mask');
    out = out.replaceAll(RegExp(r'[ \t]{2,}'), ' ').trim();
    return out;
  }
}
