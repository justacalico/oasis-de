import 'dart:ui';

import '../update/app_update.dart';
import '../update/update_service.dart';

/// Every member of the host protocol. The in-process endpoint and remote
/// clients are both driven exclusively by these names and codecs, so the
/// two sides cannot drift apart. `host_contract_test.dart` fails if a
/// member is added here without a matching contract test.
const kOasisHostMethods = {
  'getState',
  'setThemeMode',
  'setAccent',
  'setLocale',
  'openUrl',
  'checkUpdates',
  'installUpdate',
};

const kOasisHostEvents = {'appearance', 'locale', 'updates'};

String? hostLocaleToTag(Locale? locale) => locale?.toLanguageTag();

Locale? hostLocaleFromTag(String? tag) {
  if (tag == null || tag.isEmpty) return null;
  final parts = tag.split(RegExp('[-_]'));
  String? script;
  String? country;
  for (var i = 1; i < parts.length; i++) {
    final p = parts[i];
    if (script == null && p.length == 4) {
      script = p;
    } else {
      country ??= p;
    }
  }
  return Locale.fromSubtags(
    languageCode: parts.first,
    scriptCode: script,
    countryCode: country,
  );
}

int? hostAccentToJson(Color? accent) => accent?.toARGB32();

Color? hostAccentFromJson(Object? value) =>
    value == null ? null : Color((value as num).toInt());

Map<String, Object?> hostAppUpdateToJson(AppUpdate update) => {
      'currentVersion': update.currentVersion,
      'latestVersion': update.latestVersion,
      'updateAvailable': update.updateAvailable,
      'releaseUrl': update.releaseUrl,
      'asset': update.asset == null
          ? null
          : {
              'name': update.asset!.name,
              'url': update.asset!.url,
              'checksumUrl': update.asset!.checksumUrl,
            },
    };

AppUpdate? hostAppUpdateFromJson(Object? json) {
  if (json == null) return null;
  final map = Map<String, Object?>.from(json as Map);
  return AppUpdate(
    currentVersion: map['currentVersion'] as String? ?? '',
    latestVersion: map['latestVersion'] as String? ?? '',
    updateAvailable: map['updateAvailable'] as bool? ?? false,
    releaseUrl: map['releaseUrl'] as String? ?? '',
    asset: hostUpdateAssetFromJson(map['asset']),
  );
}

UpdateAsset? hostUpdateAssetFromJson(Object? json) {
  if (json == null) return null;
  final map = Map<String, Object?>.from(json as Map);
  return UpdateAsset(
    name: map['name'] as String? ?? '',
    url: map['url'] as String? ?? '',
    checksumUrl: map['checksumUrl'] as String?,
  );
}

class OasisUpdateSnapshot {
  const OasisUpdateSnapshot({
    this.update,
    this.checking = false,
    this.failed = false,
    this.installing = false,
    this.installDone = false,
    this.installFailed = false,
    this.releasesPageUrl = '',
  });

  factory OasisUpdateSnapshot.of(OasisUpdateApi service) =>
      OasisUpdateSnapshot(
        update: service.update,
        checking: service.checking,
        failed: service.failed,
        installing: service.installing,
        installDone: service.installDone,
        installFailed: service.installFailed,
        releasesPageUrl: service.releasesPageUrl,
      );

  factory OasisUpdateSnapshot.fromJson(Map json) => OasisUpdateSnapshot(
        update: hostAppUpdateFromJson(json['update']),
        checking: json['checking'] as bool? ?? false,
        failed: json['failed'] as bool? ?? false,
        installing: json['installing'] as bool? ?? false,
        installDone: json['installDone'] as bool? ?? false,
        installFailed: json['installFailed'] as bool? ?? false,
        releasesPageUrl: json['releasesPageUrl'] as String? ?? '',
      );

  final AppUpdate? update;
  final bool checking;
  final bool failed;
  final bool installing;
  final bool installDone;
  final bool installFailed;
  final String releasesPageUrl;

  Map<String, Object?> toJson() => {
        'update':
            update == null ? null : hostAppUpdateToJson(update!),
        'checking': checking,
        'failed': failed,
        'installing': installing,
        'installDone': installDone,
        'installFailed': installFailed,
        'releasesPageUrl': releasesPageUrl,
      };

  @override
  bool operator ==(Object other) =>
      other is OasisUpdateSnapshot &&
      other.update == update &&
      other.checking == checking &&
      other.failed == failed &&
      other.installing == installing &&
      other.installDone == installDone &&
      other.installFailed == installFailed &&
      other.releasesPageUrl == releasesPageUrl;

  @override
  int get hashCode => Object.hash(
        update,
        checking,
        failed,
        installing,
        installDone,
        installFailed,
        releasesPageUrl,
      );
}
