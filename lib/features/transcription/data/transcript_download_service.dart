import 'dart:io';
import 'dart:typed_data';

import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/errors/app_exception.dart';

class TranscriptDownloadService {
  Future<String> saveAndOpen({
    required String meetingId,
    required String source,
    required Uint8List bytes,
  }) async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(root.path, 'transcripts'));
    await directory.create(recursive: true);

    final file = File(
      p.join(
        directory.path,
        '${_safeFileName(meetingId)}_${_safeFileName(source)}_transcript.txt',
      ),
    );
    await file.writeAsBytes(bytes, flush: true);

    final result = await OpenFilex.open(file.path, type: 'text/plain');
    if (result.type != ResultType.done) {
      throw AppException('전사문을 열 수 없습니다: ${result.message}');
    }
    return file.path;
  }

  String _safeFileName(String value) {
    final safe = value.trim().replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    return safe.isEmpty ? 'meeting' : safe;
  }
}
