class AppVersion implements Comparable<AppVersion> {
  const AppVersion._(this.text, this.major, this.minor, this.patch, this.beta);

  final String text;
  final int major;
  final int minor;
  final int patch;
  final int? beta;

  static AppVersion? tryParse(String value) {
    final text = value
        .trim()
        .replaceFirst(RegExp(r'^[vV]'), '')
        .split('+')
        .first;
    final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)(?:-beta([1-9]\d*))?$')
        .firstMatch(text);
    if (match == null) return null;
    return AppVersion._(
      text,
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
      match[4] == null ? null : int.parse(match[4]!),
    );
  }

  @override
  int compareTo(AppVersion other) {
    for (final pair in [
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
    ]) {
      final result = pair.$1.compareTo(pair.$2);
      if (result != 0) return result;
    }
    if (beta == null) return other.beta == null ? 0 : 1;
    if (other.beta == null) return -1;
    return beta!.compareTo(other.beta!);
  }
}

class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.url,
    required this.size,
    this.digest,
  });

  final String name;
  final Uri url;
  final int size;
  final String? digest;

  factory ReleaseAsset.fromJson(Map<String, dynamic> json) => ReleaseAsset(
    name: json['name'] as String,
    url: Uri.parse(json['browser_download_url'] as String),
    size: json['size'] as int,
    digest: json['digest'] as String?,
  );
}

class AppRelease {
  const AppRelease({
    required this.version,
    required this.url,
    required this.notes,
    required this.assets,
    this.publishedAt,
  });

  final AppVersion version;
  final Uri url;
  final String notes;
  final DateTime? publishedAt;
  final List<ReleaseAsset> assets;

  factory AppRelease.fromJson(Map<String, dynamic> json, AppVersion version) =>
      AppRelease(
        version: version,
        url: Uri.parse(json['html_url'] as String),
        notes: json['body'] as String? ?? '',
        publishedAt: DateTime.tryParse(json['published_at'] as String? ?? ''),
        assets: (json['assets'] as List<dynamic>)
            .map(
              (asset) => ReleaseAsset.fromJson(asset as Map<String, dynamic>),
            )
            .toList(),
      );

  ReleaseAsset? _asset(String suffix) {
    final name = 'Reelva-${version.text}-$suffix';
    for (final asset in assets) {
      if (asset.name == name) return asset;
    }
    return null;
  }

  static String? androidAbi(List<String> supportedAbis) {
    for (final abi in supportedAbis) {
      if (const ['arm64-v8a', 'armeabi-v7a', 'x86_64'].contains(abi)) {
        return abi;
      }
    }
    return null;
  }

  ReleaseAsset? androidApk(List<String> supportedAbis) {
    final abi = androidAbi(supportedAbis);
    return abi == null ? null : _asset('android-$abi.apk');
  }

  ReleaseAsset? get windowsInstaller => _asset('windows-x64-installer.exe');
  ReleaseAsset? get windowsPortable => _asset('windows-x64.zip');
}
