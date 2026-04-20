import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../config/theme.dart';
import '../models/cliente.dart';
import '../services/visitas_service.dart';

/// Formulario de check-in: motivo + notas + GPS obligatorio.
class VisitaCheckinScreen extends StatefulWidget {
  final Cliente cliente;
  const VisitaCheckinScreen({super.key, required this.cliente});

  @override
  State<VisitaCheckinScreen> createState() => _CheckinState();
}

class _CheckinState extends State<VisitaCheckinScreen> {
  String _motivo = VisitasService.motivos.first;
  final _notasCtrl = TextEditingController();

  // GPS
  Position? _position;
  bool _gpsLoading = true;
  String _gpsError = '';

  // Submit
  bool _submitting = false;

  // Agendada detectada
  Map<String, dynamic>? _agendada;
  bool _cerrarAgendada = false;

  @override
  void initState() {
    super.initState();
    _obtenerGps();
    _buscarAgendada();
  }

  Future<void> _buscarAgendada() async {
    try {
      final m = await VisitasService.buscarVisitaAgendadaHoy(widget.cliente.codigo);
      if (mounted) setState(() => _agendada = m);
    } catch (_) {}
  }

  Future<void> _obtenerGps() async {
    setState(() {
      _gpsLoading = true;
      _gpsError = '';
    });
    try {
      final pos = await VisitasService.obtenerGps();
      if (!mounted) return;
      setState(() {
        _position = pos;
        _gpsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _gpsError = e.toString().replaceFirst('Exception: ', '');
        _gpsLoading = false;
      });
    }
  }

  bool get _canSubmit => _position != null && !_submitting;

  Future<void> _registrar() async {
    if (!_canSubmit) return;
    setState(() => _submitting = true);

    try {
      final idCerrar = (_cerrarAgendada && _agendada != null)
          ? int.tryParse(_agendada!['id'].toString())
          : null;
      await VisitasService.registrar(
        clienteCodigo: widget.cliente.codigo,
        clienteNombre: widget.cliente.nombre,
        latitud: _position!.latitude,
        longitud: _position!.longitude,
        motivo: _motivo,
        notas: _notasCtrl.text.trim().isNotEmpty ? _notasCtrl.text.trim() : null,
        precisionM: _position!.accuracy,
        cerrarActividadId: idCerrar,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(idCerrar != null
              ? 'Visita registrada y actividad agendada cerrada.'
              : 'Visita registrada correctamente'),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 3),
        ),
      );

      // Volver al picker (pop 2 pantallas: checkin + picker)
      Navigator.of(context)..pop()..pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  void dispose() {
    _notasCtrl.dispose();
    super.dispose();
  }

