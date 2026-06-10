import 'package:flutter/material.dart';

import '../../meetings/domain/meeting_room.dart';
import '../../meetings/domain/meeting_status.dart';
import '../../meetings/domain/transcript_segment.dart';
import 'meetings_controller.dart';

class MeetingRoomPage extends StatefulWidget {
  const MeetingRoomPage({super.key, required this.controller});

  final MeetingsController controller;

  @override
  State<MeetingRoomPage> createState() => _MeetingRoomPageState();
}

class _MeetingRoomPageState extends State<MeetingRoomPage> {
  MeetingsController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final room = _controller.selectedRoom;
    if (room == null) {
      return const Scaffold(body: Center(child: Text('선택된 회의방이 없습니다.')));
    }

    final isPaused = room.status == MeetingStatus.paused;
    final isRecording = room.status == MeetingStatus.recording;
    final isAnotherRoomRecording = _controller.isRecordingAnotherRoom(
      room.localId,
    );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              room.title,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            Text(
              room.meetingId,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: _showUploadDialog,
            icon: const Icon(Icons.description_outlined),
            label: const Text('회의록'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          children: [
            Text(
              _formatDate(room.createdAt),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 16),
            _LiveTranscriptPanel(
              statusMessage: _controller.statusMessage,
              isPaused: isPaused,
              isRecording: isRecording,
              autoScroll: room.autoScroll,
              segments: room.segments,
              partialTranscript: room.partialTranscript,
              onAutoScrollChanged: _controller.toggleAutoScroll,
            ),
            const SizedBox(height: 18),
            if (_controller.errorMessage != null)
              _Notice(text: _controller.errorMessage!, isError: true),
            if (_controller.errorMessage != null) const SizedBox(height: 12),
            if (isAnotherRoomRecording)
              _Notice(
                text:
                    '${_controller.activeRecordingRoomTitle ?? '다른 회의방'}에서 '
                    '백그라운드 녹음이 진행 중입니다. 녹음과 전사 기록은 시작한 회의방에만 저장됩니다.',
              ),
            if (isAnotherRoomRecording) const SizedBox(height: 12),
            _ControlRow(
              isRecording: isRecording,
              isPaused: isPaused,
              onRecord: isAnotherRoomRecording
                  ? null
                  : _controller.startRecording,
              onPause: isRecording ? _controller.pauseRecording : null,
              onTestEvent: _controller.debugMode
                  ? _controller.appendDebugTranscript
                  : null,
              onLeave: _showLeaveDialog,
            ),
            const SizedBox(height: 18),
            _Notice(
              text: isPaused
                  ? '취소하면 녹음은 일시정지 상태로 유지됩니다. 녹음을 다시 누르면 중단 지점부터 이어서 진행됩니다.'
                  : '녹음 중에는 실시간 대화록이 바로 표시됩니다. 녹음을 일시정지하면 실시간 변환도 함께 멈춥니다.',
            ),
            const SizedBox(height: 18),
            _BatchTranscriptionPanel(
              room: room,
              isStarting: _controller.isStartingBatch,
              onStart: _showBatchDialog,
              onRefresh: _controller.refreshBatchStatus,
            ),
            const SizedBox(height: 18),
            _MinutesResources(
              summary: room.summary,
              minutesMarkdownS3Key: room.minutesMarkdownS3Key,
              pdfS3Key: room.pdfS3Key,
              isDownloadingPdf: _controller.isDownloadingPdf,
              onDownloadPdf: _controller.downloadAndOpenPdf,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}. ${date.month}. ${date.day}. ${_two(date.hour)}:${_two(date.minute)}';
  }

  String _two(int value) => value.toString().padLeft(2, '0');

  void _showLeaveDialog() {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('녹음 파일을 저장할까요?'),
          content: const Text(
            '저장하면 녹음 파일이 로컬에 보관되며 나중에 S3 업로드나 회의록 생성에 사용할 수 있습니다.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                _controller.leaveRoom();
              },
              child: const Text('저장'),
            ),
          ],
        );
      },
    );
  }

  void _showUploadDialog() {
    final room = _controller.selectedRoom;
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('회의록으로 정리하시겠습니까?'),
          content: Text(
            '완료된 실시간 대화록을 기반으로 회의록 생성을 요청합니다.\n생성된 회의록 파일은 백엔드가 S3에 저장합니다.\n\n회의방: ${room?.title ?? '-'}\nmeeting_id: ${room?.meetingId ?? '-'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                _controller.generateMinutesFromRealtime();
              },
              child: const Text('확인'),
            ),
          ],
        );
      },
    );
  }

  void _showBatchDialog() {
    final room = _controller.selectedRoom;
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('녹음 파일 배치 전사'),
          content: Text(
            '오디오 파일 전체를 S3에 업로드하고 배치 처리를 시작합니다.\n'
            '배치 전사 완료 후 회의록까지 자동 생성됩니다.\n\n'
            '${room?.recording == null ? '저장된 녹음이 없어 파일을 직접 선택해야 합니다.' : '이 회의방의 저장된 녹음을 사용하거나 다른 파일을 선택할 수 있습니다.'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('취소'),
            ),
            if (room?.recording != null)
              OutlinedButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _controller.startBatchTranscription(useSavedRecording: true);
                },
                child: const Text('저장된 녹음'),
              ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _controller.startBatchTranscription(useSavedRecording: false);
              },
              icon: const Icon(Icons.folder_open),
              label: const Text('파일 선택'),
            ),
          ],
        );
      },
    );
  }
}

