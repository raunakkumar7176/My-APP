import 'package:flutter/material.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/models/subject.dart';
import '../../../core/models/syllabus_node.dart';
import '../../../core/services/subject_service.dart';
import '../../../core/services/syllabus_service.dart';

class StepSyllabus extends StatefulWidget {
  const StepSyllabus({
    required this.selectedNodeIds,
    required this.serverSelectedNodeIds,
    required this.onChanged,
    super.key,
  });

  final List<String> selectedNodeIds;
  final List<String> serverSelectedNodeIds;
  final ValueChanged<List<String>> onChanged;

  @override
  State<StepSyllabus> createState() => _StepSyllabusState();
}

class _StepSyllabusState extends State<StepSyllabus> {
  List<Subject> _subjects = [];
  Subject? _selectedSubject;
  List<SyllabusNode> _allNodes = [];
  bool _isLoadingSubjects = true;
  bool _isLoadingNodes = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSubjects();
  }

  void _loadSubjects() {
    setState(() {
      _isLoadingSubjects = true;
      _error = null;
    });

    SubjectService.loadSubjects()
        .then((subjects) {
          if (mounted) {
            setState(() {
              _subjects = subjects;
              _isLoadingSubjects = false;
            });
          }
        })
        .catchError((e) {
          if (mounted) {
            setState(() {
              _error = e.toString().replaceFirst('AppError: ', '');
              _isLoadingSubjects = false;
            });
          }
        });
  }

  void _loadNodesForSubject(Subject subject) {
    setState(() {
      _isLoadingNodes = true;
      _selectedSubject = subject;
      _allNodes = [];
    });

    SyllabusService.loadNodesForSubject(subject.id)
        .then((nodes) {
          if (mounted) {
            setState(() {
              _allNodes = nodes;
              _isLoadingNodes = false;
            });
          }
        })
        .catchError((e) {
          if (mounted) {
            setState(() {
              _error = e.toString().replaceFirst('AppError: ', '');
              _isLoadingNodes = false;
            });
          }
        });
  }

  void _toggleNode(String nodeId) {
    // Can't deselect server-selected nodes
    if (widget.serverSelectedNodeIds.contains(nodeId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot deselect syllabus added to existing test'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final updated = List<String>.from(widget.selectedNodeIds);
    if (updated.contains(nodeId)) {
      updated.remove(nodeId);
    } else {
      updated.add(nodeId);
    }
    widget.onChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Syllabus',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'Select syllabus topics covered by this test.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface
                      .withValues(alpha: 0.6),
                ),
              ),
              if (widget.selectedNodeIds.isNotEmpty ||
                  widget.serverSelectedNodeIds.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '${widget.serverSelectedNodeIds.length + widget.selectedNodeIds.length} topic(s) selected',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.primaryLight,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoadingSubjects) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _subjects.isEmpty) {
      return _buildError();
    }

    if (_subjects.isEmpty) {
      return _buildEmpty('No subjects available');
    }

    return Column(
      children: [
        _buildSubjectSelector(),
        const Divider(height: 1),
        Expanded(
          child: _selectedSubject == null
              ? _buildEmpty('Select a subject to view syllabus')
              : _isLoadingNodes
              ? const Center(child: CircularProgressIndicator())
              : _allNodes.isEmpty
              ? _buildEmpty('No syllabus available for this subject')
              : _buildNodeTree(),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            Text(
              _error!,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: AppColors.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadSubjects,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.topic_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.onSurface
                  .withValues(alpha: 0.3),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubjectSelector() {
    return SizedBox(
      height: 56,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _subjects.length,
        itemBuilder: (context, index) {
          final subject = _subjects[index];
          final isSelected = _selectedSubject?.id == subject.id;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: FilterChip(
              label: Text(subject.name),
              selected: isSelected,
              onSelected: (_) => _loadNodesForSubject(subject),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNodeTree() {
    final rootNodes = SyllabusService.buildTree(_allNodes);
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: rootNodes.length,
      itemBuilder: (context, index) {
        final node = rootNodes[index];
        final children = SyllabusService.getChildren(_allNodes, node.id);
        return _buildNodeTile(node, children, depth: 0);
      },
    );
  }

  Widget _buildNodeTile(
    SyllabusNode node,
    List<SyllabusNode> children, {
    int depth = 0,
  }) {
    final isLocalSelected = widget.selectedNodeIds.contains(node.id);
    final isServerSelected = widget.serverSelectedNodeIds.contains(node.id);
    final isSelected = isLocalSelected || isServerSelected;
    final hasChildren = children.isNotEmpty;

    return Column(
      children: [
        CheckboxListTile(
          value: isSelected,
          onChanged: isServerSelected ? null : (_) => _toggleNode(node.id),
          title: Padding(
            padding: EdgeInsets.only(left: depth * 16.0),
            child: Text(
              node.name,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: hasChildren ? FontWeight.w600 : FontWeight.w400,
                color: isServerSelected
                    ? Theme.of(context).colorScheme.onSurface
                          .withValues(alpha: 0.5)
                    : null,
              ),
            ),
          ),
          subtitle: node.classLevel != null
              ? Padding(
                  padding: EdgeInsets.only(left: depth * 16.0),
                  child: Text(
                    isServerSelected
                        ? '${node.classLevel} (existing)'
                        : node.classLevel!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface
                          .withValues(alpha: 0.6),
                    ),
                  ),
                )
              : isServerSelected
              ? Padding(
                  padding: EdgeInsets.only(left: depth * 16.0),
                  child: Text(
                    '(existing)',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface
                          .withValues(alpha: 0.6),
                    ),
                  ),
                )
              : null,
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
        ),
        if (hasChildren)
          ...children.map((child) {
            final grandChildren = SyllabusService.getChildren(
              _allNodes,
              child.id,
            );
            return _buildNodeTile(child, grandChildren, depth: depth + 1);
          }),
      ],
    );
  }
}
