import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../../../core/errors/app_exception.dart';
import '../../meetings/domain/recording_asset.dart';

class AudioFilePickerService {
  Future<RecordingAsset?> pickAudioFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'm4a',
        'mp3',
        'mp4',
        'wav',
        'flac',
        'ogg',
        'amr',
        'webm',
      ],
      allowMultiple: false,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return null;

    final picked = result.files.single;
    final path = picked.path;
    if (path == null || path.isEmpty) {
      throw const AppException('선택한 파일의 경로를 확인할 수 없습니다.');
    }

    return RecordingAsset(
      fileName: picked.name,
      filePath: path,
      contentType: _contentTypeFor(p.extension(picked.name)),
      durationMs: 0,
      realtimeAudioEncoding: 'batch_file',
      realtimeSampleRate: 0,
      realtimeChannels: 0,
      fileSizeBytes: picked.size,
    );
  }

  String _contentTypeFor(String extension) {
    return switch (extension.toLowerCase().replaceFirst('.', '')) {
      'm4a' || 'mp4' => 'audio/mp4',
      'mp3' => 'audio/mpeg',
      'wav' => 'audio/wav',
      'flac' => 'audio/flac',
      'ogg' => 'audio/ogg',
      'amr' => 'audio/amr',
      'webm' => 'audio/webm',
      _ => 'application/octet-stream',
    };
  }
}
