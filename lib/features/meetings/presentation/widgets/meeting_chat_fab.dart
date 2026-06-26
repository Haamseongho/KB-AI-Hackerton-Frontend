import 'package:flutter/material.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/meeting_room.dart';
import '../../domain/qa_message.dart';

typedef LoadQaHistory =
    Future<List<QaMessage>> Function(String backendMeetingId);
typedef AskQaQuestion =
    Future<QaMessage> Function(
      String backendMeetingId, {
      required String question,
    });

class MeetingChatFab extends StatelessWidget {
  const MeetingChatFab({
    super.key,
    required this.enabled,
    required this.onPressed,
  });

  static const _assetPath = 'assets/mascot/chatbot_mascot_fab.png';

  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled ? 1 : 0.45,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: enabled ? '회의 내용 챗봇' : '회의록 완성 후 사용할 수 있습니다',
        child: Material(
          color: enabled ? Colors.white : const Color(0xFFE2E5EC),
          elevation: enabled ? 8 : 0,
          shadowColor: Colors.black.withValues(alpha: 0.18),
          shape: const CircleBorder(side: BorderSide(color: AppTheme.border)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: SizedBox.square(
              dimension: 74,
              child: Padding(
                padding: const EdgeInsets.all(7),
                child: Image.asset(
                  _assetPath,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MeetingChatSheet extends StatefulWidget {
  const MeetingChatSheet({
    super.key,
    required this.room,
    required this.onLoadHistory,
    required this.onAskQuestion,
  });

  final MeetingRoom room;
  final LoadQaHistory onLoadHistory;
  final AskQaQuestion onAskQuestion;

  @override
  State<MeetingChatSheet> createState() => _MeetingChatSheetState();
}

class _MeetingChatSheetState extends State<MeetingChatSheet> {
  late final TextEditingController _inputController;
  late final ScrollController _scrollController;
  late final List<QaMessage> _messages;
  bool _isThinking = false;
  bool _isLoadingHistory = true;

  @override
  void initState() {
    super.initState();
    _inputController = TextEditingController();
    _scrollController = ScrollController();
    _messages = [
      QaMessage.localAssistant(
        '회의록이 준비되었습니다. 결정 사항, 미결 사항, 후속 조치에 대해 질문해 주세요.',
      ),
      if (widget.room.summary != null)
        QaMessage.localAssistant('요약: ${widget.room.summary!}'),
    ];
    _loadHistory();
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
                  child: Stack(
                    children: [
                      ListView.builder(
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
                      if (_isLoadingHistory)
                        const Positioned(
                          top: 10,
                          left: 0,
                          right: 0,
                          child: Center(child: _HistoryLoadingChip()),
                        ),
                    ],
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

  Future<void> _loadHistory() async {
    final backendId = widget.room.backendId;
    if (backendId == null || backendId.isEmpty) {
      setState(() => _isLoadingHistory = false);
      return;
    }
    try {
      final history = await widget.onLoadHistory(backendId);
      if (!mounted) return;
      if (history.isNotEmpty) {
        setState(() {
          _messages
            ..clear()
            ..addAll(history);
          _isLoadingHistory = false;
        });
      } else {
        setState(() => _isLoadingHistory = false);
      }
      _scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoadingHistory = false;
        _messages.add(QaMessage.localAssistant(_errorText(error)));
      });
      _scrollToBottom();
    }
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isThinking) return;
    final backendId = widget.room.backendId;
    if (backendId == null || backendId.isEmpty) {
      setState(() {
        _messages.add(QaMessage.localAssistant('백엔드 회의 ID가 없어 질문을 보낼 수 없습니다.'));
      });
      return;
    }
    setState(() {
      _messages.add(QaMessage.localUser(text));
      _inputController.clear();
      _isThinking = true;
    });
    _scrollToBottom();
    try {
      final answer = await widget.onAskQuestion(backendId, question: text);
      if (!mounted) return;
      setState(() {
        _messages.add(answer);
        _isThinking = false;
      });
      _scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _messages.add(QaMessage.localAssistant(_errorText(error)));
        _isThinking = false;
      });
      _scrollToBottom();
    }
  }

  String _errorText(Object error) {
    final message = error is AppException ? error.message : error.toString();
    if (message.contains('409') ||
        message.contains('minutes not ready') ||
        message.contains('meeting context')) {
      return '회의록 문맥이 아직 준비되지 않았습니다. 전사와 회의록 생성이 완료된 뒤 다시 시도해 주세요.';
    }
    if (message.contains('422')) {
      return '질문은 1자 이상 300자 이하로 입력해 주세요.';
    }
    if (message.contains('502')) {
      return '챗봇 응답을 해석하지 못했습니다. 잠시 후 다시 질문해 주세요.';
    }
    if (message.contains('TimeoutException')) {
      return '응답 시간이 길어지고 있습니다. 잠시 후 다시 시도해 주세요.';
    }
    return '질문 처리에 실패했습니다. 네트워크 상태와 백엔드 서버를 확인해 주세요.';
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

class _ChatBubble extends StatefulWidget {
  const _ChatBubble({required this.message});

  final QaMessage message;

  @override
  State<_ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<_ChatBubble> {
  bool _showEvidence = false;

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final isUser = message.isUser;
    final bubbleColor = isUser ? AppTheme.primary : Colors.white;
    final textColor = isUser
        ? Colors.white
        : message.isRejected
        ? Colors.red.shade800
        : AppTheme.ink;
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message.content,
                style: TextStyle(color: textColor, fontSize: 15, height: 1.35),
              ),
              if (!isUser && message.evidence.isNotEmpty) ...[
                const SizedBox(height: 9),
                _EvidenceToggle(
                  isExpanded: _showEvidence,
                  evidenceCount: message.evidence.length,
                  onTap: () => setState(() => _showEvidence = !_showEvidence),
                ),
                if (_showEvidence) ...[
                  const SizedBox(height: 7),
                  _EvidenceList(evidence: message.evidence),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EvidenceToggle extends StatelessWidget {
  const _EvidenceToggle({
    required this.isExpanded,
    required this.evidenceCount,
    required this.onTap,
  });

  final bool isExpanded;
  final int evidenceCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isExpanded ? '근거 접기' : '(...)',
              style: const TextStyle(
                color: AppTheme.primary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              '$evidenceCount',
              style: const TextStyle(
                color: AppTheme.muted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EvidenceList extends StatelessWidget {
  const _EvidenceList({required this.evidence});

  final List<QaEvidence> evidence;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '근거',
              style: TextStyle(
                color: AppTheme.muted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            for (final item in evidence)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  '${item.displaySpeaker}'
                  '${item.timestamp == null ? '' : ' · ${item.timestamp}'}\n'
                  '${item.quote}',
                  style: const TextStyle(
                    color: AppTheme.ink,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HistoryLoadingChip extends StatelessWidget {
  const _HistoryLoadingChip();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: AppTheme.border),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Text(
          '대화 기록 불러오는 중',
          style: TextStyle(
            color: AppTheme.muted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
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
