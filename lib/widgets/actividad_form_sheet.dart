import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/actividades_service.dart';

/// Bottom sheet para cargar una actividad manualmente.
class ActividadFormSheet extends StatefulWidget {
  final String clienteCodigo;
  final String clienteNombre;
  final VoidCallback onSaved;

  const ActividadFormSheet({
    super.key,
    required this.clienteCodigo,
    required this.clienteNombre,
    required this.onSaved,
  });

  @override
  State<ActividadFormSheet> createState() => _FormState();
}

class _FormState extends State<ActividadFormSheet> {
  String _tipo = 'Llamada';
  final _descCtrl = TextEditingController();
  DateTime? _fecha;
  TimeOfDay? _hora;
  bool _saving = false;

  Future<void> _pickFecha() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: AppColors.primary)),
        child: child!,
      ),
    );
    if (date != null && mounted) setState(() => _fecha = date);
  }

  Future<void> _pickHora() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: AppColors.primary)),
        child: child!,
      ),
    );
    if (time != null && mounted) setState(() => _hora = time);
  }

  Future<void> _guardar() async {
    setState(() => _saving = true);

    String? fechaProg;
    if (_fecha != null) {
      final h = _hora?.hour ?? 9;
      final m = _hora?.minute ?? 0;
      final dt = DateTime(_fecha!.year, _fecha!.month, _fecha!.day, h, m);
      fechaProg = dt.toIso8601String();
    }

    try {
      await ActividadesService.registrar(
        clienteCodigo: widget.clienteCodigo,
        clienteNombre: widget.clienteNombre,
        tipo: _tipo,
        descripcion: _descCtrl.text.trim().isNotEmpty ? _descCtrl.text.trim() : null,
        fechaProgramada: fechaProg,
      );
      if (!mounted) return;
      widget.onSaved();
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Actividad registrada'), backgroundColor: AppColors.success),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.danger),
      );
    }
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      decoration: const BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Cargar actividad', style: AppTextStyles.title),
          Text(widget.clienteNombre, style: AppTextStyles.muted),
          const SizedBox(height: 16),

          // Tipo
          const Text('Tipo', style: AppTextStyles.caption),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.bg, borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _tipo,
                isExpanded: true,
                dropdownColor: AppColors.bgCard,
                style: AppTextStyles.body,
                items: ActividadesService.tipos.map((t) =>
                    DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setState(() => _tipo = v!),
              ),
            ),
          ),

          const SizedBox(height: 14),

          // Descripción
          const Text('Descripción', style: AppTextStyles.caption),
          const SizedBox(height: 6),
          TextField(
            controller: _descCtrl,
            style: AppTextStyles.body,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Qué hiciste o qué tenés que hacer...',
              hintStyle: AppTextStyles.muted,
              filled: true, fillColor: AppColors.bg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
            ),
          ),

          const SizedBox(height: 14),

          // Fecha y hora (opcional)
          const Text('Fecha/hora (opcional — para recordatorio)', style: AppTextStyles.caption),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _pickFecha,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.bg, borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 16, color: AppColors.textMuted),
                        const SizedBox(width: 8),
                        Text(
                          _fecha != null
                              ? '${_fecha!.day.toString().padLeft(2, '0')}/${_fecha!.month.toString().padLeft(2, '0')}/${_fecha!.year}'
                              : 'Sin fecha',
                          style: _fecha != null ? AppTextStyles.body : AppTextStyles.muted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _pickHora,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.bg, borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.schedule, size: 16, color: AppColors.textMuted),
                      const SizedBox(width: 8),
                      Text(
                        _hora != null
                            ? '${_hora!.hour.toString().padLeft(2, '0')}:${_hora!.minute.toString().padLeft(2, '0')}'
                            : '--:--',
                        style: _hora != null ? AppTextStyles.body : AppTextStyles.muted,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Botón guardar
          SizedBox(
            width: double.infinity, height: 48,
            child: ElevatedButton(
              onPressed: _saving ? null : _guardar,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _saving
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Guardar', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}
