import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Ad servers that ad blockers (Private DNS such as AdGuard or NextDNS,
/// Blokada, Pi-hole, hosts files) stop from loading.
const _adHosts = ['googleads.g.doubleclick.net', 'pagead2.googlesyndication.com', 'securepubads.g.doubleclick.net'];
const _adUrl = 'https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js';

/// Private DNS providers whose job is blocking ads.
final _blockingDns = RegExp(r'adguard|nextdns|blokada|adblock|ads|controld|rethink|ahadns|mullvad|libredns|dnsforge|alternate-dns|tiar|blahdns', caseSensitive: false);

const _channel = MethodChannel('file_chat/adblock');

/// True when this phone blocks ads: a blocking Private DNS, an ad-blocking app
/// running as a VPN, or ad servers that do not resolve or load. Offline it is
/// false, so the app is never locked by a bad connection.
Future<bool> detectAdBlocker() async {
  // What Android itself reports (Private DNS, VPN, installed blockers).
  try {
    final r = await _channel.invokeMapMethod<String, Object?>('scan');
    if (r != null) {
      final dns = '${r['privateDns'] ?? ''}';
      if (r['privateDnsMode'] == 'hostname' && _blockingDns.hasMatch(dns)) return true;
      final apps = (r['apps'] as List?) ?? const [];
      if (apps.isNotEmpty && r['vpn'] == true) return true;
    }
  } catch (_) {}

  Future<bool?> dnsBlocked(String host) async {
    try {
      final r = await InternetAddress.lookup(host).timeout(const Duration(seconds: 6));
      return r.isEmpty || r.every((a) => a.isLoopback || a.address == '0.0.0.0' || a.address == '::');
    } on SocketException {
      return true;
    } on TimeoutException {
      return null;
    }
  }

  Future<bool?> loads(String url) async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await c.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 8));
      final res = await req.close().timeout(const Duration(seconds: 8));
      final body = await res.fold<int>(0, (n, b) => n + b.length).timeout(const Duration(seconds: 8));
      return res.statusCode == 200 && body > 1000;
    } on TimeoutException {
      return null;
    } catch (_) {
      return false;
    } finally {
      c.close(force: true);
    }
  }

  // Without a working connection nothing can be told apart.
  if (await dnsBlocked('www.google.com') != false) return false;
  for (final h in _adHosts) {
    if (await dnsBlocked(h) == true) return true;
  }
  // Blockers that filter traffic instead of DNS: the ad script does not load
  // although an ordinary Google page does.
  if (await loads('https://www.google.com/robots.txt') == true &&
      await loads(_adUrl) == false) {
    return true;
  }
  return false;
}

/// Android's ID for this app on this phone. It survives reinstalling, so the
/// proxy can count free questions per phone. Null off Android or in tests.
Future<String?> deviceId() async {
  try {
    return await _channel.invokeMethod<String>('deviceId');
  } catch (_) {
    return null;
  }
}
