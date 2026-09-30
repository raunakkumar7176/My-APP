import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/constants/theme/app_theme.dart';
import '../core/services/locale_service.dart';
import '../core/services/theme_service.dart';
import '../core/widgets/no_internet_overlay.dart';
import '../l10n/app_localizations.dart';
import 'app_config.dart';
import 'app_router.dart';

final class App extends StatelessWidget {
  const App({super.key, required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([ThemeService.instance, LocaleService.instance]),
      builder: (context, _) {
        return MaterialApp.router(
          title: config.appName,
          debugShowCheckedModeBanner: config.isDev,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: ThemeService.instance.mode,
          locale: LocaleService.instance.locale,
          supportedLocales: LocaleService.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routerConfig: AppRouter.router,
          builder: (context, child) => NetworkAwareOverlay(child: child ?? const SizedBox.shrink()),
        );
      },
    );
  }
}
