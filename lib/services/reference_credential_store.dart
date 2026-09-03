import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/app_settings.dart';

abstract interface class SecureCredentialBackend {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterSecureCredentialBackend implements SecureCredentialBackend {
  const FlutterSecureCredentialBackend({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class ReferenceCredentialStore {
  ReferenceCredentialStore({SecureCredentialBackend? backend})
    : _backend = backend ?? const FlutterSecureCredentialBackend();

  final SecureCredentialBackend _backend;

  Future<String?> readToken(AppSettings settings) async {
    final token = await _backend.read(_key(settings));
    return token == null || token.isEmpty ? null : token;
  }

  Future<void> writeToken(AppSettings settings, String token) async {
    final normalized = token.trim();
    if (!isValidReferenceToken(normalized)) {
      throw const FormatException(
        'Management token must contain at least 32 letters, digits, - or _.',
      );
    }
    await _backend.write(_key(settings), normalized);
  }

  Future<void> deleteToken(AppSettings settings) =>
      _backend.delete(_key(settings));

  static String _key(AppSettings settings) {
    final uri = _baseUri(settings.detectorBaseUrl);
    final origin = '${uri.scheme}://${uri.host}:${uri.port}';
    return 'catcheye.reference.token.'
        '${base64Url.encode(utf8.encode(origin)).replaceAll('=', '')}';
  }
}

bool isValidReferenceToken(String token) =>
    RegExp(r'^[A-Za-z0-9_-]{32,256}$').hasMatch(token);

Uri _baseUri(String value) {
  final trimmed = value.trim();
  return Uri.parse(
    trimmed.startsWith('http://') || trimmed.startsWith('https://')
        ? trimmed
        : 'http://$trimmed',
  );
}
