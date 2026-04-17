import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/cliente.dart';
import '../models/session.dart';
import '../services/clientes_service.dart';
import 'cliente_detail_screen.dart';
import '../widgets/app_drawer.dart';

class ClientesTab extends StatefulWidget {
  const ClientesTab({super.key});

  @override
  State<ClientesTab> createState() => _ClientesTabState();
}

class _ClientesTabState extends State<ClientesTab>
    with AutomaticKeepAliveClientMixin {
  List<Cliente> _todos = [];
  bool _loading = true;
  String _errorMsg = '';
  String _search = '';
  String _filtroSit = 'Todos';
  String _ordenar = 'nombre'; // nombre | ultimaCompra | saldo

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _errorMsg = ''; });
    try {
      final clientes = await ClientesService.getClientes(
        Session.current.vendedorNombre,
      );
      if (!mounted) return;
      setState(() { _todos = clientes; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _errorMsg = 'Error: $e'; });
    }
  }

  List<Cliente> get _filtered {
    var list = _todos.where((c) {
      // Filtro situación
      if (_filtroSit == 'Activos' && !c.esActivo) return false;
      if (_filtroSit == 'Inactivos' && (c.esActivo || c.esBaja)) return false;
      if (_filtroSit == 'Baja' && !c.esBaja) return false;
      // Búsqueda
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        return c.nombre.toLowerCase().contains(q) ||
               c.codigo.toLowerCase().contains(q);
      }
      return true;
    }).toList();

    // Ordenar
    switch (_ordenar) {
      case 'ultimaCompra':
        list.sort((a, b) {
          if (a.ultimaCompra == null && b.ultimaCompra == null) return 0;
          if (a.ultimaCompra == null) return 1;
          if (b.ultimaCompra == null) return -1;
          return b.ultimaCompra!.compareTo(a.ultimaCompra!);
        });
        break;
      case 'saldo':
        list.sort((a, b) => b.saldo.compareTo(a.saldo));
        break;
      default:
        // ya viene ordenado por nombre del SQL
        break;
    }
    return list;
  }

  int get _activos => _todos.where((c) => c.esActivo).length;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: AppColors.bg,
      drawer: const AppDrawer(currentTab: 2),
      appBar: AppBar(
        backgroundColor: AppColors.bgSidebar,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Clientes', style: AppTextStyles.title),
            if (!_loading)
              Text(
                '${_todos.length} clientes ($_activos activos)',
                style: AppTextStyles.muted,
              ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort, color: AppColors.textMuted, size: 20),
            tooltip: 'Ordenar',
            onSelected: (v) => setState(() => _ordenar = v),
            itemBuilder: (_) => [
              _sortItem('nombre', 'Nombre A-Z'),
              _sortItem('ultimaCompra', 'Última compra'),
              _sortItem('saldo', 'Mayor saldo'),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textMuted),
            onPressed: _loading ? null : _load,
          ),
          const AppBarAvatar(),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _errorMsg.isNotEmpty
              ? Center(child: Text(_errorMsg, style: AppTextStyles.caption))
              : Column(
                  children: [
                    // Búsqueda
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                      child: TextField(
                        style: AppTextStyles.body,
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
                    // Filtros
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          _chip('Todos'),
                          const SizedBox(width: 6),
                          _chip('Activos'),
                          const SizedBox(width: 6),
                          _chip('Inactivos'),
                          const SizedBox(width: 6),
                          _chip('Baja'),
                        ],
                      ),
                    ),
                    // Lista
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('Sin resultados', style: AppTextStyles.caption))
                          : RefreshIndicator(
                              onRefresh: _load,
                              color: AppColors.primary,
                              child: ListView.builder(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                itemCount: filtered.length,
                                itemBuilder: (_, i) => _ClienteTile(
                                  cliente: filtered[i],
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ClienteDetailScreen(
                                        cliente: filtered[i],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _chip(String label) {
    final selected = _filtroSit == label;
    return ChoiceChip(
      label: Text(label, style: TextStyle(
        fontSize: 12,
        color: selected ? Colors.white : AppColors.textMuted,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      )),
      selected: selected,
      onSelected: (_) => setState(() => _filtroSit = label),
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.bgCard,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 6),
    );
  }

  PopupMenuItem<String> _sortItem(String value, String label) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          if (_ordenar == value)
            const Icon(Icons.check, size: 16, color: AppColors.primary)
          else
            const SizedBox(width: 16),
          const SizedBox(width: 8),
          Text(label, style: AppTextStyles.body),
        ],
      ),
    );
  }
}

class _ClienteTile extends StatelessWidget {
  final Cliente cliente;
  final VoidCallback onTap;

  const _ClienteTile({required this.cliente, required this.onTap});

  Color get _sitColor {
    if (cliente.esBaja) return AppColors.danger;
    if (cliente.esActivo) return AppColors.success;
    return AppColors.textMuted;
  }

  String get _sitLabel {
    if (cliente.esBaja) return 'Baja';
    if (cliente.esActivo) return 'Activo';
    return 'Inactivo';
  }

  Color _diasColor(int? dias) {
    if (dias == null) return AppColors.textMuted;
    if (dias > 180) return AppColors.danger;
    if (dias > 90) return AppColors.warning;
    return AppColors.textMuted;
  }

  @override
  Widget build(BuildContext context) {
    final dias = cliente.diasSinComprar;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(12),
        decoration: AppCardStyle.base(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Nombre + situación
            Row(
              children: [
                Expanded(
                  child: Text(cliente.nombre, style: AppTextStyles.body,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _sitColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(_sitLabel, style: TextStyle(
                    color: _sitColor, fontSize: 10, fontWeight: FontWeight.bold,
                  )),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Código + categoría
            Row(
              children: [
                Text('${cliente.codigo} · ${cliente.categoria}',
                    style: AppTextStyles.muted),
                const Spacer(),
                // Saldo si tiene
                if (cliente.saldo > 0)
                  Text(cliente.saldoFmt, style: TextStyle(
                    color: cliente.maxAtraso > 30 ? AppColors.warning : AppColors.textSecondary,
                    fontSize: 11, fontWeight: FontWeight.bold,
                  )),
              ],
            ),
            // Última compra
            if (cliente.ultimaCompra != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    'Última compra: ${_fmtDate(cliente.ultimaCompra!)}',
                    style: AppTextStyles.muted,
                  ),
                  if (dias != null && dias > 90) ...[
                    const SizedBox(width: 8),
                    Text(
                      '$dias días',
                      style: TextStyle(color: _diasColor(dias), fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ],
              ),
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Sin compras registradas', style: AppTextStyles.muted),
              ),
          ],
        ),
      ),
    );
  }

  String _fmtDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year}';
  }
}
