import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LicensePackageKind { windows, android }

class LicensePackageStore {
  const LicensePackageStore(
    this._preferences, {
    this.supportDirectory,
    this.executableDirectory,
  });

  final SharedPreferences _preferences;
  final Directory? supportDirectory;
  final String? executableDirectory;

  static const windowsFileName = 'MastterSystemCliente_Windows.zip';
  static const androidFileName = 'MastterSystemCliente.apk';
  static const _windowsKey = 'license_admin_package_windows';
  static const _androidKey = 'license_admin_package_android';

  String fileName(LicensePackageKind kind) => switch (kind) {
        LicensePackageKind.windows => windowsFileName,
        LicensePackageKind.android => androidFileName,
      };

  String label(LicensePackageKind kind) => switch (kind) {
        LicensePackageKind.windows => 'Cliente Windows (EXE / ZIP)',
        LicensePackageKind.android => 'Cliente Android (APK)',
      };

  String? extensionError(LicensePackageKind kind, String path) {
    final extension = _extension(path);
    final valid = switch (kind) {
      LicensePackageKind.windows => const {'.exe', '.zip'}.contains(extension),
      LicensePackageKind.android => extension == '.apk',
    };
    return valid
        ? null
        : kind == LicensePackageKind.windows
            ? 'Escolha o instalador EXE ou o ZIP completo do cliente Windows.'
            : 'Escolha o arquivo de instalação APK do Android.';
  }

  Future<String?> packagePath(LicensePackageKind kind) async {
    final saved = _preferences.getString(_key(kind));
    if (saved != null && await File(saved).exists()) return saved;

    final directory =
        executableDirectory ?? File(Platform.resolvedExecutable).parent.path;
    final base = '$directory${Platform.pathSeparator}data'
        '${Platform.pathSeparator}flutter_assets';
    for (final relative in [
      'assets${Platform.pathSeparator}admin_installers',
      'admin_installers',
    ]) {
      final bundled = File(
        '$base${Platform.pathSeparator}$relative'
        '${Platform.pathSeparator}${fileName(kind)}',
      );
      if (await bundled.exists()) {
        await _preferences.setString(_key(kind), bundled.path);
        return bundled.path;
      }
    }
    return null;
  }

  Future<String?> importPackage(
    LicensePackageKind kind,
    String sourcePath,
  ) async {
    final error = extensionError(kind, sourcePath);
    if (error != null) return error;
    final source = File(sourcePath);
    if (!await source.exists()) return 'O arquivo selecionado não existe.';
    final support = supportDirectory ?? await getApplicationSupportDirectory();
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}license_packages',
    );
    await directory.create(recursive: true);
    final storedName = kind == LicensePackageKind.windows
        ? 'MastterSystemCliente_Windows${_extension(sourcePath)}'
        : fileName(kind);
    final destination = File(
      '${directory.path}${Platform.pathSeparator}$storedName',
    );
    final sourceAbsolute = source.absolute.path;
    final destinationAbsolute = destination.absolute.path;
    if (sourceAbsolute.toLowerCase() != destinationAbsolute.toLowerCase()) {
      await source.copy(destination.path);
    }
    final saved = await _preferences.setString(_key(kind), destination.path);
    if (!saved) return 'Não foi possível salvar o caminho do pacote.';
    return null;
  }

  Future<String?> exportPackage(
    LicensePackageKind kind,
    String destinationPath,
  ) async {
    final sourcePath = await packagePath(kind);
    if (sourcePath == null) {
      return 'Cadastre primeiro o pacote deste aplicativo.';
    }
    if (sourcePath.toLowerCase() == destinationPath.toLowerCase()) return null;
    await File(sourcePath).copy(destinationPath);
    return null;
  }

  String _key(LicensePackageKind kind) => switch (kind) {
        LicensePackageKind.windows => _windowsKey,
        LicensePackageKind.android => _androidKey,
      };

  static String _extension(String value) {
    final name = value.split(RegExp(r'[\\/]')).last;
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot).toLowerCase();
  }
}
