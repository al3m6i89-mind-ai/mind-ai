import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../core/ai.dart';
import '../core/store.dart';
import '../core/strings.dart';
import 'theme.dart';

/// The owner's accounts. Only used to show the button; the proxy decides who
/// may read the dashboard (ADMIN_EMAILS in proxy/wrangler.toml).
class Admin {
  static const emails = {'5azuy2@gmail.com', 'al3m6i89@gmail.com'};
  static bool isOwner(String? email) => email != null && emails.contains(email.toLowerCase());
}

/// Loads the dashboard numbers from the proxy.
Future<Map<String, dynamic>> loadDashboard(AppStore store, {http.Client? client, Proxy proxy = Proxy.build}) async {
  final session = await store.aiSession()
    ..remove('x-question-id');
  final c = client ?? http.Client();
  final res = await c
      .get(Uri.parse('${proxy.base}/admin'), headers: {'x-app-token': proxy.token, ...session})
      .timeout(const Duration(seconds: 20));
  if (res.statusCode == 403) throw const _AdminError('adminDenied');
  if (res.statusCode != 200) {
    throw _AdminError('adminFailed', 'HTTP ${res.statusCode} ${res.headers['x-proxy-error'] ?? ''}'.trim());
  }
  return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
}

/// Blocks or unblocks an account through the proxy.
Future<bool> setUserBlocked(AppStore store, String uid, bool block, {http.Client? client, Proxy proxy = Proxy.build}) async {
  final session = await store.aiSession()
    ..remove('x-question-id');
  final c = client ?? http.Client();
  final res = await c
      .post(Uri.parse('${proxy.base}/admin'),
          headers: {'x-app-token': proxy.token, 'content-type': 'application/json', ...session},
          body: jsonEncode({'uid': uid, 'block': block}))
      .timeout(const Duration(seconds: 20));
  return res.statusCode == 200;
}

class _AdminError implements Exception {
  const _AdminError(this.key, [this.detail]);
  final String key;

