/// Representa una métrica del scorecard: meta, valor real y % de logro.
class ScorecardItem {
  final int metricaId;
  final String nombre;
  final String descripcion;
  final String tipoDato; // '$', '%', 'int'
  final String funcionId;
  final String paramsJson;
  final double valorMeta;

  double valorReal;
  String formula;
  bool cargado; // true cuando SQL Server respondió
  bool error;   // true si hubo error al calcular

  ScorecardItem({
    required this.metricaId,
    required this.nombre,
    required this.descripcion,
    required this.tipoDato,
    required this.funcionId,
    required this.paramsJson,
    required this.valorMeta,
    this.valorReal = 0.0,
    this.formula = '',
    this.cargado = false,
    this.error = false,
  });

  // ── ABS tag: [ABS:clientes_cubiertos:cartera_total] ──────────
  // Cuando la fórmula contiene este tag, mostramos valores absolutos
  // en vez del porcentaje crudo. Usado por tasa_conversion.

  static final _absRegex = RegExp(r'\[ABS:(\d+):(\d+)\]');

  (int cubiertos, int cartera)? get _absValues {
    final match = _absRegex.firstMatch(formula);
    if (match == null) return null;
    return (int.parse(match.group(1)!), int.parse(match.group(2)!));
  }

  /// Fórmula limpia (sin el tag [ABS:...] que es interno)
  String get formulaDisplay {
    return formula.replaceAll(_absRegex, '').trim();
  }

  /// % de logro (0.0 a 1.0+). Ej: 0.74 = 74%
  double get pctLogro {
    if (valorMeta <= 0) return 0.0;
    // Para tasa_conversion con ABS: calcular % sobre meta absoluta
    final abs = _absValues;
    if (abs != null && tipoDato == '%') {
      final metaAbsoluta = abs.$2 * valorMeta / 100; // cartera * meta% / 100
      if (metaAbsoluta <= 0) return 0.0;
      return abs.$1 / metaAbsoluta; // cubiertos / meta_absoluta
    }
    return valorReal / valorMeta;
  }

  /// Formatea el valor real según el tipo de dato
  String get valorRealFmt {
    if (!cargado) return '...';
    if (error) return 'Error';
    // Si tiene ABS, mostrar clientes absolutos
    final abs = _absValues;
    if (abs != null && tipoDato == '%') {
      return '${abs.$1} clientes';
    }
    switch (tipoDato) {
      case r'$':
        return '\$ ${_fmtNum(valorReal)}';
      case '%':
        return '${valorReal.toStringAsFixed(1)}%';
      default:
        return valorReal.toStringAsFixed(0);
    }
  }

  /// Formatea el valor meta según el tipo de dato
  String get valorMetaFmt {
    // Si tiene ABS, convertir meta% a clientes absolutos
    final abs = _absValues;
    if (abs != null && tipoDato == '%') {
      final metaClientes = (abs.$2 * valorMeta / 100).round();
      return '$metaClientes clientes';
    }
    switch (tipoDato) {
      case r'$':
        return '\$ ${_fmtNum(valorMeta)}';
      case '%':
        return '${valorMeta.toStringAsFixed(1)}%';
      default:
        return valorMeta.toStringAsFixed(0);
    }
  }

  String _fmtNum(double v) {
    final parts = v.toStringAsFixed(0).split('');
    final buf = StringBuffer();
    final len = parts.length;
    for (int i = 0; i < len; i++) {
      if (i > 0 && (len - i) % 3 == 0) buf.write('.');
      buf.write(parts[i]);
    }
    return buf.toString();
  }
}
