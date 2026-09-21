import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_error.dart';
import '../../core/models/subject.dart';
import '../../core/services/subject_service.dart';

/// Study tab: subject shortcuts backed by the existing [SubjectService];
/// the full syllabus browsing UI is the existing `/subjects/...` route tree.
class StudyTabScreen extends StatefulWidget {
  const StudyTabScreen({super.key});

  @override
  State<StudyTabScreen> createState() => _StudyTabScreenState();
}

class _StudyTabScreenState extends State<StudyTabScreen> {
  List<Subject> _subjects = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final subjects = await SubjectService.loadSubjects();
      if (!mounted) return;
      setState(() {
        _subjects = subjects;
        _loading = false;
      });
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load subjects. Please try again.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Subjects',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                TextButton(
                  onPressed: () => context.push('/subjects'),
                  child: const Text('Browse All'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildContent(),
            const SizedBox(height: 20),
            Card(
              child: ListTile(
                leading: const Icon(Icons.calendar_month_outlined),
                title: const Text('Calendar'),
                subtitle: const Text('Your routines and upcoming tests'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/calendar'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_error != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
              const SizedBox(width: 12),
              Expanded(child: Text(_error!)),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_subjects.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(
                Icons.school_outlined,
                size: 40,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 12),
              const Text('No subjects available yet'),
            ],
          ),
        ),
      );
    }
    return Column(
      children: _subjects.take(8).map((subject) {
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.menu_book, color: Theme.of(context).colorScheme.primary),
            ),
            title: Text(subject.name),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/subjects/${subject.id}/syllabus', extra: subject.name),
          ),
        );
      }).toList(),
    );
  }
}
