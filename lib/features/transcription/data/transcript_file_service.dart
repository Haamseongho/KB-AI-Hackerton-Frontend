import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../meetings/domain/transcript_segment.dart';

/// 최종 transcript segment를 앱 문서 디렉터리의 txt 파일로 저장하는 서비스입니다.
///
/// 실시간 STT 스트림과 로컬 파일 저장은 분리해서 다룹니다. WebSocket에서 받은
/// final transcript를 누적한 뒤, 사용자가 회의방을 나갈 때 재조회 가능한 파일로
/// 남기는 역할만 담당합니다.
class TranscriptFileService {
  /// 회의 ID와 final segment 목록을 기반으로 transcript txt 파일을 생성합니다.
  Future<String?> saveTranscript({
    required String meetingId,
    required String title,
    required List<TranscriptSegment> segments,
  }) async {
    if (segments.isEmpty) return null;

    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(root.path, 'transcripts'));
    await directory.create(recursive: true);

    final file = File(
      p.join(directory.path, '${_safeFileName(meetingId)}_transcript.txt'),
    );
    await file.writeAsString(_formatTranscript(title, meetingId, segments));
    return file.path;
  }

  String _formatTranscript(
    String title,
    String meetingId,
    List<TranscriptSegment> segments,
  ) {
    final buffer = StringBuffer()
      ..writeln(title)
      ..writeln(meetingId)
      ..writeln();

    for (final segment in segments) {
      buffer
        ..write('[${_time(segment.startedAt)}] ')
        ..write('${segment.speaker ?? '화자 1'}: ')
        ..writeln(segment.text)
        ..writeln();
    }

    return buffer.toString();
  }

  String _time(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  String _safeFileName(String value) {
    return value.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
  }
}
