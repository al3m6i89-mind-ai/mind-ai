import 'package:flutter/material.dart';

import '../core/strings.dart';
import '../core/updates.dart';
import 'theme.dart';

/// The download-and-install sheet for a new release.
Future<void> showUpdateSheet(BuildContext context, Updater u, S s) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _UpdateSheet(u: u, s: s),
    );

class _UpdateSheet extends StatelessWidget {
  const _UpdateSheet({required this.u, required this.s});
  final Updater u;
  final S s;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return ListenableBuilder(
      listenable: u,
      builder: (context, _) {
        final r = u.latest;
        final notes = r == null ? '' : (s.ar ? r.notesAr : r.notesEn);
        final busy = u.state == UpdateState.downloading;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Icon(Icons.system_update_rounded, size: 44, color: primary),
              const SizedBox(height: 10),
              Text(s.t('updateAvailable'),
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              if (r != null)
                Text(s.t('updateVersion', {'v': r.version}),
                    textAlign: TextAlign.center, style: TextStyle(color: context.muted)),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(s.t('whatsNew'), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(notes, style: const TextStyle(height: 1.5)),
              ],
              const SizedBox(height: 18),
              if (busy) ...[
                LinearProgressIndicator(value: u.progress == 0 ? null : u.progress, minHeight: 6, borderRadius: BorderRadius.circular(6)),
                const SizedBox(height: 8),
                Text(s.t('downloadingP', {'p': '${(u.progress * 100).round()}'}),
                    textAlign: TextAlign.center, style: TextStyle(color: context.muted)),
                const SizedBox(height: 10),
              ],
              if (u.error != null) ...[
                Text(s.t('upd_${u.error}'), textAlign: TextAlign.center, style: TextStyle(color: context.danger, height: 1.4)),
                const SizedBox(height: 10),
              ],
              SizedBox(
                height: 50,
                child: FilledButton.icon(
                  icon: Icon(u.state == UpdateState.ready ? Icons.install_mobile_rounded : Icons.download_rounded),
                  label: Text(s.t(u.state == UpdateState.ready ? 'installNow' : 'updateNow')),
                  onPressed: busy ? null : u.install,
                ),
              ),
              TextButton(onPressed: () => Navigator.pop(context), child: Text(s.t('later'))),
            ]),
          ),
        );
      },
    );
  }
}

/// A slim card at the top of the chat screen while a new release waits.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key, required this.u, required this.s});
  final Updater u;
  final S s;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: u,
        builder: (context, _) {
          if (!u.hasUpdate) return const SizedBox.shrink();
          final primary = Theme.of(context).colorScheme.primary;
          return Container(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            padding: const EdgeInsetsDirectional.fromSTEB(14, 6, 6, 6),
            decoration: BoxDecoration(color: primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Icon(Icons.system_update_rounded, color: primary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text('${s.t('updateAvailable')} · ${u.latest!.version}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              FilledButton(
                style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: () => showUpdateSheet(context, u, s),
                child: Text(s.t('updateNow')),
              ),
            ]),
          );
        },
      );
}
