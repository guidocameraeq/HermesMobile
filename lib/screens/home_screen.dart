import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/session.dart';
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

  late final List<_TabSpec> _visibleTabs;

  @override
  void initState() {
    super.initState();
    _visibleTabs = _buildVisibleTabs();
    HomeController.register((i) {
      if (mounted && i < _visibleTabs.length) setState(() => _currentIndex = i);
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

  List<_TabSpec> _buildVisibleTabs() {
    final s = Session.current;
    final tabs = <_TabSpec>[];
    if (s.can('mobile.tab_scorecard')) {
      tabs.add(_TabSpec(
        screen: const ScorecardTab(),
        item: const BottomNavigationBarItem(
          icon: Icon(Icons.bar_chart_rounded),
          label: 'Scorecard',
        ),
      ));
    }
    if (s.can('mobile.tab_cronos')) {
      tabs.add(_TabSpec(
        screen: const AssistantScreen(),
        item: BottomNavigationBarItem(
          icon: _cronosNavIcon(AppColors.navUnselected),
          activeIcon: _cronosNavIcon(AppColors.navSelected),
          label: 'Cronos',
        ),
      ));
    }
    if (s.can('mobile.tab_clientes')) {
      tabs.add(_TabSpec(
        screen: const ClientesTab(),
        item: const BottomNavigationBarItem(
          icon: Icon(Icons.people_outline),
          label: 'Clientes',
        ),
      ));
    }
    if (s.can('mobile.tab_acciones')) {
      tabs.add(_TabSpec(
        screen: const AccionesTab(),
        item: const BottomNavigationBarItem(
          icon: Icon(Icons.apps),
          label: 'Acciones',
        ),
      ));
    }
    return tabs;
  }

  @override
  void dispose() {
    HomeController.unregister();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_visibleTabs.isEmpty) {
      // Edge case: rol con mobile.access pero sin ninguna tab habilitada.
      return const Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Tu rol no tiene ninguna pantalla habilitada.\nContactá al administrador.',
              textAlign: TextAlign.center,
              style: AppTextStyles.body,
            ),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: IndexedStack(
        index: _currentIndex,
        children: _visibleTabs.map((t) => t.screen).toList(),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        type: BottomNavigationBarType.fixed,
        items: _visibleTabs.map((t) => t.item).toList(),
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

class _TabSpec {
  final Widget screen;
  final BottomNavigationBarItem item;
  const _TabSpec({required this.screen, required this.item});
}
