import 'package:flutter/material.dart';

import '../core/constants/theme/app_theme.dart';
import '../core/services/theme_service.dart';
import 'app_config.dart';
import 'app_router.dart';

final class App extends StatelessWidget {
  const App({super.key, required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService.instance,
      builder: (context, _) {
        return MaterialApp.router(
          title: config.appName,
          debugShowCheckedModeBanner: config.isDev,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: ThemeService.instance.mode,
          routerConfig: AppRouter.router,
        );
      },
    );
  }
}
