import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/connection_manager.dart';

/// Persists server profiles (in a JSON list) and their bearer tokens
/// (individually, keyed by profile id) in the platform secure store.
class SettingsRepository {
  SettingsRepository({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _profilesKey = 'server_profiles';
  static const _tokenPrefix = 'token_';
  static const _lastProfileKey = 'last_profile_id';

  Future<List<ServerProfile>> loadProfiles() async {
    final raw = await _storage.read(key: _profilesKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    final profiles = <ServerProfile>[];
    for (final entry in decoded) {
      if (entry is Map<String, dynamic>) {
        final id = entry['id'] as String?;
        final token = id != null
            ? await _storage.read(key: '$_tokenPrefix$id')
            : null;
        profiles.add(ServerProfile.fromJson(entry, token: token));
      }
    }
    return profiles;
  }

  Future<void> saveProfile(ServerProfile profile) async {
    final profiles = await loadProfiles();
    final idx = profiles.indexWhere((p) => p.id == profile.id);
    if (idx >= 0) {
      profiles[idx] = profile;
    } else {
      profiles.add(profile);
    }
    await _persist(profiles);
    if (profile.bearerToken != null && profile.bearerToken!.isNotEmpty) {
      await _storage.write(
        key: '$_tokenPrefix${profile.id}',
        value: profile.bearerToken,
      );
    } else {
      await _storage.delete(key: '$_tokenPrefix${profile.id}');
    }
  }

  Future<void> deleteProfile(String id) async {
    final profiles = await loadProfiles();
    profiles.removeWhere((p) => p.id == id);
    await _persist(profiles);
    await _storage.delete(key: '$_tokenPrefix$id');
  }

  Future<void> _persist(List<ServerProfile> profiles) async {
    final json = jsonEncode(profiles.map((p) => p.toJson()).toList());
    await _storage.write(key: _profilesKey, value: json);
  }

  Future<String?> lastProfileId() => _storage.read(key: _lastProfileKey);

  Future<void> setLastProfileId(String id) =>
      _storage.write(key: _lastProfileKey, value: id);

  /// Loads the most recently used profile, including its token from secure
  /// storage. Falls back to the newest saved profile for installations created
  /// before the last-profile key existed.
  Future<ServerProfile?> loadLastProfile() async {
    final profiles = await loadProfiles();
    if (profiles.isEmpty) return null;
    final lastId = await lastProfileId();
    if (lastId != null) {
      for (final profile in profiles) {
        if (profile.id == lastId) return profile;
      }
    }
    return profiles.last;
  }

  /// Persists a profile and marks it as the one restored on the next launch.
  Future<void> saveLastProfile(ServerProfile profile) async {
    await saveProfile(profile);
    await setLastProfileId(profile.id);
  }
}
