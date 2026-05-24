import 'package:flutter/material.dart';

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
      return const Scaffold(body: Center(child: Text('No room selected.')));
    }

    final isPaused = room.status == MeetingStatus.paused;
    final isRecording = room.status == MeetingStatus.recording;

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
            icon: const Icon(Icons.upload),
            label: const Text('Upload'),
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
            _ControlRow(
              isRecording: isRecording,
              isPaused: isPaused,
              onRecord: _controller.startRecording,
              onPause: isRecording ? _controller.pauseRecording : null,
              onTestEvent: _controller.debugMode
                  ? _controller.appendDebugTranscript
                  : null,
              onLeave: _showLeaveDialog,
            ),
            const SizedBox(height: 18),
            _Notice(
              text: isPaused
                  ? 'If you cancel, recording remains paused. Press Record again to resume from the paused point.'
                  : 'Live transcript text appears in real time while recording. If you pause recording, live transcription will pause too.',
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
          title: const Text('Save Recording File?'),
          content: const Text(
            'If you save, the file will be stored locally and can be uploaded to S3 later.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                _controller.leaveRoom();
              },
              child: const Text('Save'),
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
            '녹음 파일과 transcript를 REST API로 S3 업로드 요청합니다.\n\nRoom: ${room?.title ?? '-'}\nmeeting_id: ${room?.meetingId ?? '-'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                _controller.requestUpload();
              },
              child: const Text('확인'),
            ),
          ],
        );
      },
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
                Text('LIVE STT', style: Theme.of(context).textTheme.labelLarge),
                const Spacer(),
                Checkbox(value: autoScroll, onChanged: _onAutoChanged),
                const Text('Auto'),
              ],
            ),
            Text(
              isPaused
                  ? 'Transcription is paused.'
                  : 'Live transcription is active.',
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
                  ? const Center(
                      child: Text(
                        'Live transcript text will appear here while recording.',
                      ),
                    )
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
                                speaker: 'Partial',
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
                        ? 'Paused. Press Record to open a new stream.'
                        : 'Sending PCM audio to FastAPI and waiting for AWS transcript events.',
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
            '${_time(segment.startedAt)}   ${segment.speaker ?? 'Speaker'}   ${segment.isFinal ? 'Final' : 'Partial'}',
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
  final VoidCallback onRecord;
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
            child: const Text('Record'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton(
            onPressed: onPause,
            style: FilledButton.styleFrom(backgroundColor: Colors.amber),
            child: Text(isPaused ? 'Paused' : 'Pause'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton(
            onPressed: onTestEvent,
            style: FilledButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text('Test Event'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton(
            onPressed: onLeave,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF111827),
            ),
            child: const Text('Leave'),
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
