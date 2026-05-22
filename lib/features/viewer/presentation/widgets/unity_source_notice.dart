import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';

bool isUnitySceneSourcePath(String? path) {
  if (path == null) {
    return false;
  }
  final normalized = path.trim().toLowerCase();
  if (normalized.endsWith('.unity')) {
    return true;
  }
  if (normalized.endsWith('/unity/index.html') ||
      normalized.endsWith('unity/index.html') ||
      normalized.contains('unityweb')) {
    return true;
  }
  return false;
}

class UnitySourceNotice extends StatelessWidget {
  const UnitySourceNotice({
    super.key,
    required this.scenePath,
    this.compact = false,
  });

  final String scenePath;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final fileName = _fileNameFromPath(scenePath);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? AppSpacing.xs : AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.extension_rounded,
                  size: compact ? 16 : 18,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Unity-Quelle aktiv',
                    style: textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              fileName,
              style: textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (!compact) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                'Auf Web wird die Unity-WebGL-Seite geladen '
                '(Standard: /unity/index.html).',
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _fileNameFromPath(String path) {
    final normalized = path.trim();
    final parts = normalized.split(RegExp(r'[\\/]'));
    return parts.isEmpty ? normalized : parts.last;
  }
}
