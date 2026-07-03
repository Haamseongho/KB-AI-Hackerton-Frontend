import 'dart:io';
import 'dart:typed_data';

import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/errors/app_exception.dart';

/// 다운로드한 회의록 파일을 앱 문서 디렉터리에 저장하고 네이티브 뷰어로 엽니다.
class PdfDownloadService {
  /// PDF bytes를 `minutes` 디렉터리에 저장한 뒤 iOS/Android PDF 앱으로 엽니다.
  Future<String> saveAndOpen({
    required String meetingId,
    required String title,
    required List<int> bytes,
  }) async {
    if (bytes.isEmpty) {
      throw const AppException('다운로드한 PDF 파일이 비어 있습니다.');
    }

    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(root.path, 'minutes'));
    await directory.create(recursive: true);

    final file = File(
      p.join(directory.path, _minutesFileName(title, meetingId, 'pdf')),
    );
    await file.writeAsBytes(Uint8List.fromList(bytes), flush: true);

    final result = await OpenFilex.open(
      file.path,
      type: 'application/pdf',
      uti: 'com.adobe.pdf',
    );
    if (result.type != ResultType.done) {
      throw AppException('PDF를 열 수 없습니다: ${result.message}');
    }
    return file.path;
  }

  /// DOCX bytes를 `minutes` 디렉터리에 저장한 뒤 iOS/Android 문서 앱으로 엽니다.
  Future<String> saveDocxAndOpen({
    required String meetingId,
    required String title,
    required List<int> bytes,
  }) async {
    if (bytes.isEmpty) {
      throw const AppException('다운로드한 DOCX 파일이 비어 있습니다.');
    }

    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(root.path, 'minutes'));
    await directory.create(recursive: true);

    final file = File(
      p.join(directory.path, _minutesFileName(title, meetingId, 'docx')),
    );
    await file.writeAsBytes(Uint8List.fromList(bytes), flush: true);

    final result = await OpenFilex.open(
      file.path,
      type:
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      uti: 'org.openxmlformats.wordprocessingml.document',
    );
    if (result.type != ResultType.done) {
      throw AppException('DOCX를 열 수 없습니다: ${result.message}');
    }
    return file.path;
  }

  String _minutesFileName(String title, String meetingId, String extension) {
    final safeTitle = _safeFileName(title);
    final fallback = _safeFileName(meetingId);
    return '회의록-${safeTitle.isEmpty ? fallback : safeTitle}.$extension';
  }

  String _safeFileName(String value) {
    return value
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|\r\n\t]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
