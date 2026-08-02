import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_butler_app/design_system/app_spacing.dart';
import 'package:ai_butler_app/design_system/app_typography.dart';
import 'package:ai_butler_app/design_system/theme_extensions.dart';
import 'package:ai_butler_app/domain/services/butler_ai_service.dart';
import 'package:ai_butler_app/providers/ai_providers.dart';
import 'package:ai_butler_app/router/routes.dart';

/// AI 智能管家對話畫面（Requirement 12、13、14）。
class ButlerChatScreen extends ConsumerStatefulWidget {
  const ButlerChatScreen({super.key});

  @override
  ConsumerState<ButlerChatScreen> createState() => _ButlerChatScreenState();
}

/// 對話中的一則訊息。
class _ChatMessage {
  _ChatMessage({required this.isUser, this.text = ''});

  final bool isUser;
  String text;
  List<String> chips = const [];
  List<ButlerChunk> cards = const [];
  bool isStreaming = false;
  bool isFailed = false;
}

class _ButlerChatScreenState extends ConsumerState<ButlerChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  StreamSubscription<ButlerChunk>? _streamSub;
  bool _isThinking = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _streamSub?.cancel();
    super.dispose();
  }

  void _send([String? text]) {
    final value = (text ?? _controller.text).trim();
    if (value.isEmpty) return;
    _controller.clear();

    setState(() {
      _messages.add(_ChatMessage(isUser: true, text: value));
      _isThinking = true;
    });
    _scrollToBottom();

    // 開始接收 AI 串流回覆
    final aiService = ref.read(butlerAiServiceProvider);
    final botMessage = _ChatMessage(isUser: false);
    botMessage.isStreaming = true;
    setState(() => _messages.add(botMessage));

    _streamSub?.cancel();
    _streamSub = aiService.send(value).listen(
      (chunk) {
        setState(() {
          _isThinking = false;
          switch (chunk) {
            case TextDelta(text: final t):
              botMessage.text += t;
            case SuggestionChips(chips: final c):
              botMessage.chips = c;
            case Done():
              botMessage.isStreaming = false;
            case Failed(message: final m):
              botMessage.isStreaming = false;
              botMessage.isFailed = true;
              botMessage.text = m.isNotEmpty ? m : '回應失敗，請重試';
            case CategoryCard() ||
                  VendorCard() ||
                  PrefillCard() ||
                  DraftCard():
              botMessage.cards = [...botMessage.cards, chunk];
          }
        });
        _scrollToBottom();
      },
      onError: (error) {
        setState(() {
          _isThinking = false;
          botMessage.isStreaming = false;
          botMessage.isFailed = true;
          botMessage.text = '連線失敗，請稍後重試';
        });
      },
    );
  }

  void _retry() {
    if (_messages.isEmpty) return;
    // 移除最後一則失敗的 bot 訊息，重新送出最後一則 user 訊息
    final lastUserMsg = _messages.lastWhere((m) => m.isUser,
        orElse: () => _ChatMessage(isUser: true, text: ''));
    if (lastUserMsg.text.isEmpty) return;
    setState(() {
      _messages.removeWhere((m) => !m.isUser && m.isFailed);
    });
    _send(lastUserMsg.text);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: <Widget>[
            Icon(Icons.smart_toy_outlined,
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: AppSpacing.xs),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('AI 智慧管家', style: AppTypography.label),
                Text(
                  _isThinking ? '思考中…' : '待命中',
                  style: AppTypography.caption
                      .copyWith(color: context.butler.secondaryText),
                ),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: _messages.isEmpty
                ? _EmptyPrompts(onPick: _send)
                : _MessageList(
                    messages: _messages,
                    scrollController: _scrollController,
                    isThinking: _isThinking,
                    onChipTap: _send,
                    onCardTap: _handleCardTap,
                    onRetry: _retry,
                  ),
          ),
          _InputBar(controller: _controller, onSend: () => _send()),
        ],
      ),
    );
  }

  void _handleCardTap(ButlerChunk card) {
    switch (card) {
      case CategoryCard(serviceId: final id):
        context.push('${Routes.vendors}?serviceId=$id');
      case VendorCard(vendorId: final id):
        context.push(Routes.vendorDetail(id));
      case PrefillCard(formId: final id):
        context.push(Routes.form(id));
      // 管家沒有寫入權限，草稿要由使用者自己在 GUI 上送出，
      // 所以這裡只負責把他帶到能完成這件事的畫面。
      case DraftCard(kind: final kind):
        context.push(kind == 'profile' ? Routes.account : Routes.orders);
      default:
        break;
    }
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.messages,
    required this.scrollController,
    required this.isThinking,
    required this.onChipTap,
    required this.onCardTap,
    required this.onRetry,
  });

  final List<_ChatMessage> messages;
  final ScrollController scrollController;
  final bool isThinking;
  final void Function(String) onChipTap;
  final void Function(ButlerChunk) onCardTap;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: messages.length + (isThinking ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == messages.length && isThinking) {
          return _ThinkingIndicator();
        }
        final msg = messages[index];
        return Column(
          crossAxisAlignment:
              msg.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: <Widget>[
            _MessageBubble(message: msg),
            // 結構化卡片
            if (msg.cards.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Column(
                  children: msg.cards
                      .map((card) =>
                          _CardWidget(card: card, onTap: () => onCardTap(card)))
                      .toList(),
                ),
              ),
            // 建議快捷選項（Requirement 12.5-6）
            if (msg.chips.isNotEmpty && !msg.isStreaming)
              Padding(
                padding: const EdgeInsets.only(
                    top: AppSpacing.xs, bottom: AppSpacing.sm),
                child: Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xxs,
                  children: msg.chips
                      .map((chip) => ActionChip(
                            label: Text(chip, style: AppTypography.caption),
                            onPressed: () => onChipTap(chip),
                          ))
                      .toList(),
                ),
              ),
            // 失敗重試按鈕（Requirement 12.13）
            if (msg.isFailed)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xxs),
                child: TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('重新產生'),
                ),
              ),
            const SizedBox(height: AppSpacing.xs),
          ],
        );
      },
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        constraints: const BoxConstraints(maxWidth: 300),
        decoration: BoxDecoration(
          color: isUser ? scheme.primary : context.butler.surfaceVariant,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(AppRadius.lg),
            topRight: const Radius.circular(AppRadius.lg),
            bottomLeft: Radius.circular(isUser ? AppRadius.lg : AppRadius.sm),
            bottomRight: Radius.circular(isUser ? AppRadius.sm : AppRadius.lg),
          ),
        ),
        child: Text(
          message.text,
          style: AppTypography.body.copyWith(
            color: isUser ? Colors.white : null,
          ),
        ),
      ),
    );
  }
}

