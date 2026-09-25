import 'package:flutter/material.dart';

import '../study/presentation/screens/study_home_screen.dart';

/// Direct entry for the Study tab in the main dashboard shell.
/// Mounts [StudyHomeScreen] directly without intermediate wrappers.
class StudyTabScreen extends StatelessWidget {
  const StudyTabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const StudyHomeScreen(embedded: true);
  }
}