class _BatchTranscriptionPanel extends StatelessWidget {
  const _BatchTranscriptionPanel({
    required this.room,
    required this.isStarting,
    required this.onStart,
    required this.onRefresh,
  });

  final MeetingRoom room;
  final bool isStarting;
  final VoidCallback onStart;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final recording = room.recording;
    final hasJob = room.batchJobId != null;
    final isProcessing =
        hasJob &&
        {
          MeetingStatus.uploading,
          MeetingStatus.uploaded,
          MeetingStatus.queued,
          MeetingStatus.transcribing,
          MeetingStatus.summarizing,
        }.contains(room.status);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '배치 파일 전사',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: isStarting || isProcessing ? null : onStart,
                  icon: isStarting
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_upload_outlined),
                  label: Text(isStarting ? '준비 중' : '배치 시작'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              recording == null
                  ? '저장된 녹음이 없습니다. 지원되는 오디오 파일을 직접 선택할 수 있습니다.'
                  : '${recording.fileName} · ${_fileSize(recording.fileSizeBytes)}',
            ),
            if (hasJob) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: _progressFor(room.status)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${room.status.label} · Job ${room.batchJobId}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('새로고침'),
                  ),
                ],
              ),
            ],
            if (room.batchErrorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                room.batchErrorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              '배치 전사 원문 조회는 현재 백엔드 API가 없어 앱에서 제공하지 않습니다. '
              '처리가 완료되면 요약과 PDF 회의록을 확인할 수 있습니다.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  double? _progressFor(MeetingStatus status) {
    return switch (status) {
      MeetingStatus.uploading => 0.2,
      MeetingStatus.uploaded => 0.4,
      MeetingStatus.queued => 0.5,
      MeetingStatus.transcribing => 0.7,
      MeetingStatus.summarizing => 0.9,
      MeetingStatus.completed => 1,
      _ => null,
    };
  }

  String _fileSize(int? bytes) {
    if (bytes == null || bytes <= 0) return '크기 정보 없음';
    final megabytes = bytes / (1024 * 1024);
    return '${megabytes.toStringAsFixed(1)} MB';
  }
}

class _MinutesResources extends StatelessWidget {
  const _MinutesResources({
    required this.summary,
    required this.minutesMarkdownS3Key,
    required this.pdfS3Key,
    required this.isDownloadingPdf,
    required this.onDownloadPdf,
  });

  final String? summary;
  final String? minutesMarkdownS3Key;
  final String? pdfS3Key;
  final bool isDownloadingPdf;
  final VoidCallback onDownloadPdf;

