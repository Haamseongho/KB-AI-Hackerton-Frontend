import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/meeting_room.dart';

class MeetingChatFab extends StatelessWidget {
  const MeetingChatFab({
    super.key,
    required this.enabled,
    required this.onPressed,
  });

  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = enabled ? AppTheme.ink : const Color(0xFFD4D8E1);
    final foregroundColor = enabled ? Colors.white : AppTheme.muted;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled ? 1 : 0.45,
      child: FloatingActionButton.extended(
        heroTag: 'meeting-chat-fab',
        tooltip: enabled ? '회의 내용 챗봇' : '회의록 완성 후 사용할 수 있습니다',
        onPressed: onPressed,
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        icon: const Icon(Icons.chat_bubble_rounded),
        label: const Text('Chat'),
      ),
    );
  }
}

class MeetingChatSheet extends StatefulWidget {
  const MeetingChatSheet({super.key, required this.room});

  final MeetingRoom room;

  @override
  State<MeetingChatSheet> createState() => _MeetingChatSheetState();
}

class _MeetingChatSheetState extends State<MeetingChatSheet> {
  late final TextEditingController _inputController;
  late final ScrollController _scrollController;
  late final List<_ChatMessage> _messages;
  bool _isThinking = false;

  @override
  void initState() {
    super.initState();
    _inputController = TextEditingController();
    _scrollController = ScrollController();
    _messages = [
      _ChatMessage.assistant('회의록이 준비되었습니다. 결정 사항, 미결 사항, 후속 조치에 대해 질문해 주세요.'),
      if (widget.room.summary != null)
        _ChatMessage.assistant('요약: ${widget.room.summary!}'),
    ];
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.55,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, sheetScrollController) {
          return Material(
            color: const Color(0xFFF2F2F7),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _ChatHeader(room: widget.room),
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
                    itemCount: _messages.length + (_isThinking ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (_isThinking && index == _messages.length) {
                        return const _TypingBubble();
                      }
                      return _ChatBubble(message: _messages[index]);
                    },
                  ),
                ),
                _ChatComposer(
                  controller: _inputController,
                  onSend: _sendMessage,
                  isBusy: _isThinking,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _sendMessage() {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isThinking) return;
    setState(() {
      _messages.add(_ChatMessage.user(text));
      _inputController.clear();
      _isThinking = true;
    });
    _scrollToBottom();
    Future<void>.delayed(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage.assistant(_mockAssistantReply(text)));
        _isThinking = false;
      });
      _scrollToBottom();
    });
  }

  String _mockAssistantReply(String prompt) {
    final lower = prompt.toLowerCase();
    final room = widget.room;
    if (lower.contains('결정') && room.decisions.isNotEmpty) {
      return '결정 사항은 ${room.decisions.length}개입니다.\n${_bulletText(room.decisions)}';
    }
    if ((lower.contains('액션') || lower.contains('후속')) &&
        room.actionItems.isNotEmpty) {
      final items = room.actionItems
          .map((item) => '${item.displayOwner}: ${item.task}')
          .toList(growable: false);
      return '후속 조치는 ${items.length}개입니다.\n${_bulletText(items)}';
    }
    if ((lower.contains('이슈') || lower.contains('미결')) &&
        room.openIssues.isNotEmpty) {
      return '미결 사항은 ${room.openIssues.length}개입니다.\n${_bulletText(room.openIssues)}';
    }
    if (room.summary != null) {
      return '현재는 목업 응답입니다. 곧 Bedrock Sonnet API가 연결되면 회의록 전체 문맥으로 답변합니다.\n\n요약 기준 답변: ${room.summary!}';
    }
    return '현재는 목업 응답입니다. API 연결 후 이 질문을 회의록 본문과 함께 Bedrock Sonnet 모델로 전달할 예정입니다.';
  }

  String _bulletText(List<String> values) {
    return values.map((value) => '- $value').join('\n');
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({required this.room});

  final MeetingRoom room;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        border: const Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Column(
            children: [
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFC6CAD3),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: AppTheme.ink,
                    child: const Icon(
                      Icons.smart_toy_outlined,
                      color: Colors.white,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '회의록 챗봇',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${room.title} · ${room.meetingId}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '닫기',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatComposer extends StatelessWidget {
  const _ChatComposer({
    required this.controller,
    required this.onSend,
    required this.isBusy,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppTheme.border)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: '회의 내용에 대해 질문하기',
                  filled: true,
                  fillColor: const Color(0xFFF2F2F7),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: const BorderSide(color: Color(0xFFD8DDE8)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: const BorderSide(color: Color(0xFFD8DDE8)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: const BorderSide(color: AppTheme.primary),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 38,
              height: 38,
              child: FilledButton(
                onPressed: isBusy ? null : onSend,
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(38, 38),
                  shape: const CircleBorder(),
                  backgroundColor: AppTheme.primary,
                ),
                child: const Icon(Icons.arrow_upward_rounded, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.sender == _ChatSender.user;
    final bubbleColor = isUser ? AppTheme.primary : Colors.white;
    final textColor = isUser ? Colors.white : AppTheme.ink;
    final alignment = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(20),
      topRight: const Radius.circular(20),
      bottomLeft: Radius.circular(isUser ? 20 : 5),
      bottomRight: Radius.circular(isUser ? 5 : 20),
    );
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 292),
        child: Container(
          margin: const EdgeInsets.only(bottom: 9),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: radius,
            border: isUser ? null : Border.all(color: AppTheme.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            message.text,
            style: TextStyle(color: textColor, fontSize: 15, height: 1.35),
          ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(bottom: 9),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.all(Radius.circular(20)),
            border: Border.fromBorderSide(BorderSide(color: AppTheme.border)),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text('입력 중...', style: TextStyle(color: AppTheme.muted)),
          ),
        ),
      ),
    );
  }
}

enum _ChatSender { assistant, user }

class _ChatMessage {
  const _ChatMessage({required this.sender, required this.text});

  factory _ChatMessage.assistant(String text) {
    return _ChatMessage(sender: _ChatSender.assistant, text: text);
  }

  factory _ChatMessage.user(String text) {
    return _ChatMessage(sender: _ChatSender.user, text: text);
  }

  final _ChatSender sender;
  final String text;
}
