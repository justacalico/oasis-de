import 'dart:js_interop';

@JS('navigator.userAgent')
external String get _ua;

String? webUserAgent() => _ua;
