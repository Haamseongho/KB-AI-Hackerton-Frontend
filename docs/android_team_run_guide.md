# Android Team Run Guide

이 문서는 팀원이 Android Studio IDE를 직접 사용하지 않고 VSCode/터미널에서 Flutter Android 앱을 실행하는 절차를 정리합니다.

## Backend Endpoint

현재 Flutter 기본값은 EC2 dev backend입니다.

```text
API_BASE_URL=http://13.124.81.217:8080
WS_BASE_URL=ws://13.124.81.217:8080
```

스크립트도 같은 값을 `--dart-define`으로 명시합니다.

## 공통 준비

1. Flutter SDK 설치
   - <https://docs.flutter.dev/get-started/install>
   - `flutter doctor`가 실행되어야 합니다.

2. Android SDK / platform-tools 준비
   - 가장 쉬운 방법은 Android Studio를 한 번 설치해 SDK만 세팅하고, 개발은 VSCode를 쓰는 방식입니다.
   - Android Studio를 쓰지 않으려면 Android command-line tools와 `platform-tools`를 직접 설치해야 합니다.
   - `adb devices`가 실행되어야 합니다.

3. Android 기기 설정
   - 개발자 옵션 활성화
   - USB 디버깅 활성화
   - USB 연결 후 RSA fingerprint 허용

4. VSCode 확장
   - Flutter
   - Dart

## macOS 실행

```bash
flutter doctor
flutter pub get
./scripts/run_android_ec2.sh
```

여러 Android 기기가 연결되어 있으면 device id를 넘깁니다.

```bash
./scripts/run_android_ec2.sh <device-id>
```

기기 목록 확인:

```bash
flutter devices
```

디버그 APK만 빌드하려면:

```bash
./scripts/build_android_debug_apk_ec2.sh
```

결과물:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

## Windows PowerShell 실행

PowerShell에서:

```powershell
flutter doctor
flutter pub get
.\scripts\run_android_ec2.ps1
```

여러 Android 기기가 연결되어 있으면 device id를 넘깁니다.

```powershell
.\scripts\run_android_ec2.ps1 -DeviceId "<device-id>"
```

디버그 APK만 빌드하려면:

```powershell
.\scripts\build_android_debug_apk_ec2.ps1
```

## VSCode에서 실행

1. VSCode로 프로젝트 루트를 엽니다.
2. Android 기기를 USB로 연결합니다.
3. 하단 device selector에서 Android 기기를 선택합니다.
4. 터미널에서 `flutter pub get` 실행 후 `F5` 또는 `flutter run`을 실행합니다.

현재 `lib/core/config/app_config.dart` 기본값이 EC2로 설정되어 있어서 VSCode에서 별도 `--dart-define` 없이도 EC2 backend를 봅니다.

## 확인 시나리오

1. 앱 실행
2. `New Room` 생성
3. 방 진입 후 `Record`
4. Android 마이크 권한 허용
5. 실시간 transcript 표시 확인
6. `Pause` 후 다시 `Record` 확인
7. `Leave`로 transcript/recording 저장
8. `Minutes`로 `/minutes-from-realtime` 호출
9. S3 회의록 산출물 생성 여부 확인

## 자주 막히는 부분

- `flutter doctor`에서 Android toolchain 실패
  - Android SDK 경로와 command-line tools 설치 상태를 확인합니다.
- `adb devices`에 기기가 `unauthorized`
  - Android 기기에서 USB 디버깅 RSA 허용 팝업을 승인합니다.
- 앱에서 녹음이 안 됨
  - Android 앱 권한에서 마이크 권한을 허용합니다.
- WebSocket 연결 실패
  - PC/기기 네트워크가 외부 EC2 `13.124.81.217:8080`에 접근 가능한지 확인합니다.
  - 브라우저에서 `http://13.124.81.217:8080/docs` 접속을 먼저 확인합니다.
