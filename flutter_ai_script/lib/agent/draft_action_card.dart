/// 訂單草稿確認卡片 —— 「直接送出」與「教我操作」的分叉點。
///
/// 兩條分支最後都打同一個既有下單 API,差別只在誰按下最後那顆按鈕:
///   直接送出 → 這張卡片幫他送
///   教我操作 → 導航到表單頁,預填 + 導覽,使用者自己送
library;

import 'package:flutter/material.dart';

import 'agent_event.dart';
import 'tour.dart';

typedef SubmitOrder = Future<void> Function(OrderDraftEvent draft);

class DraftActionCard extends StatefulWidget {
  const DraftActionCard({
    super.key,
    required this.draft,
    required this.onSubmit,
  });

  final OrderDraftEvent draft;

  /// 呼叫既有下單 endpoint。實作見本檔案底部的 submitDraft。
  final SubmitOrder onSubmit;

  @override
  State<DraftActionCard> createState() => _DraftActionCardState();
}

class _DraftActionCardState extends State<DraftActionCard> {
  bool _busy = false;
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('請確認訂單內容',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 8),
            Text(draft.summary, style: const TextStyle(fontSize: 15, height: 1.5)),
            const SizedBox(height: 16),

            if (_done)
              const Row(
                children: [
                  Icon(Icons.check_circle, size: 20),
                  SizedBox(width: 8),
                  Text('訂單已送出'),
                ],
              )
            else if (draft.expired)
              const Text('這張草稿已過期,請重新跟管家說一次需求。')
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('直接送出訂單'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _busy ? null : _teachMe,
                    child: const Text('帶我操作一次,我想學怎麼用'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await widget.onSubmit(widget.draft);
      if (mounted) setState(() => _done = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('送出失敗:$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _teachMe() {
    final launch = TourLaunchArgs.from(widget.draft);
    if (launch == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('這個服務還沒有教學導覽,可以直接送出')),
      );
      return;
    }
    // 表單頁在 initState 讀 args.prefill 填好欄位,再用 TourRunner 開始導覽。
    Navigator.of(context).pushNamed(launch.route, arguments: launch.args);
  }
}

// ---------------------------------------------------------------------------
// 直接送出的實作:打你們原本的下單 endpoint,不是打 agent。
//
// 關鍵是帶 Idempotency-Key。使用者手滑連點兩下、或網路重試時,
// draft_id 相同就不會變成兩筆訂位。後端要認這個 header 做去重。
// ---------------------------------------------------------------------------
//
// import 'dart:convert';
// import 'package:http/http.dart' as http;
//
// Future<void> submitDraft(OrderDraftEvent draft, {
//   required String baseUrl,
//   required Future<String> Function() tokenProvider,
// }) async {
//   const endpoints = {
//     'restaurant_reservation': '/reservations',
//     'laundry_booking': '/laundry/bookings',
//   };
//   final path = endpoints[draft.service];
//   if (path == null) throw StateError('未知的服務種類: ${draft.service}');
//
//   final response = await http.post(
//     Uri.parse('$baseUrl$path'),
//     headers: {
//       'Authorization': 'Bearer ${await tokenProvider()}',
//       'Content-Type': 'application/json',
//       'Idempotency-Key': draft.draftId,
//     },
//     body: jsonEncode(draft.payload),
//   );
//   if (response.statusCode >= 300) {
//     throw StateError('HTTP ${response.statusCode}: ${utf8.decode(response.bodyBytes)}');
//   }
// }
