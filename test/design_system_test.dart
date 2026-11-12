import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_marketplace_app/theme/marketplace_theme.dart';
import 'package:flutter_marketplace_app/widgets/marketplace_components.dart';

void main() {
  testWidgets('listing card supports large text and exposes its tap action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: MarketplaceTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
          child: Scaffold(
            body: SizedBox(
              height: 460,
              child: MarketplaceListingCard(
                title: 'A long community advertisement title that wraps',
                price: 'R 1 250.00 / hour',
                location: 'Southernwood, East London',
                isService: true,
                onTap: () => tapped = true,
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.textContaining('A long community'));
    expect(tapped, isTrue);
  });

  testWidgets('empty state action works at a narrow width with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: MarketplaceTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
            body: MarketplaceEmptyState(
              icon: Icons.favorite_border,
              title: 'Keep your favourites close',
              message: 'Save local finds to come back to them later.',
              actionLabel: 'Explore advertisements',
              onAction: () => tapped = true,
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Explore advertisements'));
    expect(tapped, isTrue);
  });

  testWidgets('reduced motion shows entrances immediately', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MarketplaceEntrance(delay: 180, child: Text('Visible now')),
        ),
      ),
    );
    expect(find.text('Visible now'), findsOneWidget);
    expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
