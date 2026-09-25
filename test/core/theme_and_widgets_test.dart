import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/theme/theme.dart';
import 'package:my_praperation/core/widgets/widgets.dart';

Widget testHost(Widget child, {ThemeMode mode = ThemeMode.light}) {
  return MaterialApp(
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: mode,
    home: Scaffold(body: child),
  );
}

void main() {
  group('Design Tokens', () {
    test('AppSpacing scale conforms to 4/8pt rhythm', () {
      expect(AppSpacing.xs, 4.0);
      expect(AppSpacing.sm, 8.0);
      expect(AppSpacing.md, 12.0);
      expect(AppSpacing.lg, 20.0);
      expect(AppSpacing.xl, 32.0);
    });

    test('AppRadius scale is correct', () {
      expect(AppRadius.sm, 6.0);
      expect(AppRadius.md, 8.0);
      expect(AppRadius.lg, 12.0);
      expect(AppRadius.pill, 999.0);
    });

    test('AppDimensions defines accessible minTouchTarget', () {
      expect(AppDimensions.minTouchTarget, 48.0);
      expect(AppDimensions.buttonHeightMd, 44.0);
      expect(AppDimensions.maxContentWidth, 720.0);
    });

    test('Header color is decoupled from primary button color', () {
      final light = AppTheme.light;
      final dark = AppTheme.dark;

      // Header MUST use surface, not primary, so buttons don't visually merge
      expect(light.appBarTheme.backgroundColor, light.colorScheme.surface);
      expect(
        light.appBarTheme.backgroundColor,
        isNot(equals(light.colorScheme.primary)),
      );

      expect(dark.appBarTheme.backgroundColor, dark.colorScheme.surface);
      expect(
        dark.appBarTheme.backgroundColor,
        isNot(equals(dark.colorScheme.primary)),
      );
    });

    test('Legacy AppColors constants remain available and intact', () {
      expect(AppColors.primaryLight, isNotNull);
      expect(AppColors.primaryDark, isNotNull);
      expect(AppColors.error, isNotNull);
      expect(AppColors.success, isNotNull);
      expect(AppColors.warning, isNotNull);
      expect(AppColors.backgroundLight, isNotNull);
      expect(AppColors.surfaceLight, isNotNull);
    });
  });

  group('AppCard', () {
    testWidgets('renders all variants and handles onTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        testHost(
          Column(
            children: [
              const AppCard(
                variant: AppCardVariant.outlined,
                child: Text('Outlined Card'),
              ),
              const AppCard(
                variant: AppCardVariant.elevated,
                child: Text('Elevated Card'),
              ),
              const AppCard(
                variant: AppCardVariant.filled,
                child: Text('Filled Card'),
              ),
              AppCard(
                variant: AppCardVariant.highlight,
                onTap: () => tapped = true,
                child: const Text('Highlight Card'),
              ),
            ],
          ),
        ),
      );

      expect(find.text('Outlined Card'), findsOneWidget);
      expect(find.text('Elevated Card'), findsOneWidget);
      expect(find.text('Filled Card'), findsOneWidget);
      expect(find.text('Highlight Card'), findsOneWidget);

      await tester.tap(find.text('Highlight Card'));
      expect(tapped, isTrue);
    });
  });

  group('AppButton', () {
    testWidgets(
      'renders primary, secondary, destructive, and handles loading',
      (tester) async {
        var count = 0;
        await tester.pumpWidget(
          testHost(
            Column(
              children: [
                AppButton.primary(
                  label: 'Save Changes',
                  onPressed: () => count++,
                ),
                AppButton.secondary(label: 'Cancel', onPressed: () => count++),
                AppButton.destructive(
                  label: 'Delete Item',
                  onPressed: () => count++,
                ),
                AppButton.primary(
                  label: 'Loading Button',
                  isLoading: true,
                  onPressed: () => count++,
                ),
              ],
            ),
          ),
        );

        expect(find.text('Save Changes'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.text('Delete Item'), findsOneWidget);

        // Loading button displays spinner instead of text
        expect(find.text('Loading Button'), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        await tester.tap(find.text('Save Changes'));
        expect(count, 1);

        // Tap on loading button must be ignored
        await tester.tap(find.byType(CircularProgressIndicator));
        expect(count, 1);
      },
    );

    testWidgets('onColor button renders inside dark hero container', (
      tester,
    ) async {
      var clicked = false;
      await tester.pumpWidget(
        testHost(
          Container(
            color: Colors.blue.shade900,
            padding: const EdgeInsets.all(16),
            child: AppButton.onColor(
              label: 'Start Test',
              onPressed: () => clicked = true,
            ),
          ),
        ),
      );

      expect(find.text('Start Test'), findsOneWidget);
      await tester.tap(find.text('Start Test'));
      expect(clicked, isTrue);
    });
  });

  group('AppTextField', () {
    testWidgets('renders input with label, hint, and handles typing', (
      tester,
    ) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        testHost(
          AppTextField(
            controller: controller,
            label: 'Test Name',
            hint: 'Enter title here',
            prefixIcon: Icons.quiz_outlined,
          ),
        ),
      );

      expect(find.text('Test Name'), findsOneWidget);
      expect(find.text('Enter title here'), findsOneWidget);
      expect(find.byIcon(Icons.quiz_outlined), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Midterm Exam');
      expect(controller.text, 'Midterm Exam');
    });
  });

  group('AppBadge and AppChip', () {
    testWidgets(
      'AppBadge renders semantic status labels in light and dark mode',
      (tester) async {
        await tester.pumpWidget(
          testHost(
            const Column(
              children: [
                AppBadge.live(),
                AppBadge.upcoming(),
                AppBadge.completed(),
                AppBadge.pass(),
                AppBadge.fail(),
              ],
            ),
            mode: ThemeMode.dark,
          ),
        );

        expect(find.text('LIVE'), findsOneWidget);
        expect(find.text('UPCOMING'), findsOneWidget);
        expect(find.text('COMPLETED'), findsOneWidget);
        expect(find.text('PASS'), findsOneWidget);
        expect(find.text('FAIL'), findsOneWidget);
      },
    );

    testWidgets('AppChip toggles selection and calls onTap', (tester) async {
      var selected = false;
      await tester.pumpWidget(
        testHost(
          StatefulBuilder(
            builder: (context, setState) {
              return AppChip(
                label: 'Physics',
                isSelected: selected,
                onTap: () => setState(() => selected = !selected),
              );
            },
          ),
        ),
      );

      expect(find.text('Physics'), findsOneWidget);
      await tester.tap(find.text('Physics'));
      await tester.pumpAndSettle();
      expect(selected, isTrue);
    });
  });

  group('AppErrorState and AppEmptyState', () {
    testWidgets('AppErrorState displays message and calls onRetry', (
      tester,
    ) async {
      var retried = false;
      await tester.pumpWidget(
        testHost(
          AppErrorState(
            message: 'Failed to load data',
            onRetry: () => retried = true,
          ),
        ),
      );

      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('Failed to load data'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);

      await tester.tap(find.text('Try Again'));
      expect(retried, isTrue);
    });

    testWidgets('AppEmptyState displays title, subtitle and action', (
      tester,
    ) async {
      var actionTriggered = false;
      await tester.pumpWidget(
        testHost(
          AppEmptyState(
            title: 'No upcoming tests',
            subtitle: 'You are all caught up for today.',
            actionLabel: 'Explore Tests',
            onAction: () => actionTriggered = true,
          ),
        ),
      );

      expect(find.text('No upcoming tests'), findsOneWidget);
      expect(find.text('You are all caught up for today.'), findsOneWidget);
      expect(find.text('Explore Tests'), findsOneWidget);

      await tester.tap(find.text('Explore Tests'));
      expect(actionTriggered, isTrue);
    });
  });

  group('AppDialog', () {
    testWidgets('AppDialog.confirm opens and resolves true on confirm', (
      tester,
    ) async {
      bool? result;
      await tester.pumpWidget(
        testHost(
          Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  result = await AppDialog.confirm(
                    context: context,
                    title: 'Delete Question?',
                    message: 'This cannot be undone.',
                    confirmLabel: 'Delete',
                    isDestructive: true,
                  );
                },
                child: const Text('Open Dialog'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Delete Question?'), findsOneWidget);
      expect(find.text('This cannot be undone.'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
    });
  });

  group('AppConstrainedScroll', () {
    testWidgets('renders content within constrained width', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        testHost(
          const AppConstrainedScroll(child: Text('Constrained Content')),
        ),
      );

      expect(find.text('Constrained Content'), findsOneWidget);
      final constrainedBox = tester.widget<ConstrainedBox>(
        find.byKey(const Key('app_constrained_scroll_box')),
      );
      expect(
        constrainedBox.constraints.maxWidth,
        AppDimensions.maxContentWidth,
      );
    });
  });
}
