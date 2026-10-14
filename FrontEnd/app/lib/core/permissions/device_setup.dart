enum DeviceSettingsAction { appSettings, locationSettings }

/// A missing device permission or service, independent of any feature.
class DeviceSetupException implements Exception {
  const DeviceSetupException(this.message, {this.action});
  final String message;
  final DeviceSettingsAction? action;
  @override
  String toString() => message;
}
