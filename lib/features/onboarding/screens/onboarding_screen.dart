import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/app_logger.dart';
import '../../../data/models/medicine.dart';
import '../../../data/models/schedule.dart';
import '../../medicines/screens/home_screen.dart';
import '../../medicines/widgets/medicine_card.dart';
import '../widgets/permissions_panel.dart';

/// Three-page first-run flow: reminders, inventory, permissions.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  /// shared_preferences flag set once the flow is finished.
  static const completedKey = 'onboarding_completed';

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _pageCount = 3;
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int page) => _controller.animateToPage(
    page,
    duration: const Duration(milliseconds: 300),
    curve: Curves.easeOut,
  );

  Future<void> _finish() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(OnboardingScreen.completedKey, true);
    } catch (e) {
      // Worst case the user sees onboarding again; never block them here.
      AppLogger.warn('Saving onboarding state failed', e);
    }
    if (!mounted) return;
    await Navigator.of(context)
        .pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _pageCount - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (p) => setState(() => _page = p),
                children: const [
                  _Page(
                    icon: Icons.notifications_active_rounded,
                    title: 'Never miss a dose',
                    body:
                        'PillTrack reminds you when it is time to take each '
                        'medicine — tablets, syrups, insulin, inhalers and '
                        'more. Tap “Taken” right from the notification.',
                  ),
                  _Page(
                    icon: Icons.inventory_2_rounded,
                    title: 'Track your supply — if you want',
                    body:
                        'Optional, for any medicine: tell PillTrack how much '
                        'you have, and every dose you log counts it down. '
                        "You'll get a heads-up before you run out.",
                    extra: _InventoryExample(),
                  ),
                  _Page(
                    icon: Icons.verified_user_rounded,
                    title: 'Turn on reminders',
                    body:
                        'PillTrack needs your permission to remind you. '
                        'Everything stays on this phone — no account needed.',
                    extra: PermissionsPanel(),
                  ),
                ],
              ),
            ),
            _PageDots(current: _page, count: _pageCount),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: isLast
                  ? SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _finish,
                        child: const Text('Get started'),
                      ),
                    )
                  : Row(
                      children: [
                        TextButton(
                          onPressed: () => _goTo(_pageCount - 1),
                          child: const Text('Skip'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () => _goTo(_page + 1),
                          child: const Text('Next'),
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

class _Page extends StatelessWidget {
  const _Page({
    required this.icon,
    required this.title,
    required this.body,
    this.extra,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Scrollable so large accessibility font sizes never overflow.
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
      children: [
        Center(
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 64,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(height: 28),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          body,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
        if (extra != null) ...[const SizedBox(height: 24), extra!],
      ],
    );
  }
}

/// A non-interactive sample card: a syrup with 45 ml left, taken 3x5 ml a day,
/// so the real [MedicineCard] shows "45 ml left" and a red "3 days" chip.
class _InventoryExample extends StatelessWidget {
  const _InventoryExample();

  static const _syrup = Medicine(
    id: 'example',
    name: 'Cough syrup',
    form: 'liquid',
    packageType: 'bottle',
    doseUnit: 'ml',
    unitsPerPackage: 100,
    looseUnits: 45,
    refillThresholdDays: 3,
    createdAt: 0,
  );

  static const _schedules = [
    Schedule(id: 'a', medicineId: 'example', timeOfDay: '08:00', doseAmount: 5),
    Schedule(id: 'b', medicineId: 'example', timeOfDay: '14:00', doseAmount: 5),
    Schedule(id: 'c', medicineId: 'example', timeOfDay: '20:00', doseAmount: 5),
  ];

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Example: cough syrup, 45 ml left, refill in 3 days',
      excludeSemantics: true,
      child: Column(
        children: [
          IgnorePointer(
            child: MedicineCard(
              medicine: _syrup,
              schedules: _schedules,
              onTap: () {},
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Refill in 3 days',
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.current, required this.count});
  final int current;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Page ${current + 1} of $count',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: i == current ? 24 : 10,
              height: 10,
              decoration: BoxDecoration(
                color: i == current ? scheme.primary : scheme.outlineVariant,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
        ],
      ),
    );
  }
}
