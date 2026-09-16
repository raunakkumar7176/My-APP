import 'package:flutter/material.dart';

import '../../core/constants/theme/app_colors.dart';

final class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.school,
              size: 80,
              color: AppColors.primaryLight,
            ),
            SizedBox(height: 24),
            Text(
              'My Preparation',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 24),
            CircularProgressIndicator(
              color: AppColors.primaryLight,
            ),
          ],
        ),
      ),
    );
  }
}
