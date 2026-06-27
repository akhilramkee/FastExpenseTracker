class TailscaleDevice {
  final String hostname;
  final String magicDnsName;
  final String os;
  final bool authorized;
  final DateTime? lastSeen;
  final bool likelyOnline;

  const TailscaleDevice({
    required this.hostname,
    required this.magicDnsName,
    required this.os,
    required this.authorized,
    this.lastSeen,
    this.likelyOnline = false,
  });

  factory TailscaleDevice.fromApiJson(Map<String, dynamic> json) {
    final hostname = (json['hostname'] as String?)?.trim() ?? '';
    final magicDnsName = (json['name'] as String?)?.trim() ?? hostname;
    final connectivity = json['clientConnectivity'];
    final endpoints = connectivity is Map
        ? connectivity['endpoints'] as List<dynamic>?
        : null;
    final hasEndpoints = endpoints != null && endpoints.isNotEmpty;

    DateTime? lastSeen;
    final lastSeenRaw = json['lastSeen'] as String?;
    if (lastSeenRaw != null && lastSeenRaw.isNotEmpty) {
      lastSeen = DateTime.tryParse(lastSeenRaw);
    }

    final recentlyActive = lastSeen != null &&
        DateTime.now().toUtc().difference(lastSeen.toUtc()).inMinutes < 5;

    return TailscaleDevice(
      hostname: hostname.isNotEmpty ? hostname : _shortNameFromDns(magicDnsName),
      magicDnsName: magicDnsName,
      os: (json['os'] as String?) ?? 'unknown',
      authorized: json['authorized'] as bool? ?? true,
      lastSeen: lastSeen,
      likelyOnline: hasEndpoints || recentlyActive,
    );
  }

  static String _shortNameFromDns(String dnsName) {
    final dot = dnsName.indexOf('.');
    return dot > 0 ? dnsName.substring(0, dot) : dnsName;
  }
}
