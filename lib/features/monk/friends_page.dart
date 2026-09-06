import 'package:flutter/material.dart';

import '../../theme.dart';

/// 友（好友列表）：查看好友修为与成就、交换花瓣。
///
/// 全 app 唯一强依赖网络的功能（设计方案 6.3），走同步引擎 + Supabase
/// Realtime。v0.1 未接入后端，此页为占位。
class FriendsPage extends StatelessWidget {
  const FriendsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('友')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people_outline, color: AppTheme.inkFaint, size: 48),
              const SizedBox(height: 16),
              const Text(
                '好友功能暂未开放',
                style: TextStyle(color: AppTheme.ink, fontSize: 17),
              ),
              const SizedBox(height: 10),
              const Text(
                '这是全 app 唯一强依赖网络的功能：添加好友、查看好友修为与成就、交换花瓣。\n'
                '接入后端（Supabase Auth + Realtime）后在此展开。',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.inkFaint, fontSize: 13, height: 1.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
