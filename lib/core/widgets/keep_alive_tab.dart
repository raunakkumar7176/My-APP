import 'package:flutter/material.dart';

/// Wraps one tab's subtree so [TabBarView] does not dispose it when the
/// user switches tabs — scroll position, form state, and loaded data all
/// survive a round-trip away and back.
class KeepAliveTab extends StatefulWidget {
  const KeepAliveTab({required this.child, super.key});

  final Widget child;

  @override
  State<KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<KeepAliveTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
