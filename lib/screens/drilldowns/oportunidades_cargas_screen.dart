import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/sql_service.dart';

/// Pantalla de oportunidades: elegís cargas → te muestra qué clientes
/// NO compraron cada una de esas cargas.
class OportunidadesCargasScreen extends StatefulWidget {
  final String vendedor;
  final List<String> conjuntos;

  const OportunidadesCargasScreen({
    super.key,
    required this.vendedor,
    required this.conjuntos,
  });

  @override
  State<OportunidadesCargasScreen> createState() => _State();
}

class _State extends State<OportunidadesCargasScreen> {
  Map<String, String> _cargasDisponibles = {};
  Set<String> _seleccionadas = {};
  bool _loadingCargas = true;

  List<_ClienteOportunidad> _resultados = [];
  bool _buscando = false;
  bool _buscado = false;

  @override
  void initState() {
    super.initState();
    _loadNombresCargas();
  }

  Future<void> _loadNombresCargas() async {
    setState(() => _loadingCargas = true);

    // UNA sola query para todos los nombres de conjuntos
    final phs = widget.conjuntos
        .map((c) => "'${c.replaceAll("'", "''")}'")
        .join(',');
    final rows = await SqlService.query(
      '''SELECT DISTINCT ConjuntoCodigo, ConjuntoNombre
         FROM [EQ-DBGA].[dbo].[fydvtsEstadisticas]
         WHERE ConjuntoCodigo IN ($phs)
           AND ConjuntoNombre IS NOT NULL''',
    );

    final mapa = <String, String>{};
    for (final r in rows) {
      final cod = r['ConjuntoCodigo']?.toString() ?? '';
      final nom = r['ConjuntoNombre']?.toString() ?? cod;
      if (cod.isNotEmpty) mapa[cod] = nom;
    }
    // Agregar los que no se encontraron con su código como nombre
    for (final c in widget.conjuntos) {
      mapa.putIfAbsent(c, () => c);
    }

    if (!mounted) return;
    setState(() {
      _cargasDisponibles = mapa;
      _loadingCargas = false;
    });
  }

  Future<void> _buscar() async {
    if (_seleccionadas.isEmpty) return;
    setState(() { _buscando = true; _resultados = []; });

    // UNA sola query: todos los clientes activos del vendedor
    final rowsCartera = await SqlService.query(
      '''SELECT DISTINCT ClienteCodigo, ClienteNombre
         FROM [EQ-DBGA].[dbo].[fydvtsClientesXLinea]
         WHERE VendedorNombre = ? AND ClienteSituacion = 'Activo normal'
         ORDER BY ClienteNombre''',
      [widget.vendedor],
    );

    // UNA sola query: todos los pares (cliente, conjunto) que compraron alguna vez
    final selPhs = _seleccionadas
        .map((c) => "'${c.replaceAll("'", "''")}'")
        .join(',');
    final rowsComprados = await SqlService.query(
      '''SELECT DISTINCT ClienteCodigo, ConjuntoCodigo
         FROM [EQ-DBGA].[dbo].[fydvtsEstadisticas]
         WHERE ConjuntoCodigo IN ($selPhs)
           AND NumeraTipoTipo = 2205
           AND VendedorNombre = ?''',
      [widget.vendedor],
    );

    // Index: qué conjuntos compró cada cliente
    final compradosPorCliente = <String, Set<String>>{};
    for (final r in rowsComprados) {
      final cli = r['ClienteCodigo']?.toString() ?? '';
      final conj = r['ConjuntoCodigo']?.toString() ?? '';
      compradosPorCliente.putIfAbsent(cli, () => {}).add(conj);
    }

    // Calcular faltantes por cliente
    final resultados = <_ClienteOportunidad>[];
    for (final r in rowsCartera) {
      final cli = r['ClienteCodigo']?.toString() ?? '';
      final nombre = r['ClienteNombre']?.toString() ?? cli;
      final compradas = compradosPorCliente[cli] ?? {};
      final faltantes = _seleccionadas
          .where((c) => !compradas.contains(c))
          .map((c) => _cargasDisponibles[c] ?? c)
          .toList();

      if (faltantes.isNotEmpty) {
        resultados.add(_ClienteOportunidad(
          codigo: cli, nombre: nombre, cargasFaltantes: faltantes,
        ));
      }
    }

    // Ordenar por más cargas faltantes primero
    resultados.sort((a, b) => b.cargasFaltantes.length.compareTo(a.cargasFaltantes.length));

    if (!mounted) return;
    setState(() {
      _resultados = resultados;
      _buscando = false;
      _buscado = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bgSidebar,
        title: const Text('Oportunidades por Carga', style: AppTextStyles.title),
      ),
      body: _loadingCargas
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : Column(
              children: [
                _buildSelector(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: _seleccionadas.isEmpty || _buscando ? null : _buscar,
                      icon: _buscando
                          ? const SizedBox(width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.search, size: 18),
                      label: Text(
                        _buscando
                            ? 'Buscando...'
                            : 'Buscar (${_seleccionadas.length} cargas)',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AppColors.border,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ),
                if (_buscado)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(
                      children: [
                        Text('${_resultados.length} clientes con oportunidad',
                            style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                Expanded(
                  child: _buscado
                      ? _resultados.isEmpty
                          ? const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.celebration, color: AppColors.success, size: 48),
                                  SizedBox(height: 12),
                                  Text('Todos los clientes ya tienen estas cargas',
                                      style: AppTextStyles.caption),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: _resultados.length,
                              itemBuilder: (_, i) => _buildResultTile(_resultados[i]),
                            )
                      : Center(
                          child: Text(
                            _seleccionadas.isEmpty
                                ? 'Seleccioná al menos una carga'
                                : 'Tocá "Buscar"',
                            style: AppTextStyles.muted,
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildSelector() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: AppCardStyle.base(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text('Seleccionar cargas', style: AppTextStyles.title),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  setState(() {
                    if (_seleccionadas.length == _cargasDisponibles.length) {
                      _seleccionadas.clear();
                    } else {
                      _seleccionadas = _cargasDisponibles.keys.toSet();
                    }
                    _buscado = false;
                  });
                },
                child: Text(
                  _seleccionadas.length == _cargasDisponibles.length ? 'Ninguna' : 'Todas',
                  style: const TextStyle(color: AppColors.accent, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Flexible(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _cargasDisponibles.entries.map((e) {
                  final selected = _seleccionadas.contains(e.key);
                  return FilterChip(
                    label: Text(
                      e.value,
                      style: TextStyle(
                        fontSize: 11,
                        color: selected ? Colors.white : AppColors.textMuted,
                        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    selected: selected,
                    onSelected: (v) {
                      setState(() {
                        if (v) _seleccionadas.add(e.key); else _seleccionadas.remove(e.key);
                        _buscado = false;
                      });
                    },
                    selectedColor: AppColors.primary,
                    backgroundColor: AppColors.bgCardHover,
                    checkmarkColor: Colors.white,
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultTile(_ClienteOportunidad cli) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: AppCardStyle.base(borderColor: AppColors.warning),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, color: AppColors.warning.withOpacity(0.8), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(cli.nombre, style: AppTextStyles.body,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${cli.cargasFaltantes.length} ${cli.cargasFaltantes.length == 1 ? "carga" : "cargas"}',
                  style: const TextStyle(color: AppColors.warning, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('Código: ${cli.codigo}', style: AppTextStyles.muted),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: cli.cargasFaltantes.map((carga) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.danger.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.danger.withOpacity(0.2)),
              ),
              child: Text(carga,
                style: const TextStyle(color: AppColors.danger, fontSize: 10),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }
}

class _ClienteOportunidad {
  final String codigo;
  final String nombre;
  final List<String> cargasFaltantes;

  _ClienteOportunidad({
    required this.codigo,
    required this.nombre,
    required this.cargasFaltantes,
  });
}
