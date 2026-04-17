import 'package:google_sign_in/google_sign_in.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Sincroniza actividades con Google Calendar.
/// Uso: CalendarService.I (singleton). Requiere sign-in previo.
class CalendarService {
  CalendarService._();
  static final CalendarService I = CalendarService._();

  static const _kMode = 'calendar_mode';         // off | manual | auto
  static const _kAccount = 'calendar_account';   // email

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static final _gsi = GoogleSignIn(
    scopes: [gcal.CalendarApi.calendarEventsScope],
  );

  // ── Estado / preferencias ─────────────────────────────────────
  Future<String> getMode() async =>
      await _storage.read(key: _kMode) ?? 'off';

  Future<void> setMode(String mode) =>
      _storage.write(key: _kMode, value: mode);

  Future<String?> getAccount() => _storage.read(key: _kAccount);

  Future<bool> get isEnabled async => (await getMode()) != 'off';
  Future<bool> get isAuto async => (await getMode()) == 'auto';

  // ── Auth ──────────────────────────────────────────────────────
  /// Sign-in interactivo. Retorna email o lanza excepción.
  Future<String> connect() async {
    final account = await _gsi.signIn();
    if (account == null) throw Exception('Sign-in cancelado');
    await _storage.write(key: _kAccount, value: account.email);
    return account.email;
  }

  Future<void> disconnect() async {
    try { await _gsi.signOut(); } catch (_) {}
    await _storage.delete(key: _kAccount);
    await _storage.write(key: _kMode, value: 'off');
  }

  Future<gcal.CalendarApi?> _api() async {
    var account = _gsi.currentUser;
    account ??= await _gsi.signInSilently();
    if (account == null) return null;
    final client = await _gsi.authenticatedClient();
    if (client == null) return null;
    return gcal.CalendarApi(client);
  }

  // ── CRUD de eventos ───────────────────────────────────────────
  /// Crea un evento. Retorna el eventId o null si falló.
  Future<String?> createEvent({
    required String titulo,
    required DateTime inicio,
    required Duration duracion,
    String? descripcion,
    String? ubicacion,
  }) async {
    try {
      final api = await _api();
      if (api == null) return null;
      final event = gcal.Event(
        summary: titulo,
        description: descripcion,
        location: ubicacion,
        start: gcal.EventDateTime(dateTime: inicio.toUtc(), timeZone: 'UTC'),
        end: gcal.EventDateTime(
          dateTime: inicio.add(duracion).toUtc(),
          timeZone: 'UTC',
        ),
        reminders: gcal.EventReminders(
          useDefault: false,
          overrides: [
            gcal.EventReminder(method: 'popup', minutes: 15),
          ],
        ),
      );
      final created = await api.events.insert(event, 'primary');
      return created.id;
    } catch (_) {
      return null;
    }
  }

  /// Actualiza un evento existente. Retorna true si OK.
  Future<bool> updateEvent({
    required String eventId,
    required String titulo,
    required DateTime inicio,
    required Duration duracion,
    String? descripcion,
  }) async {
    try {
      final api = await _api();
      if (api == null) return false;
      final event = gcal.Event(
        summary: titulo,
        description: descripcion,
        start: gcal.EventDateTime(dateTime: inicio.toUtc(), timeZone: 'UTC'),
        end: gcal.EventDateTime(
          dateTime: inicio.add(duracion).toUtc(),
          timeZone: 'UTC',
        ),
      );
      await api.events.patch(event, 'primary', eventId);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Elimina un evento. Retorna true si OK (también si ya no existía).
  Future<bool> deleteEvent(String eventId) async {
    try {
      final api = await _api();
      if (api == null) return false;
      await api.events.delete('primary', eventId);
      return true;
    } catch (_) {
      return false;
    }
  }
}
