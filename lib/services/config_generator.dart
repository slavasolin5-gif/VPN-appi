import 'dart:convert';

class SingBoxConfigGenerator {
  static String generateConfig({required Map<String, dynamic> outboundNode}) {
    final Map<String, dynamic> root = {
      'log': {'level': 'info', 'timestamp': true},
      'dns': {
        'servers': [
          {'tag': 'dns-remote', 'address': 'https://1.1.1.1/dns-query', 'detour': outboundNode['tag'] ?? 'proxy'},
          {'tag': 'dns-direct', 'address': 'local', 'detour': 'direct'}
        ],
        'rules': [
          {'outbound': ['any'], 'server': 'dns-direct'}
        ],
        'strategy': 'prefer_ipv4'
      },
      'inbounds': [
        {
          'type': 'tun',
          'tag': 'tun-in',
          'interface_name': 'tun0',
          'inet4_address': '172.19.0.1/30',
          'mtu': 9000,
          'auto_route': true,
          'strict_route': true,
          'stack': 'mixed',
          'sniff': true
        }
      ],
      'outbounds': [
        outboundNode,
        {'type': 'direct', 'tag': 'direct'},
        {'type': 'block', 'tag': 'block'},
        {'type': 'dns', 'tag': 'dns-out'}
      ],
      'route': {
        'auto_detect_interface': true,
        'rules': [
          {'protocol': 'dns', 'outbound': 'dns-out'},
          {'ip_is_private': true, 'outbound': 'direct'}
        ]
      }
    };
    return const JsonEncoder.withIndent('  ').convert(root);
  }

  static Map<String, dynamic> parseProxyUri(String uriString) {
    final uri = Uri.parse(uriString.trim());
    final tag = uri.fragment.isNotEmpty ? Uri.decodeComponent(uri.fragment) : 'Proxy Node';

    if (uri.scheme == 'vless') {
      final query = uri.queryParameters;
      final Map<String, dynamic> outbound = {
        'type': 'vless',
        'tag': tag,
        'server': uri.host,
        'server_port': uri.port,
        'uuid': uri.userInfo,
        'flow': query['flow'] ?? '',
      };

      if (query['security'] == 'reality') {
        outbound['tls'] = {
          'enabled': true,
          'server_name': query['sni'] ?? uri.host,
          'reality': {
            'enabled': true,
            'public_key': query['pbk'] ?? '',
            'short_id': query['sid'] ?? '',
          },
          'utls': {
            'enabled': true,
            'fingerprint': query['fp'] ?? 'chrome',
          }
        };
      }
      return outbound;
    }

    return {
      'type': 'vless',
      'tag': 'VLESS-Node',
      'server': uri.host.isNotEmpty ? uri.host : '1.1.1.1',
      'server_port': uri.port > 0 ? uri.port : 443,
      'uuid': uri.userInfo.isNotEmpty ? uri.userInfo : '00000000-0000-0000-0000-000000000000',
    };
  }
}
