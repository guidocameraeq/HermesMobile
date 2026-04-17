import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/cliente.dart';
import '../models/session.dart';
import 'clientes_service.dart';
import '../screens/cliente_detail_screen.dart';

/// Abre la ficha del cliente desde cualquier lugar donde aparezca un nombre/código.
/// Busca en la lista completa del vendedor (cacheada) y navega a [ClienteDetailScreen].
/// Si no lo encuentra, muestra un snackbar.
class ClienteRouter {
  static List<Cliente>? _cache;

  static Future<List<Cliente>> _getClientes() async {
    _cache ??= await ClientesService.getClientes(Session.current.vendedorNombre);
    return _cache!;
  }

  static void clearCache() => _cache = null;

  /// Abre la ficha a partir de un código de cliente.
  static Future<void> open(BuildContext context, String? codigo, {String? nombre}) async {
    if (codigo == null || codigo.trim().isEmpty) {
      _snack(context, 'Código de cliente no disponible');
      return;
    }
    // Mostrar loading rápido
    final scaffold = ScaffoldMessenger.of(context);
    scaffold.showSnackBar(const SnackBar(
      content: Row(children: [
        SizedBox(width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
        SizedBox(width: 12),
        Text('Abriendo ficha...'),
      ]),
      duration: Duration(seconds: 2),
    ));

    try {
      final list = await _getClientes();
      scaffold.hideCurrentSnackBar();
      final cliente = list.where((c) =>
        c.codigo.trim().toUpperCase() == codigo.trim().toUpperCase()
      ).firstOrNull;

      if (cliente == null) {
        _snack(context,
            nombre != null
                ? '$nombre no está en tu cartera actual'
                : 'Cliente $codigo no está en tu cartera');
        return;
      }

      if (!context.mounted) return;
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => ClienteDetailScreen(cliente: cliente),
      ));
    } catch (e) {
      scaffold.hideCurrentSnackBar();
      _snack(context, 'Error al abrir ficha: $e');
    }
  }

  static void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppColors.textMuted,
    ));
  }
}
