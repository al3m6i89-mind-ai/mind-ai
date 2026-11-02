import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'theme.dart';

/// "Version 1.4.3 (21)", centred at the bottom of a screen.
class VersionLabel extends StatefulWidget {
  const VersionLabel({super.key, required this.prefix});
  final String prefix;

  @override
  State<VersionLabel> createState() => _VersionLabelState();
}

class _VersionLabelState extends State<VersionLabel> {
  final _info = PackageInfo.fromPlatform().then<PackageInfo?>((i) => i, onError: (_) => null);

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 10),
          child: FutureBuilder<PackageInfo?>(
            future: _info,
            builder: (context, snap) {
              final i = snap.data;
              if (i == null) return const SizedBox(height: 16);
              final build = i.buildNumber.isEmpty ? '' : ' (${i.buildNumber})';
              return Text('${widget.prefix} ${i.version}$build',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: context.muted));
            },
          ),
        ),
      );
}
