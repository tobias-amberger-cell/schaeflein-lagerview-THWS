import 'package:flutter/material.dart';

import 'unity_runtime_view_delegate.dart';

class UnityRuntimeView extends StatelessWidget {
  const UnityRuntimeView({
    super.key,
    required this.scenePath,
  });

  final String scenePath;

  @override
  Widget build(BuildContext context) {
    return buildUnityRuntimeView(context, scenePath);
  }
}
