import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/notification_service.dart';
import 'scorecard_tab.dart';
import 'clientes_tab.dart';
import 'ventas_tab.dart';
import 'mas_tab.dart';
import 'actividad_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final _tabs = const <Widget>[
    ScorecardTab(),
    ClientesTab(),
    VentasTab(),
    MasTab(),
  ];

  @override
  void initState() {
    super.initState();
    // Si la app se abrió desde una notificación (cold start), navegar a la ficha.
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
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart_rounded),
            label: 'Scorecard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people_outline),
            label: 'Clientes',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.trending_up),
            label: 'Ventas',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.more_horiz),
            label: 'Más',
          ),
        ],
      ),
    );
  }
}
