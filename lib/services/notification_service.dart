import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

/// Notificaciones locales — programa alarmas que suenan con la app cerrada.
class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  /// Callback que ejecuta cuando el usuario toca una notificación.
  /// Recibe el id (int) de la actividad a abrir.
  static void Function(int actividadId)? onTap;

  /// Si la app se abrió desde una notificación (cold start), guarda el id aquí
  /// para que la UI lo consuma cuando esté lista.
  static int? pendingActividadId;

  /// Inicializar al arrancar la app.
  static Future<void> init() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('America/Argentina/Buenos_Aires'));

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    await _plugin.initialize(
      settings: const InitializationSettings(android: androidSettings),
      onDidReceiveNotificationResponse: (resp) {
        final payload = resp.payload;
        if (payload == null) return;
        final id = int.tryParse(payload);
        if (id == null) return;
        if (onTap != null) {
          onTap!(id);
        } else {
          pendingActividadId = id;
        }
      },
    );

    // Si la app se abrió tocando la notif mientras estaba cerrada:
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      final payload = launch?.notificationResponse?.payload;
      if (payload != null) {
        pendingActividadId = int.tryParse(payload);
      }
    }

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();

    _initialized = true;
  }

  /// Programa una notificación para una fecha/hora.
  static Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    if (!_initialized) await init();
    if (scheduledDate.isBefore(DateTime.now())) return;

    final tzDate = tz.TZDateTime.from(scheduledDate, tz.local);

    const androidDetails = AndroidNotificationDetails(
      'hermes_actividades',
      'Actividades',
      channelDescription: 'Recordatorios de actividades comerciales',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
    );

    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tzDate,
      notificationDetails: const NotificationDetails(android: androidDetails),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: '$id',
    );
  }

  /// Cancela una notificación programada.
  static Future<void> cancel(int notifId) async {
    await _plugin.cancel(id: notifId);
  }
}
