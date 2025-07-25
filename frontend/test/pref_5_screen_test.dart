import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tatar_shower/screens/pref-screens/pref_5_screen.dart';
import 'package:tatar_shower/onboarding/onboarding_data.dart';
import 'package:tatar_shower/l10n/app_localizations.dart';

void main() {
  Widget makeTestableWidget(Widget child, {Locale? locale}) {
    return ChangeNotifierProvider(
      create: (_) => OnboardingData(),
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
        routes: {
          '/prefDone': (context) => Scaffold(body: Text('PrefDone Screen')),
        },
      ),
    );
  }

  testWidgets('PreferencesScreen5 отображает опции и позволяет выбрать одну', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      makeTestableWidget(
        const PreferencesScreen5(),
        locale: const Locale('ru'),
      ),
    );

    expect(find.text('7 дней'), findsOneWidget);
    expect(find.text('14 дней'), findsOneWidget);
    expect(find.text('21 день'), findsOneWidget);
    expect(find.text('Другое'), findsOneWidget);

    await tester.tap(find.text('14 дней'));
    await tester.pump();

    final selectedCircle = find.byWidgetPredicate((widget) {
      if (widget is Container && widget.decoration is BoxDecoration) {
        final decoration = widget.decoration as BoxDecoration;
        return decoration.shape == BoxShape.circle && decoration.color != null;
      }
      return false;
    });
    expect(selectedCircle, findsWidgets);
  });

  testWidgets(
    'Кнопка Next переводит на /prefDone при выборе стандартной опции',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        makeTestableWidget(
          const PreferencesScreen5(),
          locale: const Locale('ru'),
        ),
      );

      await tester.tap(find.text('21 день'));
      await tester.pump();

      await tester.tap(find.text('Дальше'));
      await tester.pumpAndSettle();

      expect(find.text('PrefDone Screen'), findsOneWidget);
    },
  );

  testWidgets('Кнопка Skip присутствует и кликабельна', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      makeTestableWidget(
        const PreferencesScreen5(),
        locale: const Locale('ru'),
      ),
    );

    final skipButton = find.text('Пропустить');
    expect(skipButton, findsOneWidget);

    await tester.tap(skipButton);
    await tester.pump();
  });
}
