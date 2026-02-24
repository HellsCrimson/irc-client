import 'dart:io';
import 'dart:typed_data';

String normalizedSha1(X509Certificate cert) {
  final Uint8List digest = cert.sha1;
  return _toHex(digest);
}

String normalizedFingerprint(String raw) {
  return raw.replaceAll(RegExp(r'[^a-fA-F0-9]'), '').toLowerCase();
}

String _toHex(Uint8List bytes) {
  final StringBuffer buffer = StringBuffer();
  for (final int byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString().toLowerCase();
}
