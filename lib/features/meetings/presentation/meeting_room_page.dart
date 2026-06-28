import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/action_item.dart';
import '../domain/batch_transcription_status.dart';
import '../domain/meeting_room.dart';
import '../domain/meeting_status.dart';
import '../domain/meeting_workflow.dart';
import '../domain/transcript_segment.dart';
import 'meetings_controller.dart';
import 'widgets/meeting_chat_fab.dart';
import 'widgets/status_chip.dart';

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
      return const Scaffold(body: Center(child: Text('선택된 회의실이 없습니다.')));
    }

    final realtime = room.workflow == MeetingWorkflow.realtime;
    final isRecording = room.status == MeetingStatus.recording;
    final isPaused = room.status == MeetingStatus.paused;
    final anotherRoomRecording = _controller.isRecordingAnotherRoom(
      room.localId,
    );
    final chatEnabled = _isChatAvailable(room);

    return Scaffold(
      appBar: _RoomHeader(
        room: room,
        onBack: () => Navigator.of(context).pop(),
        onCreateMinutes: room.segments.isEmpty
            ? null
            : _showCreateMinutesDialog,
      ),
      body: SafeArea(
        bottom: !realtime,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 12, 16, realtime ? 120 : 28),
          children: [
            if (_controller.errorMessage != null) ...[
              _Notice(text: _controller.errorMessage!, isError: true),
              const SizedBox(height: 12),
            ],
            if (anotherRoomRecording) ...[
              _Notice(
                text:
                    '${_controller.activeRecordingRoomTitle ?? '다른 회의실'}에서 '
                    '녹음이 진행 중입니다.',
              ),
              const SizedBox(height: 12),
            ],
            if (realtime) ...[
              _LiveTranscriptPanel(
                statusMessage: _controller.statusMessage,
                isPaused: isPaused,
                isRecording: isRecording,
                segments: room.segments,
                partialTranscript: room.partialTranscript,
              ),
              if (room.realtimeMinutesProgress?.isVisible == true) ...[
                const SizedBox(height: 16),
                _RealtimeMinutesProgressCard(room: room),
              ],
              if (_hasResources(room)) ...[
                const SizedBox(height: 16),
                _ResultResources(
                  room: room,
                  isDownloadingPdf: _controller.isDownloadingPdf,
                  isDownloadingDocx: _controller.isDownloadingDocx,
                  isDownloadingTranscript: _controller.isDownloadingTranscript,
                  isRefreshingActionItems: _controller.isRefreshingActionItems,
                  isAddingCalendarEvent: _controller.isAddingCalendarEvent,
                  onRealtimeTranscript: () =>
                      _controller.downloadAndOpenTranscript(batch: false),
                  onBatchTranscript: () =>
                      _controller.downloadAndOpenTranscript(batch: true),
                  onPdf: _controller.downloadAndOpenPdf,
                  onDocx: _controller.downloadAndOpenDocx,
                  onRefreshActionItems: _controller.refreshActionItems,
                  onAddActionItemToCalendar: _showAddActionItemDialog,
                ),
              ],
            ] else ...[
              _BatchOverview(
                room: room,
                isStarting: _controller.isStartingBatch,
                onStart: _showBatchDialog,
                onRefresh: _controller.refreshBatchStatus,
              ),
              if (room.batchJobId != null) ...[
                const SizedBox(height: 14),
                _BatchSteps(room: room),
              ],
              if (room.status == MeetingStatus.completed ||
                  _hasResources(room)) ...[
                const SizedBox(height: 14),
                _ResultResources(
                  room: room,
                  isDownloadingPdf: _controller.isDownloadingPdf,
                  isDownloadingDocx: _controller.isDownloadingDocx,
                  isDownloadingTranscript: _controller.isDownloadingTranscript,
                  isRefreshingActionItems: _controller.isRefreshingActionItems,
                  isAddingCalendarEvent: _controller.isAddingCalendarEvent,
                  onRealtimeTranscript: () =>
                      _controller.downloadAndOpenTranscript(batch: false),
                  onBatchTranscript: () =>
                      _controller.downloadAndOpenTranscript(batch: true),
                  onPdf: _controller.downloadAndOpenPdf,
                  onDocx: _controller.downloadAndOpenDocx,
                  onRefreshActionItems: _controller.refreshActionItems,
                  onAddActionItemToCalendar: _showAddActionItemDialog,
                ),
              ],
              if (_isBatchProcessing(room.status)) ...[
                const SizedBox(height: 14),
                const _Notice(
                  text: '이 화면을 나가도 배치 작업은 계속됩니다. 회의실 목록에서 진행 상태를 확인할 수 있습니다.',
                ),
              ],
            ],
          ],
        ),
      ),
      bottomNavigationBar: realtime
          ? _RealtimeControls(
              isRecording: isRecording,
              isPaused: isPaused,
              onRecord: anotherRoomRecording
                  ? null
                  : _controller.startRecording,
              onPause: isRecording ? _controller.pauseRecording : null,
              onLeave: _showLeaveDialog,
            )
          : null,
      floatingActionButton: MeetingChatFab(
        enabled: chatEnabled,
        onPressed: chatEnabled ? () => _showMeetingChat(room) : null,
      ),
    );
  }

  bool _hasResources(MeetingRoom room) {
    return room.summary != null ||
        room.decisions.isNotEmpty ||
        room.openIssues.isNotEmpty ||
        room.actionItems.isNotEmpty ||
        room.minutesMarkdownS3Key != null ||
        room.pdfS3Key != null ||
        room.docxS3Key != null ||
        room.segments.isNotEmpty;
  }

  bool _isChatAvailable(MeetingRoom room) {
    final minutesCompleted =
        room.status == MeetingStatus.completed ||
        room.realtimeMinutesProgress?.completed == true;
    final hasBackendMeeting = room.backendId != null;
    final hasMinutesResult =
        room.summary != null ||
        room.decisions.isNotEmpty ||
        room.openIssues.isNotEmpty ||
        room.actionItems.isNotEmpty ||
        room.minutesMarkdownS3Key != null ||
        room.pdfS3Key != null ||
        room.docxS3Key != null;
    return minutesCompleted && hasBackendMeeting && hasMinutesResult;
  }

  bool _isBatchProcessing(MeetingStatus status) {
    return {
      MeetingStatus.uploading,
      MeetingStatus.uploaded,
      MeetingStatus.queued,
      MeetingStatus.transcribing,
      MeetingStatus.summarizing,
    }.contains(status);
  }

  void _showLeaveDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('녹음 파일을 저장할까요?'),
        content: const Text(
          '저장하면 녹음 파일과 전사문이 기기에 보관되며 나중에 배치 처리나 회의록 생성에 사용할 수 있습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _controller.leaveRoom();
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }

  void _showCreateMinutesDialog() {
    final room = _controller.selectedRoom;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('회의록을 만들까요?'),
        content: Text(
          '완료된 전사문을 기반으로 회의록 생성을 요청합니다.\n\n'
          '${room?.title ?? '-'}\n${room?.meetingId ?? '-'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _controller.generateMinutesFromRealtime();
            },
            child: const Text('회의록 만들기'),
          ),
        ],
      ),
    );
  }

  void _showBatchDialog() {
    final room = _controller.selectedRoom;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('녹음 파일 배치 전사'),
        content: Text(
          '오디오 파일을 업로드하면 전사와 회의록 생성이 순서대로 진행됩니다.\n\n'
          '${room?.recording == null ? '파일을 직접 선택해 주세요.' : '저장된 녹음 또는 다른 파일을 선택할 수 있습니다.'}',
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
            icon: const Icon(Icons.folder_open, size: 18),
            label: const Text('파일 선택'),
          ),
        ],
      ),
    );
  }

  void _showAddActionItemDialog(int index, ActionItem item) {
    final initialDate = item.resolvedDate ?? DateTime.now();
    final dateController = TextEditingController(text: _dateOnly(initialDate));
    final titleController = TextEditingController(text: item.task);

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('일정 추가'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: dateController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: '날짜',
                    suffixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  onTap: () async {
                    final current =
                        DateTime.tryParse(dateController.text) ?? initialDate;
                    final picked = await showDatePicker(
                      context: dialogContext,
                      initialDate: current,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                    );
                    if (picked != null) {
                      setDialogState(() {
                        dateController.text = _dateOnly(picked);
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '일정 내용',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () async {
                  final date = DateTime.tryParse(dateController.text);
                  if (date == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('날짜를 확인해 주세요.')),
                    );
                    return;
                  }
                  Navigator.of(dialogContext).pop();
                  final added = await _controller.addActionItemToCalendar(
                    actionItemIndex: index,
                    date: date,
                    title: titleController.text,
                  );
                  if (added && mounted) {
                    _showOpenCalendarDialog(date);
                  }
                },
                child: const Text('캘린더에 추가'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showOpenCalendarDialog(DateTime date) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('일정이 추가되었습니다'),
        content: const Text('기본 캘린더 앱에서 등록된 일정을 확인할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('나중에'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _controller.openCalendar(date: date);
            },
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('캘린더 열기'),
          ),
        ],
      ),
    );
  }

  String _dateOnly(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  void _showMeetingChat(MeetingRoom room) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => MeetingChatSheet(
        room: room,
        onLoadHistory: _controller.getQaHistory,
        onAskQuestion: _controller.askQaQuestion,
        onLoadSuggestedQuestions: _controller.getQaSuggestedQuestions,
      ),
    );
  }
}

