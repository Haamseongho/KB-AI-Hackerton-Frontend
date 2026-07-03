import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

class MicrophonePermissionService {
  /// 녹음에 필수인 마이크 권한을 요청하고 Android 알림 권한도 함께 확인합니다.
  ///
  /// Android 13 이상의 foreground recording 알림은 사용자에게 녹음 상태를
  /// 명확히 보여주기 위한 권한입니다. 알림 권한 거부는 마이크 녹음 자체를
  /// 차단하지 않으므로 반환값에는 마이크 권한 결과만 반영합니다.
  Future<bool> ensureGranted() async {
    final status = await Permission.microphone.status;
    final microphoneGranted = status.isGranted
        ? true
        : (await Permission.microphone.request()).isGranted;

    if (microphoneGranted && Platform.isAndroid) {
      final notificationStatus = await Permission.notification.status;
      if (notificationStatus.isDenied) {
        await Permission.notification.request();
      }
    }

    return microphoneGranted;
  }
}
