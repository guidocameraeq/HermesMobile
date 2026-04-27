import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Bottom sheet con la ficha de Cronos: misión, capacidades, ejemplos.
/// Se abre al tocar "Cronos" en el AppBar.
class CronosInfoSheet extends StatelessWidget {
  const CronosInfoSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CronosInfoSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: AppColors.bgSidebar,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppColors.textMuted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollCtrl,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _heroHeader(),
                    const SizedBox(height: 20),
                    _section('🎯 MISIÓN',
                        'Ser tu secretario personal. Anotar, recordar y organizar '
                        'todo lo que tenés que hacer con tus clientes, sin que tengas '
                        'que tocar formularios — hablame o escribime y yo me ocupo.'),
                    const SizedBox(height: 18),
                    _capabilities(),
                    const SizedBox(height: 18),
                    _examplesSection(),
                    const SizedBox(height: 18),
                    _tipsSection(),
                    const SizedBox(height: 30),
                    _footer(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80, height: 80,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.accent.withOpacity(0.45),
                      AppColors.accent.withOpacity(0),
                    ],
                    stops: const [0.0, 0.7],
                  ),
                ),
              ),
              Image.asset(
                'assets/icons/cronos.png',
                color: Colors.white,
                colorBlendMode: BlendMode.srcIn,
                fit: BoxFit.contain,
                width: 76, height: 76,
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Cronos', style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 24, fontWeight: FontWeight.bold,
              )),
              SizedBox(height: 2),
              Text('Tu asistente personal de agenda',
                  style: TextStyle(color: AppColors.accent, fontSize: 13)),
              SizedBox(height: 6),
              Text('GPT-4o-mini · voz con Whisper',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _section(String title, String body) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        )),
        const SizedBox(height: 8),
        Text(body, style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14, height: 1.5,
        )),
      ],
    );
  }

  Widget _capabilities() {
    final items = [
      ('📅', 'Agendar actividades', 'Llamadas, visitas, reuniones, propuestas, recordatorios'),
      ('📍', 'Cargar visitas AHORA', 'Con GPS automático, registra dónde estás'),
      ('✅', 'Consultar tu agenda', 'Pendientes de hoy, mañana, esta semana, de cierto cliente'),
      ('☑️', 'Cerrar tareas', '"Ya llamé a García" las marca como completadas'),
      ('🔁', 'Repetir o encadenar', '"4 llamadas más, una por semana" o "visitas M/Mi/J"'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('⚡ QUÉ PUEDO HACER', style: TextStyle(
          color: AppColors.textMuted, fontSize: 11,
          fontWeight: FontWeight.w700, letterSpacing: 1.2,
        )),
        const SizedBox(height: 10),
        ...items.map((item) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.$1, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.$2, style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13, fontWeight: FontWeight.w600,
                    )),
                    const SizedBox(height: 2),
                    Text(item.$3, style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12, height: 1.3,
                    )),
                  ],
                ),
              ),
            ],
          ),
        )),
      ],
    );
  }

  Widget _examplesSection() {
    final categorias = [
      ('Agendar', [
        '"Recordame llamar a García mañana a las 10"',
        '"Agendá reunión con Pérez el jueves a las 15"',
        '"Propuesta para Rodríguez la semana que viene"',
        '"Visita a López todos los martes durante un mes"',
      ]),
      ('Cargar visita con GPS', [
        '"Estoy visitando a García"',
        '"Llegué a Pérez para cobrar"',
        '"Pasé a dejar catálogo a Rodríguez"',
      ]),
      ('Consultar', [
        '"¿Qué tengo que hacer hoy?"',
        '"Pendientes de esta semana"',
        '"¿Qué tengo con García?"',
        '"¿Cuál es mi próxima tarea?"',
        '"¿Qué visité esta semana?"',
      ]),
      ('Cerrar tareas', [
        '"Ya llamé a García"',
        '"Hice la reunión con Pérez"',
      ]),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('💬 EJEMPLOS DE LO QUE PODÉS DECIRME', style: TextStyle(
          color: AppColors.textMuted, fontSize: 11,
          fontWeight: FontWeight.w700, letterSpacing: 1.2,
        )),
        const SizedBox(height: 12),
        ...categorias.map((cat) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(cat.$1, style: const TextStyle(
                color: AppColors.accent, fontSize: 11,
                fontWeight: FontWeight.w700, letterSpacing: 0.8,
              )),
              const SizedBox(height: 6),
              ...cat.$2.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(e, style: const TextStyle(
                  color: AppColors.textPrimary, fontSize: 12, height: 1.4,
                )),
              )),
            ],
          ),
        )),
      ],
    );
  }

  Widget _tipsSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.accent.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: const [
            Icon(Icons.lightbulb_outline, color: AppColors.accent, size: 14),
            SizedBox(width: 6),
            Text('TIPS', style: TextStyle(
              color: AppColors.accent, fontSize: 10,
              fontWeight: FontWeight.w700, letterSpacing: 1.2,
            )),
          ]),
          const SizedBox(height: 8),
          _tip('Podés hablarme (tocá el 🎤) o escribir.'),
          _tip('Si hay varios clientes con el mismo nombre, te muestro chips para elegir.'),
          _tip('Puedo agendar varias cosas en un solo mensaje.'),
          _tip('Si digo "el mismo cliente", sigo el contexto — no me repitás.'),
        ],
      ),
    );
  }

  Widget _tip(String t) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('• ', style: TextStyle(color: AppColors.accent, fontSize: 12)),
        Expanded(child: Text(t, style: const TextStyle(
          color: AppColors.textPrimary, fontSize: 12, height: 1.4,
        ))),
      ],
    ),
  );

  Widget _footer() {
    return const Center(
      child: Text(
        'Hermes Mobile · Cronos v3',
        style: TextStyle(color: AppColors.textMuted, fontSize: 10),
      ),
    );
  }
}
