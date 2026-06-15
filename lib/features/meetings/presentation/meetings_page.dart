import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/meeting_room.dart';
import '../domain/meeting_status.dart';
import '../domain/meeting_workflow.dart';
import 'meeting_room_page.dart';
import 'meetings_controller.dart';
import 'widgets/create_room_sheet.dart';
import 'widgets/meeting_card.dart';

class MeetingsPage extends StatefulWidget {
  const MeetingsPage({super.key, required this.controller});

  final MeetingsController controller;

  @override
  State<MeetingsPage> createState() => _MeetingsPageState();
}

class _MeetingsPageState extends State<MeetingsPage> {
  late final TextEditingController _searchController;
  MeetingWorkflow _workflow = MeetingWorkflow.realtime;

  MeetingsController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _controller.addListener(_onChanged);
    _controller.loadRooms();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final rooms = _controller.rooms
        .where((room) => room.workflow == _workflow)
        .toList(growable: false);

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
              sliver: SliverList.list(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '회의실',
                              style: Theme.of(context).textTheme.headlineLarge,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${_controller.rooms.length}개의 회의실',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: _showCreateRoomSheet,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('새 회의실'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 42),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(
                        Icons.search,
                        size: 20,
                        color: AppTheme.muted,
                      ),
                      hintText: '회의실 이름 또는 ID 검색',
                    ),
                    onChanged: _controller.search,
                  ),
                  const SizedBox(height: 14),
                  _WorkflowTabs(
                    selected: _workflow,
                    onChanged: (workflow) {
                      setState(() => _workflow = workflow);
                    },
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
            if (_controller.isLoading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (rooms.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyRooms(workflow: _workflow),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                sliver: SliverList.builder(
                  itemCount: rooms.length,
                  itemBuilder: (context, index) {
                    final room = rooms[index];
                    return MeetingCard(
                      room: room,
                      onOpen: () => _openRoom(room),
                      onPrimaryAction: () => _primaryAction(room),
                      onDelete: () => _confirmDelete(room),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _primaryAction(MeetingRoom room) {
    if (room.workflow == MeetingWorkflow.batch &&
        room.batchJobId == null &&
        room.status != MeetingStatus.completed) {
      _controller.selectRoom(room);
      _showBatchDialog();
      return;
    }
    _openRoom(room);
  }

  void _openRoom(MeetingRoom room) {
    _controller.selectRoom(room);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MeetingRoomPage(controller: _controller),
      ),
    );
  }

  void _showCreateRoomSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      showDragHandle: false,
      builder: (_) => CreateRoomSheet(onCreate: _controller.createRoom),
    );
  }

  void _showBatchDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final room = _controller.selectedRoom;
        return AlertDialog(
          title: const Text('배치 전사를 시작할까요?'),
          content: Text(
            '오디오 파일을 업로드하면 전사와 회의록 생성이 순서대로 진행됩니다.\n\n'
            '${room?.title ?? '-'}\n${room?.meetingId ?? '-'}',
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
        );
      },
    );
  }

  void _confirmDelete(MeetingRoom room) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('회의 데이터를 삭제하시겠습니까?'),
          content: Text(
            '${room.title}의 백엔드 실시간 대화록과 S3 회의록 산출물, '
            '기기에 저장된 녹음 파일 및 회의방 데이터가 삭제됩니다.\n\n'
            '백엔드 회의 자체와 원본 오디오는 백엔드 정책에 따라 남을 수 있습니다.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                try {
                  await _controller.deleteRoom(room);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('회의 데이터를 삭제했습니다.')),
                  );
                } catch (_) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        _controller.errorMessage ?? '회의 데이터를 삭제하지 못했습니다.',
                      ),
                    ),
                  );
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('삭제'),
            ),
          ],
        );
      },
    );
  }
}

class _WorkflowTabs extends StatelessWidget {
  const _WorkflowTabs({required this.selected, required this.onChanged});

  final MeetingWorkflow selected;
  final ValueChanged<MeetingWorkflow> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F2F6),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: MeetingWorkflow.values
            .map((workflow) {
              final active = workflow == selected;
              return Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => onChanged(workflow),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: active ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: active && workflow == MeetingWorkflow.batch
                          ? Border.all(color: AppTheme.primary)
                          : null,
                      boxShadow: active
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 5,
                                offset: const Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      workflow == MeetingWorkflow.realtime ? '🔴 실시간' : '📦 배치',
                      style: TextStyle(
                        color: active ? AppTheme.ink : AppTheme.muted,
                        fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              );
            })
            .toList(growable: false),
      ),
    );
  }
}

class _EmptyRooms extends StatelessWidget {
  const _EmptyRooms({required this.workflow});

  final MeetingWorkflow workflow;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              workflow == MeetingWorkflow.realtime
                  ? Icons.mic_none_rounded
                  : Icons.inventory_2_outlined,
              size: 42,
              color: AppTheme.muted,
            ),
            const SizedBox(height: 12),
            Text(
              workflow == MeetingWorkflow.realtime
                  ? '실시간 회의실이 없습니다.'
                  : '배치 회의실이 없습니다.',
            ),
          ],
        ),
      ),
    );
  }
}
