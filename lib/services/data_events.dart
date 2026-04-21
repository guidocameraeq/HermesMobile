import 'package:flutter/foundation.dart';

/// Event bus global — los services incrementan un contador cuando escriben,
/// y las pantallas que necesitan refrescar se suscriben con ValueListenableBuilder
/// o addListener. Sin paquetes externos, sin streams complicados.
class DataEvents {
  /// Incrementa cada vez que actividades_cliente cambia (crear/editar/completar/eliminar).
  static final actividades = ValueNotifier<int>(0);

  /// Incrementa cada vez que visitas cambia.
  static final visitas = ValueNotifier<int>(0);

  /// Incrementa cuando pedidos cambia (futuro).
  static final pedidos = ValueNotifier<int>(0);

  static void notifyActividades() => actividades.value++;
  static void notifyVisitas() => visitas.value++;
  static void notifyPedidos() => pedidos.value++;
}
