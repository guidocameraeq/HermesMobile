import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/pedidos_service.dart';
import '../services/cliente_router.dart';

class PedidoDetailScreen extends StatefulWidget {
  final String numero;
  final String cliente;
  final String? clienteCodigo;
  final String fecha;
  final String estado;
  final double cantPendiente;

  const PedidoDetailScreen({
    super.key,
    required this.numero,
    required this.cliente,
    this.clienteCodigo,
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
                            child: GestureDetector(
                              onTap: widget.clienteCodigo != null
                                  ? () => ClienteRouter.open(context,
                                      widget.clienteCodigo, nombre: widget.cliente)
                                  : null,
                              child: Row(
                                children: [
                                  Flexible(child: Text(widget.cliente, style: AppTextStyles.title,
                                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                                  if (widget.clienteCodigo != null)
                                    const Padding(
                                      padding: EdgeInsets.only(left: 4),
                                      child: Icon(Icons.chevron_right,
                                          color: AppColors.accent, size: 16),
                                    ),
                                ],
                              ),
                            ),
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
                              label: 'Monto pendiente',
                              value: '\$ ${_fmt(montoPend)}',
                              color: AppColors.success,
                            ))
                          else
                            Expanded(child: _TotalBox(
                              label: 'Artículos',
                              value: '${_lineas.length} items',
                            )),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Disclaimer para cerrados
                if (label == 'Cerrado') ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.textMuted.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, color: AppColors.textMuted, size: 16),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Pedido cerrado. La facturación real puede diferir '
                            'del pedido original (sujeto a disponibilidad de stock).',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Líneas de artículos
                Text('Artículos del pedido', style: AppTextStyles.title),
                const SizedBox(height: 8),

                ..._lineas.map((l) {
                  final nombre = l['ArticuloNombre']?.toString() ?? '';
                  final codigo = l['ArticuloCodigo']?.toString() ?? '';
                  final linea = l['LineaNombre']?.toString() ?? '';
                  final cant = double.tryParse(l['Cantidad']?.toString() ?? '0') ?? 0;
                  final subTotal = double.tryParse(l['SubTotalNetoPedidoLocal']?.toString() ?? '0') ?? 0;

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
                        const SizedBox(height: 4),
                        Text('${cant.toStringAsFixed(0)} uds',
                            style: AppTextStyles.muted),
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
