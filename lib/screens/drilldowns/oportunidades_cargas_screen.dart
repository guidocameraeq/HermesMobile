import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/sql_service.dart';

/// Pantalla de oportunidades: elegís cargas → te muestra qué clientes
/// NO compraron cada una de esas cargas.
class OportunidadesCargasScreen extends StatefulWidget {
  final String vendedor;
  final List<String> conjuntos; // códigos disponibles

  const OportunidadesCargasScreen({
    super.key,
    required this.vendedor,
    required this.conjuntos,
  });

  @override
  State<OportunidadesCargasScreen> createState() => _State();
}

class _State extends State<OportunidadesCargasScreen> {
  // Paso 1: selección de cargas
  Map<String, String> _cargasDisponibles = {}; // código → nombre
  Set<String> _seleccionadas = {};
  bool _loadingCargas = true;

  // Paso 2: resultados
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

    // Buscar nombres de cada conjunto
    final mapa = <String, String>{};
    for (final cod in widget.conjuntos) {
      final codEsc = cod.replaceAll("'", "''");
      final rows = await SqlService.query(
        '''SELECT TOP 1 ConjuntoNombre
           FROM [EQ-DBGA].[dbo].[fydvtsEstadisticas]
           WHERE ConjuntoCodigo = '$codEsc' AND ConjuntoNombre IS NOT NULL''',
      );
      mapa[cod] = rows.firstOrNull?['ConjuntoNombre']?.toString() ?? cod;
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

    // Por cada carga seleccionada, buscar clientes que NUNCA la compraron
    final Map<String, List<String>> clientesFaltantes = {}; // clienteCodigo → [cargas que le faltan]
    final Map<String, String> clienteNombres = {};

    for (final cod in _seleccionadas) {
      final codEsc = cod.replaceAll("'", "''");
      final cargaNombre = _cargasDisponibles[cod] ?? cod;

      // Clientes activos del vendedor que NO compraron esta carga
      final rows = await SqlService.query(
        '''SELECT c.ClienteCodigo, c.ClienteNombre
           FROM [EQ-DBGA].[dbo].[fydvtsClientesXLinea] c
           WHERE c.VendedorNombre = ? AND c.ClienteSituacion = 'Activo normal'
             AND c.ClienteCodigo NOT IN (
                 SELECT DISTINCT ClienteCodigo
                 FROM [EQ-DBGA].[dbo].[fydvtsEstadisticas]
                 WHERE ConjuntoCodigo = '$codEsc' AND NumeraTipoTipo = 2205
             )
           ORDER BY c.ClienteNombre''',
        [widget.vendedor],
      );

      for (final r in rows) {
        final cli = r['ClienteCodigo']?.toString() ?? '';
        clienteNombres[cli] = r['ClienteNombre']?.toString() ?? cli;
        clientesFaltantes.putIfAbsent(cli, () => []).add(cargaNombre);
      }
    }

    // Convertir a lista ordenada por cantidad de cargas faltantes (más faltantes primero)
    final resultados = clientesFaltantes.entries.map((e) => _ClienteOportunidad(
      codigo: e.key,
      nombre: clienteNombres[e.key] ?? e.key,
      cargasFaltantes: e.value,
    )).toList()
      ..sort((a, b) => b.cargasFaltantes.length.compareTo(a.cargasFaltantes.length));

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
                // Selector de cargas
                _buildSelector(),
                // Botón buscar
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
                            : 'Buscar oportunidades (${_seleccionadas.length} cargas)',
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
                // Resultados
                if (_buscado) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(
                      children: [
                        Text('${_resultados.length} clientes con oportunidad',
                            style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.bold)),
                        const Spacer(),
                        Text('Ordenado por cargas faltantes', style: AppTextStyles.muted),
                      ],
                    ),
                  ),
                ],
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
                                : 'Tocá "Buscar oportunidades"',
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
                        if (v) {
                          _seleccionadas.add(e.key);
                        } else {
                          _seleccionadas.remove(e.key);
                        }
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
              child: Text(
                carga,
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