  Widget _buildAgendadaPrompt() {
    final m = _agendada!;
    final iso = m['fecha_programada']?.toString();
    final d = iso != null ? DateTime.tryParse(iso) : null;
    final hora = d != null
        ? '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}'
        : '--:--';
    final desc = m['descripcion']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.accent.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: const [
            Icon(Icons.schedule, size: 14, color: AppColors.accent),
            SizedBox(width: 6),
            Expanded(
              child: Text('Tenés una visita agendada para hoy',
                  style: TextStyle(color: AppColors.accent, fontSize: 11,
                      fontWeight: FontWeight.w700, letterSpacing: 0.5)),
            ),
          ]),
          const SizedBox(height: 6),
          Text('📅 Hoy a las $hora${desc.isNotEmpty ? "  ·  \"$desc\"" : ""}',
              style: AppTextStyles.body),
          const SizedBox(height: 8),
          const Text('¿Querés cerrarla con esta visita?',
              style: AppTextStyles.muted),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _cerrarAgendada = false),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: !_cerrarAgendada ? AppColors.textMuted.withOpacity(0.25) : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: !_cerrarAgendada ? AppColors.textMuted : AppColors.border),
                  ),
                  alignment: Alignment.center,
                  child: Text('No, dejarla pendiente', style: TextStyle(
                    color: !_cerrarAgendada ? AppColors.textPrimary : AppColors.textMuted,
                    fontSize: 11,
                    fontWeight: !_cerrarAgendada ? FontWeight.w600 : FontWeight.normal,
                  )),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _cerrarAgendada = true),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: _cerrarAgendada ? AppColors.success : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _cerrarAgendada ? AppColors.success : AppColors.border),
                  ),
                  alignment: Alignment.center,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (_cerrarAgendada) ...[
                      const Icon(Icons.check, color: Colors.white, size: 12),
                      const SizedBox(width: 4),
                    ],
                    Text('Sí, cerrarla', style: TextStyle(
                      color: _cerrarAgendada ? Colors.white : AppColors.textMuted,
                      fontSize: 11,
                      fontWeight: _cerrarAgendada ? FontWeight.w600 : FontWeight.normal,
                    )),
                  ]),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cliente;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bgSidebar,
        title: const Text('Registrar Visita', style: AppTextStyles.title),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Cliente ────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: AppCardStyle.base(),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.primary.withOpacity(0.2),
                  child: Text(c.nombre.isNotEmpty ? c.nombre[0] : '?',
                      style: const TextStyle(color: AppColors.primary, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.nombre, style: AppTextStyles.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text('${c.codigo} · ${c.categoria}', style: AppTextStyles.muted),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Agendada detectada (si existe) ─────────────────
          if (_agendada != null) ...[
            const SizedBox(height: 14),
            _buildAgendadaPrompt(),
          ],

          const SizedBox(height: 20),

          // ── GPS Status ─────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _position != null
                    ? AppColors.success.withOpacity(0.4)
                    : _gpsError.isNotEmpty
                        ? AppColors.danger.withOpacity(0.4)
                        : AppColors.border,
              ),
            ),
            child: Row(
              children: [
                if (_gpsLoading)
                  const SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                  )
                else if (_position != null)
                  const Icon(Icons.gps_fixed, color: AppColors.success, size: 22)
                else
                  const Icon(Icons.gps_off, color: AppColors.danger, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _gpsLoading
                            ? 'Obteniendo ubicación...'
                            : _position != null
                                ? 'Ubicación obtenida'
                                : 'GPS no disponible',
                        style: AppTextStyles.body,
                      ),
                      if (_position != null)
                        Text(
                          '${_position!.latitude.toStringAsFixed(6)}, ${_position!.longitude.toStringAsFixed(6)}',
                          style: AppTextStyles.muted,
                        ),
                      if (_gpsError.isNotEmpty)
                        Text(_gpsError, style: const TextStyle(color: AppColors.danger, fontSize: 11)),
                    ],
                  ),
                ),
                if (_gpsError.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.refresh, color: AppColors.accent, size: 20),
                    onPressed: _obtenerGps,
                    tooltip: 'Reintentar GPS',
                  ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Motivo ─────────────────────────────────────────
          const Text('Motivo de la visita', style: AppTextStyles.caption),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _motivo,
                isExpanded: true,
                dropdownColor: AppColors.bgCard,
                style: AppTextStyles.body,
                items: VisitasService.motivos.map((m) =>
                    DropdownMenuItem(value: m, child: Text(m))).toList(),
                onChanged: (v) => setState(() => _motivo = v!),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── Notas ──────────────────────────────────────────
          const Text('Notas (opcional)', style: AppTextStyles.caption),
          const SizedBox(height: 8),
          TextField(
            controller: _notasCtrl,
            style: AppTextStyles.body,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Observaciones de la visita...',
              hintStyle: AppTextStyles.muted,
              filled: true,
              fillColor: AppColors.bgCard,
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

          const SizedBox(height: 32),

          // ── Botón Registrar ────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _canSubmit ? _registrar : null,
              icon: _submitting
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_circle, size: 20),
              label: Text(
                _submitting
                    ? 'Registrando...'
                    : _position == null
                        ? 'Esperando GPS...'
                        : 'Registrar visita',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.border,
                disabledForegroundColor: AppColors.textMuted,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
