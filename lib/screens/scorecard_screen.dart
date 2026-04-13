import 'package:flutter/material.dart';
import '../models/scorecard_item.dart';
import '../models/session.dart';
import '../services/scorecard_service.dart';
import '../services/auth_service.dart';
import '../services/calculator_service.dart';
import '../widgets/metric_card.dart';
import 'login_screen.dart';

class ScorecardScreen extends StatefulWidget {
  const ScorecardScreen({super.key});

  @override
  State<ScorecardScreen> createState() => _ScorecardScreenState();
}

class _ScorecardScreenState extends State<ScorecardScreen> {
  List<ScorecardItem> _items = [];
  bool _loading = true;
  String _errorMsg = '';
  DateTime _lastUpdate = DateTime.now();

  late int _mes;
  late int _anio;
  late double _ritmo;

  static const _meses = [
    '', 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _mes = now.month;
    _anio = now.year;
    _ritmo = CalculatorService.ritmoEsperado(_anio, _mes);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMsg = '';
    });

    try {
      final items = await ScorecardService.loadScorecard(
        Session.current.vendedorNombre,
        _mes,
        _anio,
      );

      if (!mounted) return;

      if (items.isEmpty) {
        setState(() {
          _loading = false;
          _items = [];
          _errorMsg =
              'Sin métricas asignadas para ${_meses[_mes]} $_anio.\n'
              'El administrador debe cargar los objetivos desde el desktop.';
        });
      } else {
        setState(() {
          _loading = false;
          _items = items;
          _lastUpdate = DateTime.now();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMsg = 'Error al cargar el scorecard:\n${e.toString()}';
      });
    }
  }

  void _logout() {
    AuthService.logout();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  String _fmtTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final vendedor = Session.current.vendedorNombre;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0C10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              vendedor,
              style: const TextStyle(
                color: Color(0xFFF8FAFC),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '${_meses[_mes]} $_anio',
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          // Botón refresh
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF94A3B8)),
            onPressed: _loading ? null : _load,
            tooltip: 'Actualizar',
          ),
          // Logout
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFF94A3B8)),
            onPressed: _logout,
            tooltip: 'Salir',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF2563EB)),
            SizedBox(height: 16),
            Text(
              'Cargando scorecard...',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (_errorMsg.isNotEmpty && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.info_outline, color: Color(0xFF94A3B8), size: 48),
              const SizedBox(height: 16),
              Text(
                _errorMsg,
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: const Color(0xFF2563EB),
      backgroundColor: const Color(0xFF1C2333),
      child: ListView(
        children: [
          // ── Ritmo del mes ────────────────────────────────────
          _RitmoBar(ritmo: _ritmo),

          // ── Tarjetas de métricas ─────────────────────────────
          ..._items.map((item) => MetricCard(item: item, ritmo: _ritmo)),

          // ── Timestamp ───────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Actualizado: ${_fmtTime(_lastUpdate)}  •  Deslizá para refrescar',
              style: const TextStyle(
                color: Color(0xFF475569),
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Barra de ritmo esperado del mes (% días hábiles transcurridos)
class _RitmoBar extends StatelessWidget {
  final double ritmo;

  const _RitmoBar({required this.ritmo});

  @override
  Widget build(BuildContext context) {
    final pct = (ritmo * 100).toStringAsFixed(0);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2333),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule, color: Color(0xFF64748B), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Ritmo esperado del mes',
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      '$pct%',
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: ritmo.clamp(0.0, 1.0),
                    minHeight: 4,
                    backgroundColor: const Color(0xFF2D3748),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF4A9EFF),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
