import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../data/tutorial_repository.dart';
import '../domain/app_tutorial.dart';
import '../widgets/tutorial_video_sheet.dart';

/// "App Kaise Chalayein?" — searchable, category-chipped library of short
/// how-to-use-the-app videos (0100_app_tutorials.sql), played in-app via a
/// bottom sheet rather than jumping out to the YouTube app.
class TutorialListScreen extends StatefulWidget {
  const TutorialListScreen({this.initialCategory, super.key});

  /// Deep-link from a contextual "? Video Dekhein" button elsewhere in the
  /// app (OMR, Create Challenge, Mistake Vault) straight to that category.
  final TutorialCategory? initialCategory;

  @override
  State<TutorialListScreen> createState() => _TutorialListScreenState();
}

class _TutorialListScreenState extends State<TutorialListScreen> {
  final _repo = const SupabaseTutorialRepository();
  List<AppTutorial> _all = [];
  bool _loading = true;
  String _query = '';
  TutorialCategory? _category;

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final tutorials = await _repo.all();
    if (!mounted) return;
    setState(() {
      _all = tutorials;
      _loading = false;
    });
  }

  List<AppTutorial> get _filtered {
    final q = _query.trim().toLowerCase();
    return _all.where((t) {
      if (_category != null && t.category != _category) return false;
      if (q.isEmpty) return true;
      return t.title.toLowerCase().contains(q) ||
          (t.titleHi ?? '').toLowerCase().contains(q) ||
          (t.description ?? '').toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Scaffold(
      appBar: AppBar(title: const Text('App Kaise Chalayein?')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Apni pareshani yahan search karein...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _CategoryChip(
                  label: 'All',
                  selected: _category == null,
                  onTap: () => setState(() => _category = null),
                ),
                for (final c in TutorialCategory.values)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: _CategoryChip(
                      label: c.chipLabel,
                      selected: _category == c,
                      onTap: () => setState(() => _category = c),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                ? const Center(child: Text('Koi video nahi mila.'))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final t = filtered[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: AppColors.error,
                            child: Icon(Icons.play_arrow_rounded, color: Colors.white),
                          ),
                          title: Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            [
                              if (t.category != null) t.category!.title,
                              if (t.durationText != null) t.durationText!,
                            ].join(' · '),
                          ),
                          onTap: () => showTutorialVideoSheet(context, t),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap());
  }
}
