import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/notification_service.dart';
import 'scorecard_tab.dart';
import 'clientes_tab.dart';
import 'assistant_screen.dart';
import 'acciones_tab.dart';
import 'actividad_detail_screen.dart';
import 'home_controller.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final _tabs = const <Widget>[
    ScorecardTab(),      // 0
    AssistantScreen(),   // 1 — Cronos
    ClientesTab(),       // 2
    AccionesTab(),       // 3
  ];

  @override
  void initState() {
    super.initState();
    HomeController.register((i) {
      if (mounted) setState(() => _currentIndex = i);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pending = NotificationService.pendingActividadId;
      if (pending != null && mounted) {
        NotificationService.pendingActividadId = null;
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ActividadDetailScreen(actividadId: pending),
        ));
      }
    });
  }

  @override
  void dispose() {
    HomeController.unregister();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: IndexedStack(
        index: _currentIndex,
        children: _tabs,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        type: BottomNavigationBarType.fixed,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart_rounded),
            label: 'Scorecard',
          ),
          BottomNavigationBarItem(
            icon: _cronosNavIcon(AppColors.navUnselected),
            activeIcon: _cronosNavIcon(AppColors.navSelected),
            label: 'Cronos',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.people_outline),
            label: 'Clientes',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.apps),
            label: 'Acciones',
          ),
        ],
      ),
    );
  }

  /// Icono del tab Cronos: el line art se tiñe al color del estado
  /// (selected/unselected) igual que los Icons Material vecinos.
  Widget _cronosNavIcon(Color color) {
    return Image.asset(
      'assets/icons/cronos.png',
      color: color,
      colorBlendMode: BlendMode.srcIn,
      width: 24,
      height: 24,
      fit: BoxFit.contain,
    );
  }
}
