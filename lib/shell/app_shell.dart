import 'package:flutter/material.dart';

import '../features/me/me_page.dart';
import '../features/monk/monk_page.dart';
import '../features/practice_list/practice_list_page.dart';
import '../theme.dart';

/// 三页签 Shell：左「修」中「僧」右「我」横向切换，
/// 底部图标栏平移切换，当前页对应图标放大。
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final PageController _controller = PageController(initialPage: 1);
  int _index = 1;

  static const List<({String label, Widget page})> _pages = [
    (label: '修', page: PracticeListPage()),
    (label: '僧', page: MonkPage()),
    (label: '我', page: MePage()),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(int index) {
    _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _controller,
        onPageChanged: (i) => setState(() => _index = i),
        children: [for (final p in _pages) p.page],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          height: 64,
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0x14E8DFC8))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (var i = 0; i < _pages.length; i++)
                _TabIcon(
                  label: _pages[i].label,
                  selected: _index == i,
                  onTap: () => _go(i),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabIcon extends StatelessWidget {
  const _TabIcon({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 88,
        height: 64,
        child: Center(
          child: AnimatedScale(
            scale: selected ? 1.35 : 1.0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: Text(
              label,
              style: TextStyle(
                color: selected ? AppTheme.gold : AppTheme.inkFaint,
                fontSize: 18,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
