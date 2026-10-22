import 'package:flutter/material.dart';

/// 当组件 build 发生异常时渲染的安全错误提示组件
///
/// 特性：
/// 1. 展示通用中文提示，绝不向用户呈现任何原始堆栈或凭据；
/// 2. 使用 [FittedBox] 弹性缩放，自适应各种小局部约束，避免自身溢出；
/// 3. 自带 [Directionality] 与 [Material] 暗色兜底，避免祖先缺失时二次崩溃。
class SafeErrorWidget extends StatelessWidget {
  const SafeErrorWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        color: Color(0xFF141414),
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(8.0),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 36,
                    color: Color(0xFFE57373),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '界面加载遇到问题',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFEEEEEE),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '请稍后重试',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Color(0xFF9E9E9E)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
