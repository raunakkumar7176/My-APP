import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/theme/app_colors.dart';
import '../../core/responsive/responsive_layout.dart';

final class StarterScreen extends StatelessWidget {
  const StarterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final screenType = ResponsiveLayout.getScreenType(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _buildContent(context, screenType),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, ScreenType screenType) {
    final isDesktop = screenType == ScreenType.desktop;
    final isTablet = screenType == ScreenType.tablet;

    final double logoSize = isDesktop ? 120 : (isTablet ? 100 : 80);
    final double titleSize = isDesktop ? 36 : (isTablet ? 32 : 28);
    final double subtitleSize = isDesktop ? 18 : (isTablet ? 16 : 14);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: logoSize,
            height: logoSize,
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.school,
              size: logoSize * 0.5,
              color: AppColors.primaryLight,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            AppConstants.appName,
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontSize: titleSize,
                  fontWeight: FontWeight.bold,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Your exam preparation companion',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontSize: subtitleSize,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () {
                // Will navigate to auth flow when implemented
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryLight,
                foregroundColor: Colors.white,
              ),
              child: const Text(
                'Get Started',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Version ${AppConstants.appVersion}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
          ),
        ],
      ),
    );
  }
}