class _RoomHeader extends StatelessWidget implements PreferredSizeWidget {
  const _RoomHeader({
    required this.room,
    required this.onBack,
    required this.onCreateMinutes,
  });

  final MeetingRoom room;
  final VoidCallback onBack;
  final VoidCallback? onCreateMinutes;

  @override
  Size get preferredSize => const Size.fromHeight(96);

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 430;
    return Material(
      color: AppTheme.surface,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              IconButton.filledTonal(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back, size: 20),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StatusChip(status: room.status),
                    const SizedBox(height: 5),
                    Text(
                      room.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${room.meetingId}  ·  ${_formatDate(room.createdAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (onCreateMinutes != null) ...[
                const SizedBox(width: 8),
                if (compact)
                  IconButton.filled(
                    tooltip: '회의록 만들기',
                    onPressed: onCreateMinutes,
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.purple,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.menu_book_outlined, size: 19),
                  )
                else
                  FilledButton.icon(
                    onPressed: onCreateMinutes,
                    icon: const Icon(Icons.menu_book_outlined, size: 17),
                    label: const Text('회의록'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.purple,
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}.${_two(date.month)}.${_two(date.day)} '
        '${_two(date.hour)}:${_two(date.minute)}';
  }

  String _two(int value) => value.toString().padLeft(2, '0');
}

class _LiveTranscriptPanel extends StatelessWidget {
  const _LiveTranscriptPanel({
    required this.statusMessage,
    required this.isPaused,
    required this.isRecording,
    required this.segments,
    this.partialTranscript,
  });

  final String statusMessage;
  final bool isPaused;
  final bool isRecording;
  final List<TranscriptSegment> segments;
  final String? partialTranscript;

  @override
  Widget build(BuildContext context) {
    final statusColor = isPaused
        ? Colors.orange
        : isRecording
        ? Colors.red
        : AppTheme.muted;
    final hasTranscript = segments.isNotEmpty || partialTranscript != null;

    return Column(
      children: [
        Card(
          child: SizedBox(
            height: 505,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.circle, size: 8, color: statusColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Live Transcription',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        constraints: const BoxConstraints(maxWidth: 145),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF2FF),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: const Text(
                          '최신 대화 상단 고정',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppTheme.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: hasTranscript
                        ? ListView(
                            key: const ValueKey('live-transcript-list'),
                            children: [
                              if (partialTranscript != null)
                                Opacity(
                                  opacity: 0.55,
                                  child: _TranscriptLine(
                                    TranscriptSegment(
                                      id: 'partial',
                                      text: partialTranscript!,
                                      startedAt: Duration.zero,
                                      endedAt: Duration.zero,
                                      isFinal: false,
                                    ),
                                  ),
                                ),
                              ...segments.reversed.map(_TranscriptLine.new),
                            ],
                          )
                        : const _TranscriptEmptyState(),
                  ),
                  const Divider(height: 24),
                  Text(
                    isPaused
                        ? '일시정지되었습니다. 녹음 버튼을 누르면 이어서 진행합니다.'
                        : statusMessage,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF2FF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            isRecording
                ? '실시간 전사가 진행 중입니다.'
                : isPaused
                ? '실시간 전사가 일시정지되었습니다.'
                : '실시간 전사가 활성화되어 있습니다.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _TranscriptEmptyState extends StatelessWidget {
  const _TranscriptEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.mic_none_rounded, size: 52, color: AppTheme.muted),
          const SizedBox(height: 14),
          Text(
            '녹음을 시작하면 전사가 시작됩니다',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
          ),
          const SizedBox(height: 6),
          Text('녹음 버튼을 눌러 시작하세요', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _RealtimeControls extends StatelessWidget {
  const _RealtimeControls({
    required this.isRecording,
    required this.isPaused,
    required this.onRecord,
    required this.onPause,
    required this.onLeave,
  });

  final bool isRecording;
  final bool isPaused;
  final VoidCallback? onRecord;
  final VoidCallback? onPause;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(top: BorderSide(color: AppTheme.border)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: onRecord,
                icon: Icon(
                  isPaused ? Icons.play_arrow_rounded : Icons.mic_none_rounded,
                ),
                label: Text(isPaused ? '녹음 재개' : '녹음'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFF3347),
                  minimumSize: const Size(0, 58),
                ),
              ),
            ),
            if (isRecording) ...[
              const SizedBox(width: 10),
              SizedBox(
                width: 58,
                child: FilledButton(
                  onPressed: onPause,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.orange,
                    minimumSize: const Size(58, 58),
                    padding: EdgeInsets.zero,
                  ),
                  child: const Icon(Icons.pause_rounded),
                ),
              ),
            ],
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: onLeave,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('나가기'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.ink,
                  minimumSize: const Size(0, 58),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BatchOverview extends StatelessWidget {
  const _BatchOverview({
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
    final hasJob = room.batchJobId != null;
    final progress = _progress(room.status);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  hasJob ? '전체 진행률' : '배치 파일 전사',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                if (hasJob)
                  Text(
                    '${(progress * 100).round()}%',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: AppTheme.primary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (hasJob) ...[
              LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                borderRadius: BorderRadius.circular(99),
                backgroundColor: const Color(0xFFE9EEF7),
              ),
              const SizedBox(height: 10),
              Text(
                '${room.title} · ${room.batchStatus?.label ?? room.status.label}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('상태 새로고침'),
                ),
              ),
            ] else ...[
              Text(
                room.recording == null
                    ? '오디오 파일을 선택하면 비동기적으로 전사와 회의록 생성을 진행합니다.'
                    : '${room.recording!.fileName}을 사용하거나 다른 파일을 선택할 수 있습니다.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: isStarting ? null : onStart,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(isStarting ? '시작 중' : '배치 시작'),
                ),
              ),
            ],
            if (room.batchErrorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                room.batchErrorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  double _progress(MeetingStatus status) {
    return switch (status) {
      MeetingStatus.uploading => 0.18,
      MeetingStatus.uploaded => 0.34,
      MeetingStatus.queued => 0.48,
      MeetingStatus.transcribing => 0.68,
      MeetingStatus.summarizing => 0.86,
      MeetingStatus.completed => 1,
      _ => 0.08,
    };
  }
}

class _BatchSteps extends StatelessWidget {
  const _BatchSteps({required this.room});

  final MeetingRoom room;

  @override
  Widget build(BuildContext context) {
    final current = _stepIndex(room.batchStatus, room.status);
    final steps = const [
      ('녹음 파일 선택 완료', '선택한 오디오 파일을 확인했습니다.'),
      ('파일 업로드 완료', 'S3 업로드와 확인 요청을 완료했습니다.'),
      ('배치 작업 시작', 'worker 처리 대기열에 등록했습니다.'),
      ('전사문 생성', '오디오와 화자 라벨을 처리합니다.'),
      ('회의록 생성', '요약과 회의록 파일을 생성합니다.'),
      ('결과 저장', '전사문과 회의록 리소스를 저장합니다.'),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('처리 단계', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            for (var index = 0; index < steps.length; index++)
              _BatchStepTile(
                title: steps[index].$1,
                description: steps[index].$2,
                state: index < current
                    ? _StepState.done
                    : index == current
                    ? _StepState.active
                    : _StepState.waiting,
                showLine: index != steps.length - 1,
              ),
          ],
        ),
      ),
    );
  }

  int _stepIndex(BatchTranscriptionStatus? batchStatus, MeetingStatus status) {
    if (status == MeetingStatus.completed) return 6;
    if (status == MeetingStatus.summarizing) return 4;
    if (status == MeetingStatus.transcribing) return 3;
    if (status == MeetingStatus.queued) return 2;
    if (status == MeetingStatus.uploaded) return 2;
    if (status == MeetingStatus.uploading) return 1;
    return switch (batchStatus) {
      BatchTranscriptionStatus.completed => 6,
      BatchTranscriptionStatus.summarizing => 4,
      BatchTranscriptionStatus.transcribing => 3,
      BatchTranscriptionStatus.queued => 2,
      BatchTranscriptionStatus.uploaded => 2,
      _ => 0,
    };
  }
}

enum _StepState { done, active, waiting }

class _BatchStepTile extends StatelessWidget {
  const _BatchStepTile({
    required this.title,
    required this.description,
    required this.state,
    required this.showLine,
  });

  final String title;
  final String description;
  final _StepState state;
  final bool showLine;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      _StepState.done => const Color(0xFF28C98B),
      _StepState.active => AppTheme.primary,
      _StepState.waiting => AppTheme.border,
    };
    final label = switch (state) {
      _StepState.done => '완료',
      _StepState.active => '진행 중',
      _StepState.waiting => '대기',
    };

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: color),
                  ),
                  child: Icon(
                    state == _StepState.done
                        ? Icons.check
                        : state == _StepState.active
                        ? Icons.sync
                        : Icons.circle_outlined,
                    size: 13,
                    color: color,
                  ),
                ),
                if (showLine)
                  Expanded(child: Container(width: 2, color: color)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            color: color,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (state == _StepState.active) ...[
                    const SizedBox(height: 5),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RealtimeMinutesProgressCard extends StatelessWidget {
  const _RealtimeMinutesProgressCard({required this.room});

  final MeetingRoom room;

  @override
  Widget build(BuildContext context) {
    final progress = room.realtimeMinutesProgress;
    if (progress == null) return const SizedBox.shrink();
    final percent = progress.safePercent;
    final failed = progress.failed || room.status == MeetingStatus.failed;
    final completed = progress.completed || percent >= 100;
    final title = failed
        ? '실시간 회의록 생성 실패'
        : completed
        ? '100% 완료'
        : '$percent% 처리 중';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  '$percent%',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: failed ? Colors.red : AppTheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: failed ? null : percent / 100,
              minHeight: 8,
              borderRadius: BorderRadius.circular(99),
              backgroundColor: const Color(0xFFE9EEF7),
              color: failed ? Colors.red : AppTheme.primary,
            ),
            const SizedBox(height: 10),
            Text(
              progress.message ?? _progressStepLabel(progress.step),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  String _progressStepLabel(String? step) {
    return switch (step) {
      'requested' => '회의록 생성을 준비하고 있습니다.',
      'loading_segments' => '전사 segment를 불러오고 있습니다.',
      'preprocessing_transcript' => '회의록 입력을 정리하고 있습니다.',
      'llm_generating_minutes' => '요약과 액션 아이템을 생성하고 있습니다.',
      'rendering_artifacts' => '회의록 파일을 생성하고 있습니다.',
      'uploading_to_s3' => '회의록 파일을 S3에 저장하고 있습니다.',
      'saving_result' => '결과 메타데이터를 저장하고 있습니다.',
      'completed' => '회의록 생성이 완료되었습니다.',
      'failed' => '회의록 생성에 실패했습니다.',
      _ => '회의록 생성 상태를 확인하고 있습니다.',
    };
  }
}

class _ResultResources extends StatelessWidget {
  const _ResultResources({
    required this.room,
    required this.isDownloadingPdf,
    required this.isDownloadingDocx,
    required this.isDownloadingTranscript,
    required this.isRefreshingActionItems,
    required this.isAddingCalendarEvent,
    required this.onRealtimeTranscript,
    required this.onBatchTranscript,
    required this.onPdf,
    required this.onDocx,
    required this.onRefreshActionItems,
    required this.onAddActionItemToCalendar,
  });

  final MeetingRoom room;
  final bool isDownloadingPdf;
  final bool isDownloadingDocx;
  final bool isDownloadingTranscript;
  final bool isRefreshingActionItems;
  final bool isAddingCalendarEvent;
  final VoidCallback onRealtimeTranscript;
  final VoidCallback onBatchTranscript;
  final VoidCallback onPdf;
  final VoidCallback onDocx;
  final VoidCallback onRefreshActionItems;
  final void Function(int index, ActionItem item) onAddActionItemToCalendar;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (room.summary != null ||
            room.decisions.isNotEmpty ||
            room.openIssues.isNotEmpty ||
            room.actionItems.isNotEmpty) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('회의 결과', style: Theme.of(context).textTheme.titleMedium),
                  if (room.summary != null) ...[
                    const SizedBox(height: 12),
                    Text(room.summary!),
                  ],
                  if (room.decisions.isNotEmpty)
                    _ResultList(title: '결정 사항', items: room.decisions),
                  if (room.openIssues.isNotEmpty)
                    _ResultList(title: '미결 사항', items: room.openIssues),
                  if (room.actionItems.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _ActionItemsList(
                      items: room.actionItems,
                      isAddingCalendarEvent: isAddingCalendarEvent,
                      onAddToCalendar: onAddActionItemToCalendar,
                    ),
                  ],
                  if (room.backendId != null) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: isRefreshingActionItems
                            ? null
                            : onRefreshActionItems,
                        icon: const Icon(Icons.event_available_outlined),
                        label: Text(
                          isRefreshingActionItems
                              ? '액션 플랜 조회 중'
                              : '캘린더용 액션 플랜 갱신',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '파일 및 리소스',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                if (room.recording != null)
                  _ResourceRow(
                    icon: Icons.headphones_outlined,
                    color: AppTheme.primary,
                    title: '녹음 파일',
                    extension: _extension(room.recording!.fileName),
                  ),
                if (room.segments.isNotEmpty)
                  _ResourceRow(
                    icon: Icons.description_outlined,
                    color: const Color(0xFF20B486),
                    title: '실시간 전사문',
                    extension: '.txt',
                    actionLabel: isDownloadingTranscript ? '여는 중' : '열기',
                    onAction: isDownloadingTranscript
                        ? null
                        : onRealtimeTranscript,
                  ),
                if (room.recording?.transcriptS3Key != null)
                  _ResourceRow(
                    icon: Icons.article_outlined,
                    color: Colors.orange,
                    title: '배치 전사문',
                    extension: '.txt',
                    actionLabel: isDownloadingTranscript ? '여는 중' : '열기',
                    onAction: isDownloadingTranscript
                        ? null
                        : onBatchTranscript,
                  ),
                if (room.pdfS3Key != null)
                  _ResourceRow(
                    icon: Icons.menu_book_outlined,
                    color: AppTheme.purple,
                    title: '회의록',
                    extension: '.pdf',
                    actionLabel: isDownloadingPdf ? '여는 중' : '열기',
                    onAction: isDownloadingPdf ? null : onPdf,
                  ),
                if (room.docxS3Key != null)
                  _ResourceRow(
                    icon: Icons.description_outlined,
                    color: const Color(0xFF2563EB),
                    title: '회의록',
                    extension: '.docx',
                    actionLabel: isDownloadingDocx ? '여는 중' : '열기',
                    onAction: isDownloadingDocx ? null : onDocx,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _extension(String fileName) {
    final index = fileName.lastIndexOf('.');
    return index == -1 ? '' : fileName.substring(index);
  }
}

class _ResultList extends StatelessWidget {
  const _ResultList({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          ...items.map((item) => Text('• $item')),
        ],
      ),
    );
  }
}

class _ActionItemsList extends StatelessWidget {
  const _ActionItemsList({
    required this.items,
    required this.isAddingCalendarEvent,
    required this.onAddToCalendar,
  });

  final List<ActionItem> items;
  final bool isAddingCalendarEvent;
  final void Function(int index, ActionItem item) onAddToCalendar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '후속 조치',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              '${items.length}개',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (var index = 0; index < items.length; index += 1)
          _ActionItemRow(
            index: index,
            item: items[index],
            isBusy: isAddingCalendarEvent,
            showCalendarAction:
                items[index].hasCalendarCandidateDate ||
                items[index].isAddedToCalendar,
            onAddToCalendar: onAddToCalendar,
          ),
      ],
    );
  }
}

class _ActionItemRow extends StatelessWidget {
  const _ActionItemRow({
    required this.index,
    required this.item,
    required this.isBusy,
    required this.showCalendarAction,
    required this.onAddToCalendar,
  });

  final int index;
  final ActionItem item;
  final bool isBusy;
  final bool showCalendarAction;
  final void Function(int index, ActionItem item) onAddToCalendar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Icon(
              Icons.check_circle_outline,
              size: 17,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.task,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  '${item.displayOwner} · 기한 ${item.displayDueDate}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (showCalendarAction) ...[
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: isBusy || item.isAddedToCalendar
                  ? null
                  : () => onAddToCalendar(index, item),
              icon: Icon(
                item.isAddedToCalendar
                    ? Icons.event_available
                    : Icons.add_circle_outline,
                size: 16,
              ),
              label: Text(item.isAddedToCalendar ? '추가됨' : '일정 추가'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ResourceRow extends StatelessWidget {
  const _ResourceRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.extension,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String extension;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 21),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: title,
                children: [
                  TextSpan(
                    text: ' $extension',
                    style: const TextStyle(
                      color: AppTheme.muted,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (actionLabel != null)
            TextButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.open_in_new, size: 15),
              label: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

class _TranscriptLine extends StatelessWidget {
  const _TranscriptLine(this.segment);

  final TranscriptSegment segment;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 62,
            child: Text(
              _time(segment.startedAt),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
            ),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  if (segment.speaker != null)
                    TextSpan(
                      text: '${segment.displaySpeaker} ',
                      style: const TextStyle(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  TextSpan(text: segment.text),
                ],
              ),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  String _time(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.isError = false});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError
        ? Theme.of(context).colorScheme.error
        : AppTheme.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Text(
        text,
        style: TextStyle(color: isError ? color : AppTheme.ink),
      ),
    );
  }
}
