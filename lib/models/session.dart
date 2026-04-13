/// Sesión del usuario actualmente logueado.
/// Se puebla al hacer login y se limpia al cerrar sesión.
class Session {
  static Session? _instance;

  String username = '';
  String vendedorNombre = '';
  String role = '';

  Session._();

  static Session get current {
    _instance ??= Session._();
    return _instance!;
  }

  void set({
    required String username,
    required String vendedorNombre,
    required String role,
  }) {
    this.username = username;
    this.vendedorNombre = vendedorNombre;
    this.role = role;
  }

  void clear() {
    username = '';
    vendedorNombre = '';
    role = '';
  }

  bool get isLoggedIn => username.isNotEmpty;
}
