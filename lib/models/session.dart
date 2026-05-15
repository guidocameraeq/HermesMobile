/// Sesión del usuario actualmente logueado.
/// Se puebla al hacer login y se limpia al cerrar sesión.
class Session {
  static Session? _instance;

  String username = '';
  String vendedorNombre = '';
  String role = '';

  Set<String> _permissions = const <String>{};

  Session._();

  static Session get current {
    _instance ??= Session._();
    return _instance!;
  }

  void set({
    required String username,
    required String vendedorNombre,
    required String role,
    Map<String, dynamic> permisos = const <String, dynamic>{},
  }) {
    this.username = username;
    this.vendedorNombre = vendedorNombre;
    this.role = role;
    _permissions = permisos.entries
        .where((e) => e.value == true)
        .map((e) => e.key)
        .toSet();
  }

  void clear() {
    username = '';
    vendedorNombre = '';
    role = '';
    _permissions = const <String>{};
  }

  bool get isLoggedIn => username.isNotEmpty;

  /// Devuelve true si el rol del usuario tiene la key habilitada.
  /// Si la key no existe en el dict del rol, se asume false (cerrado por defecto).
  bool can(String key) => _permissions.contains(key);
}
