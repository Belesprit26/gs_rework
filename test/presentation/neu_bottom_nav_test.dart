import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gs_rework/presentation/shared/widgets/neu/neu_bottom_nav.dart';

void main() {
  const items = [
    NeuNavItem(icon: Icons.dashboard_outlined, label: 'Home'),
    NeuNavItem(icon: Icons.bar_chart_outlined, label: 'Usage'),
    NeuNavItem(icon: Icons.settings_outlined, label: 'Settings'),
  ];

  Widget harness({required int selected, required ValueChanged<int> onTap}) {
    return MaterialApp(
      home: Scaffold(
        body: const Center(child: Text('BODY')),
        bottomNavigationBar: NeuBottomNav(
          items: items,
          selectedIndex: selected,
          onSelected: onTap,
        ),
      ),
    );
  }

  testWidgets('bottom nav hugs its content height and does not fill the screen',
      (tester) async {
    // A tall screen so a mis-constrained bar (that expands to fill) would
    // be obvious. This is the regression guard: the bar must stay short.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(harness(selected: 0, onTap: (_) {}));

    final navSize = tester.getSize(find.byType(NeuBottomNav));
    final screenHeight = tester.view.physicalSize.height;

    // The bar must occupy only a small slice of the screen, never balloon
    // to fill it (the bug that squeezed out the body + app bar).
    expect(navSize.height, lessThan(160));
    expect(navSize.height, greaterThan(0));
    expect(navSize.height, lessThan(screenHeight * 0.2));

    // Body still renders (it wasn't squeezed to zero height).
    expect(find.text('BODY'), findsOneWidget);
  });

  testWidgets('tapping a destination reports its index', (tester) async {
    int? tapped;
    await tester.pumpWidget(harness(selected: 0, onTap: (i) => tapped = i));

    await tester.tap(find.text('Settings'));
    expect(tapped, 2);

    await tester.tap(find.text('Usage'));
    expect(tapped, 1);
  });
}
