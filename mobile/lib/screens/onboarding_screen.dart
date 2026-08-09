import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'home_shell.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final page = PageController();
  int step = 0;
  int? settlementId;

  @override
  void dispose() {
    page.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await context.read<AppState>().completeOnboarding(settlementId: settlementId);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(fastRoute(const HomeShell()));
  }

  void _next() {
    if (step >= 2) {
      _finish();
      return;
    }
    page.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _finish,
                child: const Text('Пропустить'),
              ),
            ),
            Expanded(
              child: PageView(
                controller: page,
                onPageChanged: (i) => setState(() => step = i),
                children: [
                  _Slide(
                    icon: Icons.home_work_outlined,
                    title: 'Рядом56 — всё о районе',
                    body: 'Объявления соседей, справочник организаций, транспорт, афиша и новости Сакмарского района — в одном приложении.',
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.place_outlined, size: 72, color: scheme.primary),
                        const SizedBox(height: 24),
                        Text(
                          'Выберите своё село',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.unbounded(fontSize: 24, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Покажем события, транспорт и новости ближе к вам. Можно изменить в профиле.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
                        ),
                        const SizedBox(height: 24),
                        DropdownButtonFormField<int?>(
                          value: settlementId != null && state.settlements.any((s) => s['id'] == settlementId)
                              ? settlementId
                              : null,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Населённый пункт',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem(value: null, child: Text('Весь район')),
                            ...state.settlements.map(
                              (s) => DropdownMenuItem(
                                value: s['id'] as int,
                                child: Text(s['display_name'] as String),
                              ),
                            ),
                          ],
                          onChanged: (v) => setState(() => settlementId = v),
                        ),
                      ],
                    ),
                  ),
                  _Slide(
                    icon: Icons.add_circle_outline,
                    title: 'Как подать объявление',
                    body: 'Нажмите «Подать» на главной, заполните форму и добавьте фото. После проверки модератором объявление появится в ленте. Связаться с покупателями можно через чат в приложении.',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      3,
                      (i) => Container(
                        width: i == step ? 22 : 8,
                        height: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: i == step ? scheme.primary : scheme.outlineVariant,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _next,
                    child: Text(step >= 2 ? 'Начать' : 'Далее'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Slide extends StatelessWidget {
  const _Slide({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 72, color: scheme.primary),
          const SizedBox(height: 24),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.unbounded(fontSize: 24, fontWeight: FontWeight.w600, height: 1.2),
          ),
          const SizedBox(height: 16),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant, height: 1.45, fontSize: 15),
          ),
        ],
      ),
    );
  }
}
