import 'package:permission_handler/permission_handler.dart';

class MicrophonePermissionService {
  Future<bool> ensureGranted() async {
    final status = await Permission.microphone.status;
    if (status.isGranted) return true;

    final requested = await Permission.microphone.request();
    return requested.isGranted;
  }
}
