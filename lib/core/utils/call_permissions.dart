import 'package:permission_handler/permission_handler.dart';

/// Thrown when the user has not granted camera/microphone access.
///
/// The Daily SDK does NOT request runtime permissions for you — it assumes
/// they are already granted before `CallClient.create()` / `join()` runs.
/// Touching the camera without them crashes the native layer on Android and
/// hard-aborts on iOS, which is why this check has to happen *first*.
class CallPermissionException implements Exception {
  CallPermissionException(this.message, {this.permanentlyDenied = false});

  final String message;

  /// True when the user picked "Don't ask again" / denied in iOS Settings.
  /// The only way forward is the system settings page.
  final bool permanentlyDenied;

  @override
  String toString() => message;
}

class CallPermissions {
  const CallPermissions._();

  /// Requests camera + microphone together and throws a
  /// [CallPermissionException] if either is missing.
  ///
  /// Call this BEFORE creating a Daily CallClient. Always.
  static Future<void> ensureGranted() async {
    final statuses = await [
      Permission.camera,
      Permission.microphone,
    ].request();

    final camera = statuses[Permission.camera] ?? PermissionStatus.denied;
    final mic = statuses[Permission.microphone] ?? PermissionStatus.denied;

    if (camera.isGranted && mic.isGranted) {
      return;
    }

    final missing = <String>[
      if (!camera.isGranted) 'camera',
      if (!mic.isGranted) 'microphone',
    ].join(' and ');

    final permanentlyDenied =
        camera.isPermanentlyDenied || mic.isPermanentlyDenied;

    throw CallPermissionException(
      permanentlyDenied
          ? 'Clarastudy needs $missing access to run a live class. '
              'Turn it on in your phone settings, then try again.'
          : 'Clarastudy needs $missing access to run a live class.',
      permanentlyDenied: permanentlyDenied,
    );
  }

  /// Opens the OS settings page so the user can flip a permanently
  /// denied permission back on.
  static Future<void> openSettings() => openAppSettings();
}
