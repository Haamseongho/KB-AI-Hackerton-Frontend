import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../domain/meeting_room.dart';
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
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '회의방',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _showCreateRoomSheet,
                  icon: const Icon(Icons.add),
                  label: const Text('새 회의방'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '서버 REST ${AppConfig.apiBaseUrl} · 실시간 WS ${AppConfig.wsBaseUrl}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '회의 제목, meeting_id, 날짜 검색',
                border: OutlineInputBorder(),
              ),
              onChanged: _controller.search,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                '회의방은 로컬에 저장됩니다. 회의방을 열고 녹음을 시작하면 PCM 오디오가 FastAPI로 전송됩니다.',
              ),
            ),
            const SizedBox(height: 20),
            if (_controller.isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_controller.rooms.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('아직 생성된 회의방이 없습니다.')),
              )
            else
              ..._controller.rooms.map(
                (room) => MeetingCard(
                  room: room,
                  onOpen: () => _openRoom(room),
                  onUpload: () {
                    _controller.selectRoom(room);
                    _confirmUpload();
                  },
                  onDelete: () => _confirmDelete(room),
                ),
              ),
          ],
        ),
      ),
    );
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
      builder: (_) => CreateRoomSheet(onCreate: _controller.createRoom),
    );
  }

  void _confirmUpload() {
    showDialog<void>(
      context: context,
      builder: (context) {
        final room = _controller.selectedRoom;
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

  void _confirmDelete(MeetingRoom room) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('기기에서 삭제하시겠습니까?'),
          content: Text(
            '${room.title} 회의방과 기기에 저장된 녹음 파일 및 대화록이 삭제됩니다.\n\n'
            '백엔드에 생성된 회의 데이터는 삭제되지 않습니다.',
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
                  await _controller.deleteRoomFromDevice(room);
                  if (!mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('기기에서 삭제했습니다.')));
                } catch (_) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        _controller.errorMessage ?? '기기에서 삭제하지 못했습니다.',
                      ),
                    ),
                  );
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              child: const Text('삭제'),
            ),
          ],
        );
      },
    );
  }
}
