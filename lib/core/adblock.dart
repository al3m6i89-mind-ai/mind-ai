import 'dart:async';
import 'dart:io';

/// Ad servers that ad blockers (Private DNS such as AdGuard or NextDNS,
/// Blokada, Pi-hole, hosts files) stop from resolving.
const _adHosts = ['googleads.g.doubleclick.net', 'pagead2.googlesyndication.com', 'securepubads.g.doubleclick.net'];

/// True when this phone blocks ad servers. Offline, or when unsure, it is false
/// so the app is never locked by mistake.
Future<bool> detectAdBlocker() async {
  Future<bool?> blocked(String host) async {
    try {
      final r = await InternetAddress.lookup(host).timeout(const Duration(seconds: 6));
      return r.isEmpty || r.every((a) => a.isLoopback || a.address == '0.0.0.0' || a.address == '::');
    } on SocketException {
      return true;
    } on TimeoutException {
      return null;
    }
  }

  // Without a working connection nothing can be told apart.
  final control = await blocked('www.google.com');
  if (control != false) return false;
  var hits = 0;
  for (final h in _adHosts) {
    if (await blocked(h) == true) hits++;
  }
  return hits >= 2;
}
