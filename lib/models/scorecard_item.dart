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

  /// % de logro (0.0 a 1.0+). Ej: 0.74 = 74%
  double get pctLogro {
    if (valorMeta <= 0) return 0.0;
    return valorReal / valorMeta;
  }

  /// Formatea el valor real según el tipo de dato
  String get valorRealFmt {
    if (!cargado) return '...';
    if (error) return 'Error';
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
    // Formatea con puntos de miles: 1234567 -> 1.234.567
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
