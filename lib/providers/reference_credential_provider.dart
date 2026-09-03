import 'package:flutter/foundation.dart';

import '../models/app_settings.dart';
import '../services/reference_credential_store.dart';

class ReferenceCredentialProvider extends ChangeNotifier {
  ReferenceCredentialProvider({ReferenceCredentialStore? store})
    : _store = store ?? ReferenceCredentialStore();

  final ReferenceCredentialStore _store;
  int _revision = 0;

  int get revision => _revision;

  Future<String?> readToken(AppSettings settings) => _store.readToken(settings);

  Future<void> saveToken(AppSettings settings, String token) async {
    await _store.writeToken(settings, token);
    _revision++;
    notifyListeners();
  }

  Future<void> clearToken(AppSettings settings) async {
    await _store.deleteToken(settings);
    _revision++;
    notifyListeners();
  }
}
