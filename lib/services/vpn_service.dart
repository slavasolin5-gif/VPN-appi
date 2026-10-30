import 'dart:async';
import 'package:flutter/services.dart';

enum VpnConnectionState { disconnected, connecting, connected, error }

class VpnTrafficStats {
  final VpnConnectionState state;
  final int uploadSpeedBytes;
  final int downloadSpeedBytes;
  final int uploadTotalBytes;
  final int downloadTotalBytes;

  const VpnTrafficStats({
    required this.state,
    this.uploadSpeedBytes = 0,
    this.downloadSpeedBytes = 0,
    this.uploadTotalBytes = 0,
    this.downloadTotalBytes = 0,
  });

  String get uploadSpeedFormatted => _formatSpeed(uploadSpeedBytes);
  String get downloadSpeedFormatted => _formatSpeed(downloadSpeedBytes);

  static String _formatSpeed(int bytes) {
    if (bytes < 1024) return '$bytes B/s';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB/s';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB/s';
  }
}

class VpnControllerService {
  static const MethodChannel _methodChannel = MethodChannel('com.example.singbox_vpn/channel');
  static const EventChannel _statsEventChannel = EventChannel('com.example.singbox_vpn/stats');
  static const EventChannel _logsEventChannel = EventChannel('com.example.singbox_vpn/logs');

  final StreamController<VpnTrafficStats> _statsController = StreamController<VpnTrafficStats>.broadcast();
  final StreamController<String> _logsController = StreamController<String>.broadcast();

  Stream<VpnTrafficStats> get statsStream => _statsController.stream;
  Stream<String> get logsStream => _logsController.stream;

  VpnConnectionState _currentState = VpnConnectionState.disconnected;
  VpnConnectionState get currentState => _currentState;

  VpnControllerService() {
    _initEventStreams();
  }

  void _initEventStreams() {
    _statsEventChannel.receiveBroadcastStream().listen((dynamic event) {
      if (event is Map) {
        final statusStr = event['status'] as String? ?? 'disconnected';
        final upSpeed = (event['uploadSpeed'] as num?)?.toInt() ?? 0;
        final downSpeed = (event['downloadSpeed'] as num?)?.toInt() ?? 0;
        final upTotal = (event['uploadTotal'] as num?)?.toInt() ?? 0;
        final downTotal = (event['downloadTotal'] as num?)?.toInt() ?? 0;

        VpnConnectionState state = statusStr == 'connected'
            ? VpnConnectionState.connected
            : statusStr == 'connecting'
                ? VpnConnectionState.connecting
                : VpnConnectionState.disconnected;

        _currentState = state;
        _statsController.add(VpnTrafficStats(
          state: state,
          uploadSpeedBytes: upSpeed,
          downloadSpeedBytes: downSpeed,
          uploadTotalBytes: upTotal,
          downloadTotalBytes: downTotal,
        ));
      }
    }, onError: (_) {
      _currentState = VpnConnectionState.error;
      _statsController.add(const VpnTrafficStats(state: VpnConnectionState.error));
    });

    _logsEventChannel.receiveBroadcastStream().listen((dynamic event) {
      if (event is String) _logsController.add(event);
    });
  }

  Future<bool> startVpn(String configJson) async {
    try {
      _currentState = VpnConnectionState.connecting;
      _statsController.add(const VpnTrafficStats(state: VpnConnectionState.connecting));
      final result = await _methodChannel.invokeMethod<bool>('startVpn', {'config': configJson});
      return result ?? false;
    } catch (_) {
      _currentState = VpnConnectionState.error;
      _statsController.add(const VpnTrafficStats(state: VpnConnectionState.error));
      return false;
    }
  }

  Future<bool> stopVpn() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('stopVpn');
      _currentState = VpnConnectionState.disconnected;
      _statsController.add(const VpnTrafficStats(state: VpnConnectionState.disconnected));
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _statsController.close();
    _logsController.close();
  }
}
