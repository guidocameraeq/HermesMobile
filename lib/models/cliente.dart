/// Modelo de cliente para la lista y ficha de detalle.
class Cliente {
  final String codigo;
  final String nombre;
  final String categoria;   // Mayorista / Minorista
  final String situacion;   // Activo normal / Inactivo / Baja
  final String localidad;
  final String provincia;
  final DateTime? ultimaCompra;
  final double ultimoMonto;  // facturación del último mes con compra
  final double saldo;        // ImpPendiente total de CxC
  final int maxAtraso;       // días de atraso máximo

  Cliente({
    required this.codigo,
    required this.nombre,
    required this.categoria,
    required this.situacion,
    required this.localidad,
    required this.provincia,
    this.ultimaCompra,
    this.ultimoMonto = 0,
    this.saldo = 0,
    this.maxAtraso = 0,
  });

  int? get diasSinComprar {
    if (ultimaCompra == null) return null;
    return DateTime.now().difference(ultimaCompra!).inDays;
  }

  bool get esActivo => situacion.toLowerCase().contains('activo');
  bool get esBaja => situacion.toLowerCase().contains('baja');

  String get saldoFmt {
    if (saldo <= 0) return '-';
    return '\$ ${_fmt(saldo)}';
  }

  static String _fmt(double v) {
    final s = v.toStringAsFixed(0);
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  Map<String, dynamic> toJson() => {
    'codigo': codigo,
    'nombre': nombre,
    'categoria': categoria,
    'situacion': situacion,
    'localidad': localidad,
    'provincia': provincia,
    'ultimaCompra': ultimaCompra?.toIso8601String(),
    'ultimoMonto': ultimoMonto,
    'saldo': saldo,
    'maxAtraso': maxAtraso,
  };

  factory Cliente.fromJson(Map<String, dynamic> j) => Cliente(
    codigo: j['codigo']?.toString() ?? '',
    nombre: j['nombre']?.toString() ?? '',
    categoria: j['categoria']?.toString() ?? '',
    situacion: j['situacion']?.toString() ?? '',
    localidad: j['localidad']?.toString() ?? '',
    provincia: j['provincia']?.toString() ?? '',
    ultimaCompra: j['ultimaCompra'] != null ? DateTime.tryParse(j['ultimaCompra'].toString()) : null,
    ultimoMonto: (j['ultimoMonto'] as num?)?.toDouble() ?? 0,
    saldo: (j['saldo'] as num?)?.toDouble() ?? 0,
    maxAtraso: (j['maxAtraso'] as num?)?.toInt() ?? 0,
  );
}
