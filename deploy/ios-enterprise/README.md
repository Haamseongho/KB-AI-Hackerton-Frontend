# VoiceDoc iOS Enterprise OTA 배포 파일

이 폴더는 Apple Enterprise 인증서로 서명한 iOS `.ipa`를 S3에 올려 Safari에서 설치하기 위한 정적 파일 템플릿입니다.

## 포함 파일

- `install.html`: iPhone Safari에서 여는 설치 페이지
- `manifest.plist`: Apple OTA 설치 manifest

## S3 업로드 예시

최종 S3 prefix 예시:

```text
s3://YOUR_BUCKET/ios-enterprise/
```

업로드할 객체:

```text
install.html
manifest.plist
VoiceDoc.ipa
icon-57.png
icon-512.png
```

## 배포 전 수정할 값

`manifest.plist`:

```text
https://YOUR_BUCKET.s3.YOUR_REGION.amazonaws.com/ios-enterprise/VoiceDoc.ipa
https://YOUR_BUCKET.s3.YOUR_REGION.amazonaws.com/ios-enterprise/icon-57.png
https://YOUR_BUCKET.s3.YOUR_REGION.amazonaws.com/ios-enterprise/icon-512.png
```

`install.html`의 `itms-services` 링크:

```text
https://YOUR_BUCKET.s3.YOUR_REGION.amazonaws.com/ios-enterprise/manifest.plist
```

HTML 안의 URL은 percent-encoding된 상태여야 합니다.

## MIME type

S3 객체 metadata는 다음처럼 설정하는 것이 안전합니다.

```text
install.html      text/html; charset=utf-8
manifest.plist    application/xml
VoiceDoc.ipa      application/octet-stream
icon-57.png       image/png
icon-512.png      image/png
```

## iOS 설치 조건

- 설치 페이지와 manifest, IPA URL은 iOS 기기에서 HTTPS로 접근 가능해야 합니다.
- IPA는 `com.kbds.aihackerthon.frontend` 번들 ID에 맞는 Enterprise 배포 프로비저닝 프로파일로 서명되어야 합니다.
- Enterprise 인증서는 대상 기기에서 신뢰되어야 합니다.
- S3 static website endpoint는 HTTP만 제공하므로 iOS OTA에는 S3 REST HTTPS endpoint 또는 CloudFront HTTPS URL을 사용하세요.
