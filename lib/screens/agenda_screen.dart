import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/cliente.dart';
import '../models/session.dart';
import '../services/actividades_service.dart';
import '../services/clientes_service.dart';
import '../widgets/actividad_form_sheet.dart';
import 'actividad_detail_screen.dart';

class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key});

  @override
  State<AgendaScreen> createState() => _AgendaState();
}

class _AgendaState extends State<AgendaScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String _filtro = 'Hoy';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = switch (_filtro) {
      'Hoy' => await ActividadesService.pendientesHoy(),
      'Semana' => await ActividadesService.pendientesSemana(),
      'Todas' => await ActividadesService.pendientes(),
      'Hechas' => await ActividadesService.completadas(),
      _ => await ActividadesService.pendientes(),
    };
    if (!mounted) return;
    setState(() { _items = data; _loading = false; });
  }

  Future<void> _completar(int id) async {
    await ActividadesService.completar(id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Actividad completada'), backgroundColor: AppColors.success),
    );
    _load();
  }

  void _nuevaActividad() {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _ActividadClientePickerScreen(onSaved: _load),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bgSidebar,
        title: const Text('Mi Agenda', style: AppTextStyles.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: AppColors.accent),
            onPressed: _nuevaActividad,
            tooltip: 'Nueva actividad',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textMuted),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _chip('Hoy'), const SizedBox(width: 6),
                _chip('Semana'), const SizedBox(width: 6),
                _chip('Todas'), const SizedBox(width: 6),
                _chip('Hechas'),
                const Spacer(),
                Text('${_items.length}', style: AppTextStyles.muted),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _filtro == 'Hechas' ? Icons.check_circle : Icons.event_available,
                              color: AppColors.textMuted, size: 48,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _filtro == 'Hechas' ? 'Sin actividades completadas' : 'Sin actividades pendientes',
                              style: AppTextStyles.caption,
                            ),
                            if (_filtro != 'Hechas') ...[
                              const SizedBox(height: 4),
                              const Text('Usá Cronos o el botón + para agendar', style: AppTextStyles.muted),
                            ],
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: AppColors.primary,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _items.length,
                          itemBuilder: (_, i) {
                            final item = _items[i];
                            final id = int.tryParse(item['id']?.toString() ?? '');
                            return _ActividadTile(
                              item: item,
                              esHecha: _filtro == 'Hechas',
                              onCompletar: id != null ? () => _completar(id) : null,
                              onTap: id != null
                                  ? () async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => ActividadDetailScreen(actividadId: id),
                                        ),
                                      );
                                      if (mounted) _load();
                                    }
                                  : null,
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label) {
    final selected = _filtro == label;
    return ChoiceChip(
      label: Text(label, style: TextStyle(
        fontSize: 12,
        color: selected ? Colors.white : AppColors.textMuted,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      )),
      selected: selected,
      onSelected: (_) { setState(() => _filtro = label); _load(); },
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.bgCard,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 6),
    );
  }
}

class _ActividadTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool esHecha;
  final VoidCallback? onCompletar;
  final VoidCallback? onTap;

  const _ActividadTile({required this.item, required this.esHecha, this.onCompletar, this.onTap});

  IconData get _icon => switch (item['tipo']?.toString() ?? '') {
    'llamada' => Icons.phone,
    'visita' => Icons.location_on,
    'propuesta' => Icons.description,
    'presentacion' || 'presentación' => Icons.present_to_all,
    'reunion' || 'reunión' => Icons.groups,
    'recordatorio' => Icons.alarm,
    _ => Icons.note,
  };

  Color get _color => switch (item['tipo']?.toString() ?? '') {
    'llamada' => AppColors.primary,
    'visita' => AppColors.success,
    'propuesta' => AppColors.warning,
    'recordatorio' => AppColors.accent,
    _ => AppColors.textMuted,
  };

  @override
  Widget build(BuildContext context) {
    final tipo = item['tipo']?.toString() ?? 'otro';
    final cliente = item['cliente_nombre']?.toString() ?? '';
    final desc = item['descripcion']?.toString() ?? '';
    final fecha = item['fecha_programada'] ?? item['completada_at'] ?? item['created_at'];
    String horaStr = '';
    if (fecha != null) {
      final dt = fecha is DateTime ? fecha : DateTime.tryParse(fecha.toString());
      if (dt != null) {
        horaStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: AppCardStyle.base(borderColor: esHecha ? AppColors.textMuted : _color),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: (esHecha ? AppColors.textMuted : _color).withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(_icon, color: esHecha ? AppColors.textMuted : _color, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (horaStr.isNotEmpty)
                      Text('$horaStr — ', style: AppTextStyles.muted),
                    Expanded(
                      child: Text(
                        '${tipo[0].toUpperCase()}${tipo.substring(1)}${cliente.isNotEmpty ? " — $cliente" : ""}',
                        style: TextStyle(
                          color: esHecha ? AppColors.textMuted : AppColors.textPrimary,
                          fontSize: 13, fontWeight: FontWeight.w600,
                          decoration: esHecha ? TextDecoration.lineThrough : null,
                        ),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(desc, style: AppTextStyles.muted, maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          if (!esHecha && onCompletar != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onCompletar,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.check, color: AppColors.success, size: 18),
              ),
            ),
          ],
        ],
      ),
      ),
    );
  }
}

/// Picker de cliente para nueva actividad desde la agenda.
class _ActividadClientePickerScreen extends StatefulWidget {
  final VoidCallback onSaved;
  const _ActividadClientePickerScreen({required this.onSaved});

  @override
  State<_ActividadClientePickerScreen> createState() => _PickerState();
}

class _PickerState extends State<_ActividadClientePickerScreen> {
  List<Cliente> _clientes = [];
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final clientes = await ClientesService.getClientes(Session.current.vendedorNombre);
    if (!mounted) return;
    setState(() {
      _clientes = clientes.where((c) => c.esActivo).toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _search.isEmpty
        ? _clientes
        : _clientes.where((c) =>
            c.nombre.toLowerCase().contains(_search.toLowerCase()) ||
            c.codigo.toLowerCase().contains(_search.toLowerCase())).toList();

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bgSidebar,
        title: const Text('Elegir cliente', style: AppTextStyles.title),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    style: AppTextStyles.body,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Buscar cliente...', hintStyle: AppTextStyles.muted,
                      prefixIcon: const Icon(Icons.search, color: AppColors.textMuted, size: 20),
                      filled: true, fillColor: AppColors.bgCard,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final c = filtered[i];
                      return GestureDetector(
                        onTap: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => ActividadFormSheet(
                              clienteCodigo: c.codigo,
                              clienteNombre: c.nombre,
                              onSaved: () {
                                widget.onSaved();
                                Navigator.pop(context); // cierra picker
                              },
                            ),
                          );
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.all(12),
                          decoration: AppCardStyle.base(),
                          child: Row(
                            children: [
                              const Icon(Icons.store, color: AppColors.textMuted, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(c.nombre, style: AppTextStyles.body,
                                        maxLines: 1, overflow: TextOverflow.ellipsis),
                                    Text('${c.codigo} · ${c.categoria}', style: AppTextStyles.muted),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 20),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
