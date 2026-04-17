import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/scorecard_item.dart';
import '../models/session.dart';
import '../services/scorecard_service.dart';
import '../services/calculator_service.dart';
import '../widgets/metric_card.dart';
import '../widgets/month_selector.dart';
import '../widgets/skeleton_card.dart';
import '../widgets/app_drawer.dart';
import '../widgets/mes_picker_sheet.dart';
import 'drilldowns/facturacion_drilldown.dart';
import 'drilldowns/tasa_conversion_drilldown.dart';
import 'drilldowns/foco_drilldown.dart';
import 'drilldowns/aperturas_drilldown.dart';
import 'drilldowns/reactivacion_drilldown.dart';
import 'drilldowns/activaciones_drilldown.dart';
import 'drilldowns/incorporaciones_cargas_drilldown.dart';
import '../widgets/cuotas_grid.dart';

class ScorecardTab extends StatefulWidget {
  const ScorecardTab({super.key});

  @override
  State<ScorecardTab> createState() => _ScorecardTabState();
}

class _ScorecardTabState extends State<ScorecardTab>
    with AutomaticKeepAliveClientMixin {
  List<ScorecardItem> _items = [];
  bool _loading = true;
  String _errorMsg = '';
  DateTime _lastUpdate = DateTime.now();
  bool _inclPend = false;

  late int _mes;
  late int _anio;
  late double _ritmo;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _mes = now.month;
    _anio = now.year;
    _ritmo = CalculatorService.ritmoEsperado(_anio, _mes);
    _load();
  }

  void _onMonthChanged(int mes, int anio) {
    setState(() {
      _mes = mes;
      _anio = anio;
      _ritmo = CalculatorService.ritmoEsperado(_anio, _mes);
    });
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
        inclPendientes: _inclPend,
      );

      if (!mounted) return;

      if (items.isEmpty) {
        setState(() {
          _loading = false;
          _items = [];
          _errorMsg =
              'Sin métricas asignadas para ${MonthSelector.mesNombre(_mes)} $_anio.\n'
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

  void _openDrilldown(ScorecardItem item) {
    final vendedor = Session.current.vendedorNombre;
    Widget? screen;

    switch (item.funcionId) {
      case 'facturacion':
        screen = FacturacionDrilldown(vendedor: vendedor, mes: _mes, anio: _anio);
        break;
      case 'tasa_conversion':
        screen = TasaConversionDrilldown(vendedor: vendedor, mes: _mes, anio: _anio);
        break;
      case 'foco_unidades':
      case 'incorporaciones':
        screen = FocoDrilldown(vendedor: vendedor, mes: _mes, anio: _anio, paramsJson: item.paramsJson);
        break;
      case 'aperturas':
        screen = AperturasDrilldown(vendedor: vendedor, mes: _mes, anio: _anio);
        break;
      case 'reactivacion':
        screen = ReactivacionDrilldown(vendedor: vendedor, mes: _mes, anio: _anio, paramsJson: item.paramsJson);
        break;
      case 'incorporaciones_cargas':
        screen = IncorporacionesCargasDrilldown(vendedor: vendedor, mes: _mes, anio: _anio, paramsJson: item.paramsJson);
        break;
      case 'activaciones':
        screen = ActivacionesDrilldown(vendedor: vendedor, mes: _mes, anio: _anio);
        break;
    }

    if (screen != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen!));
    }
  }

  String _fmtTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final vendedor = Session.current.vendedorNombre;

    return Scaffold(
      backgroundColor: AppColors.bg,
      drawer: const AppDrawer(currentTab: 0),
      appBar: AppBar(
        backgroundColor: AppColors.bgSidebar,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(vendedor, style: AppTextStyles.title),
            const Text('Scorecard', style: AppTextStyles.caption),
          ],
        ),
        actions: [
          // Toggle pendientes
          Tooltip(
            message: _inclPend ? 'Mostrando + Pendientes' : 'Solo Facturado',
            child: IconButton(
              icon: Icon(
                _inclPend ? Icons.inventory_2 : Icons.inventory_2_outlined,
                color: _inclPend ? AppColors.accent : AppColors.textMuted,
                size: 20,
              ),
              onPressed: () {
                setState(() => _inclPend = !_inclPend);
                _load();
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textMuted),
            onPressed: _loading ? null : _load,
            tooltip: 'Actualizar',
          ),
          _mesButton(),
          const AppBarAvatar(),
        ],
      ),
      body: Column(
        children: [
          if (_esMesNoActual()) _bannerMesViendo(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  bool _esMesNoActual() {
    final now = DateTime.now();
    return _mes != now.month || _anio != now.year;
  }

  Widget _bannerMesViendo() {
    const meses = ['', 'Enero','Febrero','Marzo','Abril','Mayo','Junio',
                   'Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre'];
    return GestureDetector(
      onTap: _abrirPickerMes,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: AppColors.warning.withOpacity(0.15),
        child: Row(
          children: [
            const Icon(Icons.history, color: AppColors.warning, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text(
              'Viendo ${meses[_mes]} $_anio',
              style: const TextStyle(color: AppColors.warning, fontSize: 12, fontWeight: FontWeight.w600),
            )),
            GestureDetector(
              onTap: _volverMesActual,
              child: const Text('Volver a actual',
                  style: TextStyle(color: AppColors.warning, fontSize: 11,
                      decoration: TextDecoration.underline)),
            ),
          ],
        ),
      ),
    );
  }

  void _volverMesActual() {
    final now = DateTime.now();
    _onMonthChanged(now.month, now.year);
  }

  Widget _mesButton() {
    return IconButton(
      icon: Icon(Icons.calendar_month,
          color: _esMesNoActual() ? AppColors.warning : AppColors.textMuted, size: 20),
      onPressed: _abrirPickerMes,
      tooltip: 'Cambiar mes',
    );
  }

  void _abrirPickerMes() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => MesPickerSheet(
        mesActual: _mes,
        anioActual: _anio,
        onPicked: (m, a) {
          Navigator.pop(context);
          _onMonthChanged(m, a);
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView(
        children: const [
          SkeletonCard(),
          SkeletonCard(),
          SkeletonCard(),
        ],
      );
    }

    if (_errorMsg.isNotEmpty && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.info_outline, color: AppColors.textMuted, size: 48),
              const SizedBox(height: 16),
              Text(
                _errorMsg,
                style: AppTextStyles.caption,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
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
      color: AppColors.primary,
      backgroundColor: AppColors.bgCard,
      child: ListView(
        children: [
          _RitmoBar(ritmo: _ritmo),
          ..._items.map((item) => MetricCard(
                item: item,
                ritmo: _ritmo,
                onTap: item.cargado && !item.error ? () => _openDrilldown(item) : null,
              )),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Actualizado: ${_fmtTime(_lastUpdate)}  •  Deslizá para refrescar',
              style: AppTextStyles.muted,
              textAlign: TextAlign.center,
            ),
          ),
          // Cuotas por cliente (carga bajo demanda)
          CuotasGrid(mes: _mes, anio: _anio, inclPend: _inclPend),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

/// Barra de ritmo esperado del mes.
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
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule, color: AppColors.textMuted, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Ritmo esperado del mes',
                        style: AppTextStyles.caption),
                    Text('$pct%',
                        style: AppTextStyles.caption
                            .copyWith(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: ritmo.clamp(0.0, 1.0),
                    minHeight: 4,
                    backgroundColor: AppColors.border,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(AppColors.accent),
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