  /// Shown under the message, so a screenshot tells what went wrong.
  final String? detail;
}

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key, this.load, this.block});

  /// For tests: replace the network calls.
  final Future<Map<String, dynamic>> Function()? load;
  final Future<bool> Function(String uid, bool block)? block;

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  String? _detail;
  bool _loading = true;
  String _q = '';
  bool _onlyBlocked = false;

  Future<void> _setBlocked(Map<String, dynamic> u, bool block, S s) async {
    final store = context.read<AppStore>();
    final uid = '${u['uid']}';
    if (block) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(s.t('aBlockQ', {'e': '${u['email'] == '' ? uid : u['email']}'})),
          content: Text(s.t('aBlockText')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('cancel'))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: context.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(s.t('aBlock')),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    bool done;
    try {
      done = await (widget.block?.call(uid, block) ?? setUserBlocked(store, uid, block));
    } catch (_) {
      done = false;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(done ? s.t('aDone') : s.t('adminFailed')),
      behavior: SnackBarBehavior.floating,
    ));
    if (done) await _refresh();
  }

  void _details(Map<String, dynamic> u, S s, int now) {
    String date(Object? ms) {
      if (ms is! num || ms == 0) return '—';
      final d = DateTime.fromMillisecondsSinceEpoch(ms.toInt()).toLocal();
      String two(int n) => n.toString().padLeft(2, '0');
      return '${d.year}/${two(d.month)}/${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
    }

    final blocked = (u['blocked'] ?? 0) != 0;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${u['email'] == '' ? u['uid'] : u['email']}',
                textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(u['provider'] == 'google.com' ? 'Google' : s.t('methodEmail'), style: TextStyle(color: context.muted)),
            const SizedBox(height: 12),
            _kv(s.t('aFirst'), date(u['first'])),
            _kv(s.t('fLastIn'), date(u['last'])),
            _kv(s.t('aQuestionsToday'), '${u['today'] ?? 0}'),
            _kv(s.t('aQuestionsAll'), '${u['questions'] ?? 0}'),
            _kv(s.t('voice'), '${u['voice'] ?? 0}'),
            _kv(s.t('plans'), u['premiumUntil'] != null ? s.t('aPremiumTill', {'d': date(u['premiumUntil'])}) : s.t('planFree')),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: Text(s.t('aCopyId')),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: '${u['uid']}'));
                Navigator.pop(ctx);
              },
            ),
            const SizedBox(height: 4),
            blocked
                ? FilledButton.icon(
                    icon: const Icon(Icons.lock_open_rounded),
                    label: Text(s.t('aUnblock')),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _setBlocked(u, false, s);
                    },
                  )
                : FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: context.danger),
                    icon: const Icon(Icons.block_rounded),
                    label: Text(s.t('aBlock')),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _setBlocked(u, true, s);
                    },
                  ),
          ]),
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Text(k, style: TextStyle(color: context.muted, fontSize: 13.5)),
          const SizedBox(width: 12),
          Expanded(child: Text(v, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
      _detail = null;
    });
    try {
      final store = context.read<AppStore>();
      final d = await (widget.load?.call() ?? loadDashboard(store));
      if (mounted) setState(() => _data = d);
    } on _AdminError catch (e) {
      if (mounted) {
        setState(() {
          _error = e.key;
          _detail = e.detail;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'adminFailed';
          _detail = e.runtimeType.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S(context.watch<AppStore>().lang);
    final d = _data;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('admin')),
        actions: [
          IconButton(tooltip: s.t('refresh'), icon: const Icon(Icons.refresh_rounded), onPressed: _loading ? null : _refresh),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: d == null
              ? ListView(children: [
                  const SizedBox(height: 120),
                  Center(
                    child: _loading
                        ? const CircularProgressIndicator()
                        : Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                                '${s.t(_error ?? 'adminFailed')}${_detail == null ? '' : '\n\n$_detail'}',
                                textAlign: TextAlign.center),
                          ),
                  ),
                ])
              : _body(context, s, d),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, S s, Map<String, dynamic> d) {
    final t = (d['totals'] as Map).cast<String, dynamic>();
    final days = (d['days'] as List).cast<Map>();
    final users = (d['users'] as List).cast<Map>();
    final q = _q.trim().toLowerCase();
    final shown = users
        .where((u) => q.isEmpty || '${u['email']}'.toLowerCase().contains(q) || '${u['uid']}'.toLowerCase().contains(q))
        .where((u) => !_onlyBlocked || (u['blocked'] ?? 0) != 0)
        .toList();
    String n(String k) => '${t[k] ?? 0}';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(s.t(_error!), style: TextStyle(color: context.danger)),
          ),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.9,
          children: [
            _Stat(icon: Icons.people_alt_rounded, label: s.t('aUsers'), value: n('users')),
            _Stat(icon: Icons.person_add_alt_1_rounded, label: s.t('aNewToday'), value: n('newToday')),
            _Stat(icon: Icons.bolt_rounded, label: s.t('aActiveToday'), value: n('activeToday')),
            _Stat(icon: Icons.date_range_rounded, label: s.t('aActive7'), value: n('active7')),
            _Stat(icon: Icons.workspace_premium_rounded, label: s.t('aSubscribers'), value: n('subscribers'), gold: true),
            _Stat(icon: Icons.chat_bubble_rounded, label: s.t('aQuestionsToday'), value: n('questionsToday')),
            _Stat(icon: Icons.mic_rounded, label: s.t('aVoiceToday'), value: n('voiceToday')),
            _Stat(icon: Icons.forum_rounded, label: s.t('aQuestionsAll'), value: n('questionsAll')),
          ],
        ),
        const SizedBox(height: 10),
        Text(s.t('aBySignIn', {'g': n('byGoogle'), 'e': n('byEmail')}), style: TextStyle(color: context.muted, fontSize: 13)),
        const SizedBox(height: 18),
        Text(s.t('aLast14'), style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        _Bars(days: days),
        const SizedBox(height: 22),
        Text(s.t('aUsersList', {'n': '${users.length}'}), style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        TextField(
          onChanged: (v) => setState(() => _q = v),
          decoration: InputDecoration(
            hintText: s.t('aSearchEmail'),
            prefixIcon: Icon(Icons.search_rounded, color: context.muted),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilterChip(
            avatar: const Icon(Icons.block_rounded, size: 16),
            label: Text('${s.t('aBlocked')} (${n('blocked')})'),
            selected: _onlyBlocked,
            onSelected: (v) => setState(() => _onlyBlocked = v),
          ),
        ),
        const SizedBox(height: 4),
        for (final u in shown)
          _UserRow(
            u: u.cast<String, dynamic>(),
            s: s,
            now: (d['now'] as num).toInt(),
            onTap: () => _details(u.cast<String, dynamic>(), s, (d['now'] as num).toInt()),
          ),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: Text(s.t('noResults'), style: TextStyle(color: context.muted))),
          ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, required this.value, this.gold = false});
  final IconData icon;
  final String label;
  final String value;
  final bool gold;

  @override
  Widget build(BuildContext context) {
    final color = gold ? const Color(0xFFE0A100) : Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(color: context.surface2, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        Row(children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.muted, fontSize: 12.5)),
          ),
        ]),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

