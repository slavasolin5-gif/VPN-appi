import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/vpn_service.dart';
import '../services/config_generator.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final VpnControllerService _vpnService = VpnControllerService();
  final TextEditingController _urlController = TextEditingController();

  VpnTrafficStats _stats = const VpnTrafficStats(state: VpnConnectionState.disconnected);
  final List<String> _logs = [];
  int _pingMs = -1;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _vpnService.statsStream.listen((stats) {
      if (mounted) setState(() => _stats = stats);
    });

    _vpnService.logsStream.listen((log) {
      if (mounted) {
        setState(() {
          _logs.insert(0, log);
          if (_logs.length > 50) _logs.removeLast();
        });
      }
    });

    _urlController.text =
        'vless://b831381d-6324-4d53-ad4f-8cda48b30811@world.cloudflare.com:443?security=reality&sni=yahoo.com&fp=chrome&pbk=1U4rZJ5dG6m7k8L9_DemoPublicKey&sid=12ab#Fast-Reality-01';
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _vpnService.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _toggleVpn() async {
    if (_stats.state == VpnConnectionState.connected) {
      await _vpnService.stopVpn();
      setState(() => _pingMs = -1);
    } else {
      final input = _urlController.text.trim();
      if (input.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Введите ссылку на узел или JSON конфиг')),
        );
        return;
      }

      String configJson = input.startsWith('{')
          ? input
          : SingBoxConfigGenerator.generateConfig(
              outboundNode: SingBoxConfigGenerator.parseProxyUri(input),
            );

      final ok = await _vpnService.startVpn(configJson);
      if (ok) {
        setState(() => _pingMs = 45);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _stats.state == VpnConnectionState.connected;
    final isConnecting = _stats.state == VpnConnectionState.connecting;

    final primaryColor = isConnected
        ? const Color(0xFF10B981) // Изумрудный
        : isConnecting
            ? const Color(0xFFF59E0B) // Янтарный
            : const Color(0xFF6366F1); // Индиго

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.shield_rounded, color: Color(0xFF818CF8)),
            SizedBox(width: 8),
            Text('SingBox VPN', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.terminal_rounded, color: Colors.white70),
            onPressed: _showLogsModal,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            children: [
              // Значок пинга
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.network_check_rounded,
                        size: 18, color: isConnected ? const Color(0xFF34D399) : Colors.white38),
                    const SizedBox(width: 6),
                    Text(
                      _pingMs > 0 ? '$_pingMs ms' : 'Пинг: --',
                      style: TextStyle(
                        color: _pingMs > 0 ? const Color(0xFF34D399) : Colors.white60,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // Большая круглая кнопка подключения
              ScaleTransition(
                scale: isConnected ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
                child: GestureDetector(
                  onTap: isConnecting ? null : _toggleVpn,
                  child: Container(
                    width: 190,
                    height: 190,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [primaryColor.withOpacity(0.85), primaryColor],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: primaryColor.withOpacity(isConnected ? 0.45 : 0.25),
                          blurRadius: isConnected ? 36 : 18,
                          spreadRadius: isConnected ? 8 : 2,
                        ),
                      ],
                    ),
                    child: Center(
                      child: isConnecting
                          ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 3)
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  isConnected ? Icons.stop_rounded : Icons.power_settings_new_rounded,
                                  size: 60,
                                  color: Colors.white,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  isConnected ? 'ОТКЛЮЧИТЬ' : 'ПОДКЛЮЧИТЬ',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.2,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              Text(
                isConnected
                    ? 'Подключено • Защищено'
                    : isConnecting
                        ? 'Подключение...'
                        : 'Отключено',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryColor),
              ),

              const SizedBox(height: 32),

              // Карточка скорости трафика
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.arrow_downward_rounded, size: 16, color: Color(0xFF38BDF8)),
                            SizedBox(width: 4),
                            Text('ЗАГРУЗКА', style: TextStyle(color: Colors.white54, fontSize: 11)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(_stats.downloadSpeedFormatted,
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Container(height: 36, width: 1, color: Colors.white12),
                    Column(
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.arrow_upward_rounded, size: 16, color: Color(0xFFA78BFA)),
                            SizedBox(width: 4),
                            Text('ОТДАЧА', style: TextStyle(color: Colors.white54, fontSize: 11)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(_stats.uploadSpeedFormatted,
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Поле ввода ссылки на подписку
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Ссылка на узел или подписку',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _urlController,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      maxLines: 2,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        hintText: 'vless://..., vmess://... или sing-box JSON',
                        hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final data = await Clipboard.getData('text/plain');
                        if (data?.text != null) {
                          setState(() => _urlController.text = data!.text!);
                        }
                      },
                      icon: const Icon(Icons.paste_rounded, size: 16),
                      label: const Text('Вставить из буфера'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF334155),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLogsModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Container(
          height: 360,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Логи ядра sing-box',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const Divider(color: Colors.white12),
              Expanded(
                child: ListView.builder(
                  itemCount: _logs.length,
                  itemBuilder: (context, index) => Text(
                    _logs[index],
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFF94A3B8)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
