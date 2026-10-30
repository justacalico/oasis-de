class UpdateAsset {
  final String name;
  final String url;
  final String? checksumUrl;

  const UpdateAsset({
    required this.name,
    required this.url,
    this.checksumUrl,
  });

  bool get verifiable => checksumUrl != null;

  @override
  bool operator ==(Object other) =>
      other is UpdateAsset &&
      other.name == name &&
      other.url == url &&
      other.checksumUrl == checksumUrl;

  @override
  int get hashCode => Object.hash(name, url, checksumUrl);
}

class AppUpdate {
  final String currentVersion;
  final String latestVersion;
  final bool updateAvailable;
  final String releaseUrl;
  final UpdateAsset? asset;

  const AppUpdate({
    this.currentVersion = '',
    this.latestVersion = '',
    this.updateAvailable = false,
    this.releaseUrl = '',
    this.asset,
  });

  @override
  bool operator ==(Object other) =>
      other is AppUpdate &&
      other.currentVersion == currentVersion &&
      other.latestVersion == latestVersion &&
      other.updateAvailable == updateAvailable &&
      other.releaseUrl == releaseUrl &&
      other.asset == asset;

  @override
  int get hashCode => Object.hash(
        currentVersion,
        latestVersion,
        updateAvailable,
        releaseUrl,
        asset,
      );
}
