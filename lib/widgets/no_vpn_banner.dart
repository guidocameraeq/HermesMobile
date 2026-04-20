import 'dart:async';
import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/connectivity_service.dart';

/// Banner sticky arriba de las pantallas que dependen de SQL Server.
/// Muestra "Sin VPN" si la conectividad falló + botón Reintentar.
/// Se oculta automáticamente cuando la conexión vuelve.
class NoVpnBanner extends StatefulWidget {
  /// Mensaje que se muestra si no hay VPN.
  final String mensaje;
  /// Si autoping es true, al montar intenta un ping.
  final bool autoPing;

  const NoVpnBanner({
    super.key,
    this.mensaje = 'Sin conexión VPN. Los datos no pueden actualizarse.',
    this.autoPing = true,
  });

  @override
  State<NoVpnBanner> createState() => _NoVpnBannerState();
}

class _NoVpnBannerState extends State<NoVpnBanner> {
  bool _visible = !ConnectivityService.lastKnown;
  bool _pinging = false;
  StreamSubscription<bool>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = ConnectivityService.onChange.listen((ok) {
      if (mounted) setState(() => _visible = !ok);
    });
    if (widget.autoPing) {
      Future.delayed(const Duration(milliseconds: 400), () async {
        if (!mounted) return;
        await ConnectivityService.ping();
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _retry() async {
    setState(() => _pinging = true);
    await ConnectivityService.ping(timeout: const Duration(seconds: 3));
    if (mounted) setState(() => _pinging = false);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: _visible ? 1 : 0,
        child: _visible
            ? Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                color: AppColors.warning.withOpacity(0.12),
                child: Row(
                  children: [
                    const Icon(Icons.wifi_off, color: AppColors.warning, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Sin conexión VPN',
                              style: TextStyle(color: AppColors.warning,
                                  fontSize: 12, fontWeight: FontWeight.bold)),
                          Text(widget.mensaje,
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _pinging ? null : _retry,
                      icon: _pinging
                          ? const SizedBox(width: 12, height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.warning))
                          : const Icon(Icons.refresh, size: 14, color: AppColors.warning),
                      label: Text(_pinging ? 'Probando...' : 'Reintentar',
                          style: const TextStyle(color: AppColors.warning, fontSize: 12)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}
