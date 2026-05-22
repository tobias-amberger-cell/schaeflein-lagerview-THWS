// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

Widget buildUnityRuntimeView(BuildContext context, String scenePath) {
  return _UnityWebGlFrame(scenePath: scenePath);
}

class _UnityWebGlFrame extends StatefulWidget {
  const _UnityWebGlFrame({required this.scenePath});

  final String scenePath;

  @override
  State<_UnityWebGlFrame> createState() => _UnityWebGlFrameState();
}

class _UnityWebGlFrameState extends State<_UnityWebGlFrame> {
  late final String _viewType;
  late final String _iframeSrc;

  @override
  void initState() {
    super.initState();
    _viewType = 'unity-webgl-${DateTime.now().microsecondsSinceEpoch}';
    _iframeSrc = _resolveUnityWebGlUrl(widget.scenePath);
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
      final iframe = html.IFrameElement()
        ..src = _iframeSrc
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.backgroundColor = '#0f1115'
        ..allowFullscreen = true;
      return iframe;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Stack(
      children: <Widget>[
        Positioned.fill(child: HtmlElementView(viewType: _viewType)),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Text(
                  'Unity WebGL: $_iframeSrc',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String _resolveUnityWebGlUrl(String scenePath) {
  final normalized = scenePath.trim().replaceAll('\\', '/');
  if (normalized.startsWith('http://') || normalized.startsWith('https://')) {
    return normalized;
  }
  if (normalized.toLowerCase().endsWith('.html')) {
    if (normalized.startsWith('/')) {
      return normalized;
    }
    return '/$normalized';
  }
  // Unity-Szene als Quelle -> standardisierter WebGL-Hostpfad.
  return '/unity/index.html';
}

