import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/cliente.dart';
import '../models/session.dart';
import '../services/clientes_service.dart';
import 'visita_checkin_screen.dart';

/// Pantalla para elegir un cliente antes de registrar la visita.
class VisitaClientePickerScreen extends StatefulWidget {
  const VisitaClientePickerScreen({super.key});

  @override
  State<VisitaClientePickerScreen> createState() => _PickerState();
}

class _PickerState extends State<VisitaClientePickerScreen> {
  List<Cliente> _todos = [];
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final clientes = await ClientesService.getClientes(
        Session.current.vendedorNombre,
      );
      if (!mounted) return;
      setState(() {
        _todos = clientes.where((c) => c.esActivo).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  List<Cliente> get _filtered {
    if (_search.isEmpty) return _todos;
    final q = _search.toLowerCase();
    return _todos.where((c) =>
        c.nombre.toLowerCase().contains(q) ||
        c.codigo.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

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
                      hintText: 'Buscar por nombre o código...',
                      hintStyle: AppTextStyles.muted,
                      prefixIcon: const Icon(Icons.search, color: AppColors.textMuted, size: 20),
                      filled: true,
                      fillColor: AppColors.bgCard,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    '${filtered.length} clientes activos',
                    style: AppTextStyles.muted,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final c = filtered[i];
                      return GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => VisitaCheckinScreen(cliente: c),
                          ),
                        ),
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
                                    Text('${c.codigo} · ${c.categoria}',
                                        style: AppTextStyles.muted),
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
