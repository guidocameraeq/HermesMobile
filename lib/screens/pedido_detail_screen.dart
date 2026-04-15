import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/pedidos_service.dart';

class PedidoDetailScreen extends StatefulWidget {
  final String numero;
  final String cliente;
  final String fecha;
  final String estado;
  final double cantPendiente;

  const PedidoDetailScreen({
    super.key,
    required this.numero,
    required this.cliente,
    required this.fecha,
    required this.estado,
    required this.cantPendiente,
  });

  @override
  State<PedidoDetailScreen> createState() => _PedidoDetailState();
}

class _PedidoDetailState extends State<PedidoDetailScreen> {
  List<Map<String, dynamic>> _lineas = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await PedidosService.getDetalle(widget.numero);
    if (!mounted) return;
    setState(() {
      _lineas = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final label = PedidosService.estadoLabel(widget.estado, widget.cantPendiente);
    final color = Color(PedidosService.estadoColor(widget.estado, widget.cantPendiente));

    // Totales
    double montoTotal = 0, montoPend = 0;
    double cantTotal = 0, cantAplic = 0, cantPend = 0;
    for (final l in _lineas) {
      montoTotal += double.tryParse(l['SubTotalNetoPedidoLocal']?.toString() ?? '0') ?? 0;
      montoPend += double.tryParse(l['SubTotalNetoPendienteLocal']?.toString() ?? '0') ?? 0;
      cantTotal += double.tryParse(l['Cantidad']?.toString() ?? '0') ?? 0;
      cantAplic += double.tryParse(l['CantidadAplicada']?.toString() ?? '0') ?? 0;
      cantPend += double.tryParse(l['CantidadPendiente']?.toString() ?? '0') ?? 0;
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bgSidebar,
        title: Text(widget.numero, style: AppTextStyles.title,
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: AppCardStyle.base(borderColor: color),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(widget.cliente, style: AppTextStyles.title),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(label, style: TextStyle(
                              color: color, fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('Fecha: ${widget.fecha.split(' ').first}', style: AppTextStyles.muted),
                      Text('${_lineas.length} artículos', style: AppTextStyles.muted),
                      const SizedBox(height: 12),
                      // Totales
                      Row(
                        children: [
                          Expanded(child: _TotalBox(
                            label: 'Total pedido',
                            value: '\$ ${_fmt(montoTotal)}',
                          )),
                          const SizedBox(width: 8),
                          if (label == 'Pendiente')
                            Expanded(child: _TotalBox(
                              label: 'Pendiente',
                              value: '\$ ${_fmt(montoPend)}',
                              color: AppColors.success,
                            ))
                          else
                            Expanded(child: _TotalBox(
                              label: 'Aplicado',
                              value: '${cantAplic.toStringAsFixed(0)} / ${cantTotal.toStringAsFixed(0)} uds',
                              color: AppColors.primary,
                            )),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Líneas de artículos
                Text('Artículos del pedido', style: AppTextStyles.title),
                const SizedBox(height: 8),

                ..._lineas.map((l) {
                  final nombre = l['ArticuloNombre']?.toString() ?? '';
                  final codigo = l['ArticuloCodigo']?.toString() ?? '';
                  final linea = l['LineaNombre']?.toString() ?? '';
                  final cant = double.tryParse(l['Cantidad']?.toString() ?? '0') ?? 0;
                  final aplic = double.tryParse(l['CantidadAplicada']?.toString() ?? '0') ?? 0;
                  final pend = double.tryParse(l['CantidadPendiente']?.toString() ?? '0') ?? 0;
                  final precio = double.tryParse(l['Precio']?.toString() ?? '0') ?? 0;
                  final subTotal = double.tryParse(l['SubTotalNetoPedidoLocal']?.toString() ?? '0') ?? 0;
                  final pctCumpl = cant > 0 ? (aplic / cant) : 0.0;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(12),
                    decoration: AppCardStyle.base(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(nombre, style: AppTextStyles.body,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(codigo, style: AppTextStyles.muted),
                            if (linea.isNotEmpty) ...[
                              const Text(' · ', style: AppTextStyles.muted),
                              Expanded(child: Text(linea, style: AppTextStyles.muted,
                                  maxLines: 1, overflow: TextOverflow.ellipsis)),
                            ] else
                              const Spacer(),
                            Text('\$ ${_fmt(subTotal)}',
                                style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Barra de cumplimiento
                        Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: pctCumpl.clamp(0, 1).toDouble(),
                                  minHeight: 6,
                                  backgroundColor: AppColors.border,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    pctCumpl >= 1 ? AppColors.primary : AppColors.success,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '${aplic.toStringAsFixed(0)}/${cant.toStringAsFixed(0)}',
                              style: AppTextStyles.muted,
                            ),
                          ],
                        ),
                        if (pend > 0) ...[
                          const SizedBox(height: 4),
                          Text('Pendiente: ${pend.toStringAsFixed(0)} uds  ·  \$ ${_fmt(precio)} c/u',
                              style: const TextStyle(color: AppColors.warning, fontSize: 11)),
                        ],
                      ],
                    ),
                  );
                }),

                const SizedBox(height: 32),
              ],
            ),
    );
  }

  String _fmt(double v) {
    final s = v.abs().toStringAsFixed(0);
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return v < 0 ? '-${buf.toString()}' : buf.toString();
  }
}

class _TotalBox extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _TotalBox({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.muted),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(
            color: color ?? AppColors.textPrimary,
            fontSize: 14, fontWeight: FontWeight.bold,
          )),
        ],
      ),
    );
  }
}
