/// Controller global para cambiar de tab desde cualquier lugar (ej: drawer).
/// HomeScreen registra `switchTab` en initState; otras pantallas la invocan.
class HomeController {
  static void Function(int index)? _switchTab;

  static void register(void Function(int index) cb) => _switchTab = cb;
  static void unregister() => _switchTab = null;

  static void switchTab(int index) => _switchTab?.call(index);
}
