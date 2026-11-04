class LicenseMode {
  const LicenseMode._();

  static const String current =
      String.fromEnvironment('LICENSE_MODE', defaultValue: 'lan');
  static const String defaultServer =
      String.fromEnvironment('LICENSE_DEFAULT_SERVER');

  static bool get isLan => current.toLowerCase() == 'lan';
}