/// Questions per day, last 14 days.
class _Bars extends StatelessWidget {
  const _Bars({required this.days});
  final List<Map> days;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    int v(Map d) => ((d['ask'] ?? 0) as num).toInt() + ((d['voice'] ?? 0) as num).toInt();
    final top = days.fold<int>(1, (m, d) => v(d) > m ? v(d) : m);
    return Container(
      height: 150,
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
      decoration: BoxDecoration(color: context.surface2, borderRadius: BorderRadius.circular(16)),
      child: Directionality(
        // Oldest on the left, like any chart, in both languages.
        textDirection: TextDirection.ltr,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final d in days)
            Expanded(
              child: Tooltip(
                message: '${d['day']}: ${v(d)}',
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text('${v(d)}', style: TextStyle(fontSize: 9.5, color: context.muted)),
                  const SizedBox(height: 2),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                    height: 90 * v(d) / top + 2,
                    decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(4)),
                  ),
                  const SizedBox(height: 4),
                  Text('${d['day']}'.substring(8), style: TextStyle(fontSize: 9.5, color: context.muted)),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({required this.u, required this.s, required this.now, required this.onTap});
  final Map<String, dynamic> u;
  final S s;
  final int now;
  final VoidCallback onTap;

  String _ago(int t) {
    final m = ((now - t) / 60000).floor();
    if (m < 1) return s.t('aNow');
    if (m < 60) return s.t('aMinAgo', {'n': '$m'});
    if (m < 1440) return s.t('aHourAgo', {'n': '${m ~/ 60}'});
    return s.t('aDayAgo', {'n': '${m ~/ 1440}'});
  }

  @override
  Widget build(BuildContext context) {
    final google = u['provider'] == 'google.com';
    final premium = u['premiumUntil'] != null;
    final blocked = (u['blocked'] ?? 0) != 0;
    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: CircleAvatar(
        radius: 17,
        backgroundColor: context.surface2,
        child: Icon(google ? Icons.g_mobiledata_rounded : Icons.alternate_email_rounded, size: google ? 26 : 18),
      ),
      title: Row(children: [
        Flexible(
          child: Text('${u['email'] == '' ? u['uid'] : u['email']}',
              maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr,
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        if (premium) ...[
          const SizedBox(width: 6),
          const Icon(Icons.workspace_premium_rounded, size: 16, color: Color(0xFFE0A100)),
        ],
        if (blocked) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(color: context.danger.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
            child: Text(s.t('aBlockedTag'), style: TextStyle(color: context.danger, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ],
      ]),
      trailing: Icon(Icons.chevron_right_rounded, color: context.muted),
      subtitle: Text(
        s.t('aUserLine', {
          'today': '${u['today'] ?? 0}',
          'all': '${u['questions'] ?? 0}',
          'last': _ago((u['last'] as num).toInt()),
        }),
        style: TextStyle(color: context.muted, fontSize: 12),
      ),
    );
  }
}