  @override
  Widget build(BuildContext context) {
    if (summary == null && minutesMarkdownS3Key == null && pdfS3Key == null) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '파일 및 결과',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            if (summary != null) ...[
              const SizedBox(height: 10),
              Text(summary!),
            ],
            if (minutesMarkdownS3Key != null) ...[
              const SizedBox(height: 10),
              Text('회의록: $minutesMarkdownS3Key'),
            ],
            if (pdfS3Key != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: isDownloadingPdf ? null : onDownloadPdf,
                  icon: isDownloadingPdf
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_outlined),
                  label: Text(isDownloadingPdf ? 'PDF 다운로드 중' : 'PDF 회의록 다운로드'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LiveTranscriptPanel extends StatelessWidget {
  const _LiveTranscriptPanel({
    required this.statusMessage,
    required this.isPaused,
    required this.isRecording,
    required this.autoScroll,
    required this.segments,
    required this.onAutoScrollChanged,
    this.partialTranscript,
  });

  final String statusMessage;
  final bool isPaused;
  final bool isRecording;
  final bool autoScroll;
  final List<TranscriptSegment> segments;
  final String? partialTranscript;
  final ValueChanged<bool> onAutoScrollChanged;

  @override
  Widget build(BuildContext context) {
    final statusColor = isPaused ? Colors.deepOrange : Colors.green;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('실시간 STT', style: Theme.of(context).textTheme.labelLarge),
                const Spacer(),
                Checkbox(value: autoScroll, onChanged: _onAutoChanged),
                const Text('자동 스크롤'),
              ],
            ),
            Text(
              isPaused ? '실시간 변환이 일시정지되었습니다.' : '실시간 변환이 진행 중입니다.',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(statusMessage),
            ),
            const SizedBox(height: 12),
            Container(
              height: 310,
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: segments.isEmpty && partialTranscript == null
                  ? const Center(child: Text('녹음을 시작하면 실시간 대화록이 여기에 표시됩니다.'))
                  : ListView(
                      children: [
                        ...segments.map(_TranscriptLine.new),
                        if (partialTranscript != null)
                          Opacity(
                            opacity: 0.65,
                            child: _TranscriptLine(
                              TranscriptSegment(
                                id: 'partial',
                                text: partialTranscript!,
                                startedAt: Duration.zero,
                                endedAt: Duration.zero,
                                isFinal: false,
                                speaker: '부분 결과',
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.circle, size: 8, color: statusColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isPaused
                        ? '일시정지 상태입니다. 녹음을 다시 누르면 새 스트림으로 이어집니다.'
                        : 'PCM 오디오를 FastAPI로 전송하고 대화록 이벤트를 기다리는 중입니다.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _onAutoChanged(bool? value) {
    if (value == null) return;
    onAutoScrollChanged(value);
  }
}

class _TranscriptLine extends StatelessWidget {
  const _TranscriptLine(this.segment);

  final TranscriptSegment segment;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_time(segment.startedAt)}   ${segment.speaker ?? '화자'}   ${segment.isFinal ? '최종' : '부분'}${segment.isLowConfidence ? ' · 낮은 신뢰도' : ''}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 4),
          Text(segment.text, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }

  String _time(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '00:$minutes:$seconds';
  }
}

class _ControlRow extends StatelessWidget {
  const _ControlRow({
    required this.isRecording,
    required this.isPaused,
    required this.onRecord,
    required this.onPause,
    required this.onTestEvent,
    required this.onLeave,
  });

  final bool isRecording;
  final bool isPaused;
  final VoidCallback? onRecord;
  final VoidCallback? onPause;
  final VoidCallback? onTestEvent;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton(
            onPressed: onRecord,
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('녹음'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton(
            onPressed: onPause,
            style: FilledButton.styleFrom(backgroundColor: Colors.amber),
            child: Text(isPaused ? '일시정지됨' : '일시정지'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton(
            onPressed: onTestEvent,
            style: FilledButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text('테스트'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton(
            onPressed: onLeave,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF111827),
            ),
            child: const Text('나가기'),
          ),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.isError = false});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (isError ? Colors.red : Colors.amber).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text),
    );
  }
}
