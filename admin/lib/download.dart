// Saves a text file in the browser (CSV export). No-op outside the web.
export 'download_stub.dart' if (dart.library.js_interop) 'download_web.dart';
