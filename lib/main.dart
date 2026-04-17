import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'config/theme.dart';
import 'screens/login_screen.dart';
import 'screens/actividad_detail_screen.dart';
import 'services/notification_service.dart';

final navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  await NotificationService.init();

  // Runtime taps: si la app ya está abierta y el usuario toca una notif.
  NotificationService.onTap = (id) {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    nav.push(MaterialPageRoute(
      builder: (_) => ActividadDetailScreen(actividadId: id),
    ));
  };

  runApp(const HermesApp());
}

class HermesApp extends StatelessWidget {
  const HermesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hermes',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme().copyWith(
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          },
        ),
      ),
      home: const LoginScreen(),
    );
  }
}