class _ThinkingIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: context.butler.surfaceVariant,
          borderRadius: AppRadius.lgAll,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.butler.secondaryText,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text('思考中…',
                style: AppTypography.caption
                    .copyWith(color: context.butler.secondaryText)),
          ],
        ),
      ),
    );
  }
}

class _CardWidget extends StatelessWidget {
  const _CardWidget({required this.card, required this.onTap});

  final ButlerChunk card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (icon, title, subtitle) = switch (card) {
      CategoryCard(name: final n) => (Icons.category_outlined, n, '查看服務商列表'),
      VendorCard(name: final n, description: final d) => (
          Icons.storefront_outlined,
          n,
          d
        ),
      PrefillCard(summary: final s) => (Icons.edit_note_outlined, '表單已預填', s),
      DraftCard(kind: final k, kindLabel: final l, summary: final s) => (
          k == 'profile'
              ? Icons.person_outline
              : Icons.rate_review_outlined,
          '$l・請確認',
          s
        ),
      _ => (Icons.info_outlined, '資訊', ''),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title, style: AppTypography.label),
        subtitle: subtitle.isNotEmpty
            ? Text(subtitle, style: AppTypography.caption)
            : null,
        trailing: const Icon(Icons.chevron_right, size: 18),
        onTap: onTap,
        dense: true,
      ),
    );
  }
}

class _EmptyPrompts extends StatelessWidget {
  const _EmptyPrompts({required this.onPick});

  final void Function(String) onPick;

  static const List<String> _examples = <String>[
    '今天晚上想吃火鍋，順便叫人來整理家裡',
    '冷氣好像有異味，想找人清洗',
    '幫我訂位這週五晚上 7 點的餐廳',
  ];

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.smart_toy_outlined,
                size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: AppSpacing.sm),
            const Text('告訴我您的生活需求吧', style: AppTypography.title),
            const SizedBox(height: AppSpacing.md),
            for (final example in _examples)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => onPick(example),
                    child: Text(example, textAlign: TextAlign.center),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({required this.controller, required this.onSend});

  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(top: BorderSide(color: context.butler.border)),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: '輸入你的生活需求…',
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
              ),
            ),
            IconButton(
              icon: Icon(Icons.send_rounded,
                  color: Theme.of(context).colorScheme.primary),
              onPressed: onSend,
            ),
          ],
        ),
      ),
    );
  }
}
