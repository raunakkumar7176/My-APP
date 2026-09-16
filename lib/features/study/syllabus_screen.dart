import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/theme/app_colors.dart';
import '../../core/models/syllabus_node.dart';
import '../../core/services/syllabus_service.dart';

final class SyllabusScreen extends StatefulWidget {
  const SyllabusScreen({super.key, required this.subjectId, this.subjectName});

  final String subjectId;
  final String? subjectName;

  @override
  State<SyllabusScreen> createState() => _SyllabusScreenState();
}

class _SyllabusScreenState extends State<SyllabusScreen> {
  List<SyllabusNode> _allNodes = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadNodes();
  }

  void _loadNodes() {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    SyllabusService.loadNodesForSubject(widget.subjectId).then((nodes) {
      if (mounted) {
        setState(() {
          _allNodes = nodes;
          _isLoading = false;
        });
      }
    }).catchError((e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('AppError: ', '');
          _isLoading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.subjectName ?? 'Syllabus'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _buildError();
    }

    final rootNodes = SyllabusService.buildTree(_allNodes);

    if (rootNodes.isEmpty) {
      return _buildEmpty();
    }

    return _buildNodeList(rootNodes);
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              'Failed to load syllabus',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.error,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadNodes,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.topic_outlined,
              size: 64,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No syllabus available',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Syllabus topics will appear here when they are added.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.7),
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNodeList(List<SyllabusNode> nodes) {
    return RefreshIndicator(
      onRefresh: () async => _loadNodes(),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: nodes.length,
        itemBuilder: (context, index) {
          final node = nodes[index];
          final children = SyllabusService.getChildren(_allNodes, node.id);
          return _SyllabusNodeTile(
            node: node,
            childCount: children.length,
            onTap: () {
              if (children.isNotEmpty) {
                context.push(
                  '/subjects/${widget.subjectId}/syllabus/${node.id}',
                  extra: node.name,
                );
              } else {
                context.push(
                  '/subjects/${widget.subjectId}/nodes/${node.id}/materials',
                  extra: node.name,
                );
              }
            },
          );
        },
      ),
    );
  }
}

class _SyllabusNodeTile extends StatelessWidget {
  const _SyllabusNodeTile({
    required this.node,
    required this.childCount,
    required this.onTap,
  });

  final SyllabusNode node;
  final int childCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: childCount > 0
                ? AppColors.primaryLight.withValues(alpha: 0.1)
                : AppColors.secondaryLight.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            childCount > 0 ? Icons.folder_outlined : Icons.description_outlined,
            color: childCount > 0 ? AppColors.primaryLight : AppColors.secondaryLight,
          ),
        ),
        title: Text(
          node.name,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w500,
              ),
        ),
        subtitle: node.classLevel != null
            ? Text(
                node.classLevel!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.6),
                    ),
              )
            : null,
        trailing: childCount > 0
            ? Text(
                '$childCount',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.primaryLight,
                      fontWeight: FontWeight.w600,
                    ),
              )
            : Icon(
                Icons.chevron_right,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.5),
              ),
        onTap: onTap,
      ),
    );
  }
}
