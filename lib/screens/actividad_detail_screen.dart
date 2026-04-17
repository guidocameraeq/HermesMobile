import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/actividades_service.dart';
import '../services/notification_service.dart';

class ActividadDetailScreen extends StatefulWidget {
  final int actividadId;
  const ActividadDetailScreen({super.key, required this.actividadId});

  @override
  State<ActividadDetailScreen> createState() => _State();
}

class _State extends State<ActividadDetailScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _saving = false;

  DateTime? _fecha;
  TimeOfDay? _hora;
  final _descCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final d = await ActividadesService.porId(widget.actividadId);
    if (!mounted) return;
    if (d == null) {
      setState(() => _loading = false);
      return;
    }

    // Parsear fecha programada
    final fecha = d['fecha_programada'];
    if (fecha != null) {
      final dt = fecha is DateTime ? fecha : DateTime.tryParse(fecha.toString());
      if (dt != null) {
        _fecha = DateTime(dt.year, dt.month, dt.day);
        _hora = TimeOfDay(hour: dt.hour, minute: dt.minute);
      }
    }
    _descCtrl.text = d['descripcion']?.toString() ?? '';

    setState(() {
      _data = d;
      _loading = false;
    });
  }

  bool get _esCompletada => _data?['completada'] == true;
  String get _tipo => _data?['tipo']?.toString() ?? '';
  String get _cliente => _data?['cliente_nombre']?.toString() ?? '';
  String get _clienteCodigo => _data?['cliente_codigo']?.toString() ?? '';

  IconData get _icon => switch (_tipo) {
    'llamada' => Icons.phone,
    'visita' => Icons.location_on,
    'propuesta' => Icons.description,
    'presentacion' || 'presentación' => Icons.present_to_all,
    'reunion' || 'reunión' => Icons.groups,
    'recordatorio' => Icons.alarm,
    _ => Icons.note,
  };

  Color get _color => switch (_tipo) {
    'llamada' => AppColors.primary,
    'visita' => AppColors.success,
    'propuesta' => AppColors.warning,
    'recordatorio' => AppColors.accent,
    _ => AppColors.textMuted,
  };

  Future<void> _pickFecha() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _fecha ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: AppColors.primary)),
        child: child!,
      ),
    );
    if (d != null && mounted) {
      setState(() => _fecha = d);
      _guardarCambios();
    }
  }

  Future<void> _pickHora() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _hora ?? TimeOfDay.now(),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: AppColors.primary)),
        child: child!,
      ),
    );
    if (t != null && mounted) {
      setState(() => _hora = t);
      _guardarCambios();
    }
  }

  Future<void> _editarDescripcion() async {
    final controller = TextEditingController(text: _descCtrl.text);
    final nuevaDesc = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text('Editar descripción', style: AppTextStyles.title),
        content: TextField(
          controller: controller,
          style: AppTextStyles.body,
          maxLines: 4,
          autofocus: true,
          decoration: InputDecoration(
            filled: true, fillColor: AppColors.bg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (nuevaDesc != null && nuevaDesc != _descCtrl.text) {
      _descCtrl.text = nuevaDesc;
      _guardarCambios();
    }
  }

  Future<void> _guardarCambios() async {
    setState(() => _saving = true);

    String? fechaStr;
    if (_fecha != null) {
      final h = _hora?.hour ?? 9;
      final m = _hora?.minute ?? 0;
      final dt = DateTime(_fecha!.year, _fecha!.month, _fecha!.day, h, m);
      fechaStr = dt.toIso8601String();
    }

    try {
      await ActividadesService.actualizar(
        id: widget.actividadId,
        descripcion: _descCtrl.text.trim(),
        fechaProgramada: fechaStr,
      );

      // Cancelar notif anterior y programar nueva si corresponde
      await NotificationService.cancel(widget.actividadId);
      if (_fecha != null && !_esCompletada) {
        final h = _hora?.hour ?? 9;
        final m = _hora?.minute ?? 0;
        final dt = DateTime(_fecha!.year, _fecha!.month, _fecha!.day, h, m);
        if (dt.isAfter(DateTime.now())) {
          await NotificationService.schedule(
            id: widget.actividadId,
            title: '${_tipo[0].toUpperCase()}${_tipo.substring(1)} — $_cliente',
            body: _descCtrl.text.trim().isNotEmpty ? _descCtrl.text.trim() : 'Actividad agendada',
            scheduledDate: dt,
          );
        }
      }

      if (!mounted) return;
      setState(() => _saving = false);
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.danger),
      );
    }
  }

  Future<void> _toggleCompletada() async {
    try {
      if (_esCompletada) {
        await ActividadesService.reabrir(widget.actividadId);
      } else {
        await ActividadesService.completar(widget.actividadId);
        await NotificationService.cancel(widget.actividadId);
      }
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.danger),
      );
    }
  }

  Future<void> _eliminar() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text('Eliminar actividad', style: AppTextStyles.title),
        content: const Text('¿Seguro que querés eliminar esta actividad?', style: AppTextStyles.body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ActividadesService.eliminar(widget.actividadId);
      await NotificationService.cancel(widget.actividadId);
      if (!mounted) return;
      Navigator.pop(context, true); // vuelve con "hubo cambios"
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Actividad eliminada'), backgroundColor: AppColors.success),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.danger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    if (_data == null) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(backgroundColor: AppColors.bgSidebar),
        body: const Center(child: Text('Actividad no encontrada', style: AppTextStyles.caption)),
      );
    }

    final createdAt = _data!['created_at'];
    String createdStr = '';
    if (createdAt != null) {
      final dt = createdAt is DateTime ? createdAt : DateTime.tryParse(createdAt.toString());
      if (dt != null) {
        createdStr = '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bgSidebar,
        title: const Text('Actividad', style: AppTextStyles.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppColors.danger),
            onPressed: _eliminar,
            tooltip: 'Eliminar',
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Header con tipo + cliente
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _color.withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 56, height: 56,
                      decoration: BoxDecoration(
                        color: _color.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Icon(_icon, color: _color, size: 28),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${_tipo[0].toUpperCase()}${_tipo.substring(1)}'.toUpperCase(),
                      style: TextStyle(color: _color, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
                    const SizedBox(height: 8),
                    Text(_cliente, style: AppTextStyles.body, textAlign: TextAlign.center),
                    if (_clienteCodigo.isNotEmpty)
                      Text('Código: $_clienteCodigo', style: AppTextStyles.muted),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Fecha/hora
              _fieldCard(
                label: 'Fecha y hora',
                value: _fecha == null
                    ? 'Sin programar'
                    : '${_fecha!.day.toString().padLeft(2, '0')}/${_fecha!.month.toString().padLeft(2, '0')}/${_fecha!.year}'
                      '${_hora != null ? "  ·  ${_hora!.hour.toString().padLeft(2, '0')}:${_hora!.minute.toString().padLeft(2, '0')}" : ""}',
                icon: Icons.calendar_today,
                onTap: _esCompletada ? null : () async {
                  await _pickFecha();
                  if (_fecha != null && mounted) await _pickHora();
                },
              ),

              const SizedBox(height: 10),

              // Descripción
              _fieldCard(
                label: 'Descripción',
                value: _descCtrl.text.isNotEmpty ? _descCtrl.text : 'Sin descripción',
                icon: Icons.notes,
                onTap: _esCompletada ? null : _editarDescripcion,
                multiLine: true,
              ),

              const SizedBox(height: 20),

              // Metadata
              Container(
                padding: const EdgeInsets.all(12),
                decoration: AppCardStyle.base(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _metaRow('Origen', _data!['origen']?.toString() ?? 'manual'),
                    _metaRow('Creada', createdStr),
                    if (_esCompletada && _data!['completada_at'] != null)
                      _metaRow('Completada', _formatDate(_data!['completada_at'])),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Estado + botón
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _esCompletada ? AppColors.success.withOpacity(0.1) : AppColors.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _esCompletada ? Icons.check_circle : Icons.schedule,
                          color: _esCompletada ? AppColors.success : AppColors.warning,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _esCompletada ? 'Completada' : 'Pendiente',
                          style: TextStyle(
                            color: _esCompletada ? AppColors.success : AppColors.warning,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _toggleCompletada,
                        icon: Icon(_esCompletada ? Icons.replay : Icons.check, size: 20),
                        label: Text(_esCompletada ? 'Reabrir actividad' : 'Marcar como completada',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _esCompletada ? AppColors.textMuted : AppColors.success,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),
            ],
          ),
          if (_saving)
            Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator(color: AppColors.primary)),
            ),
        ],
      ),
    );
  }

  String _formatDate(dynamic dt) {
    if (dt == null) return '';
    final d = dt is DateTime ? dt : DateTime.tryParse(dt.toString());
    if (d == null) return '';
    return '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Widget _fieldCard({
    required String label,
    required String value,
    required IconData icon,
    VoidCallback? onTap,
    bool multiLine = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: AppCardStyle.base(),
        child: Row(
          crossAxisAlignment: multiLine ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.textMuted, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTextStyles.muted),
                  const SizedBox(height: 2),
                  Text(value, style: AppTextStyles.body, maxLines: multiLine ? 4 : 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (onTap != null)
              const Icon(Icons.edit_outlined, color: AppColors.accent, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _metaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 80, child: Text(label, style: AppTextStyles.muted)),
          Expanded(child: Text(value, style: AppTextStyles.caption)),
        ],
      ),
    );
  }
}
