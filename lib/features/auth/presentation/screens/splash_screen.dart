import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/state/app_state.dart';
import '../../../../shared/widgets/ssi_branding.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _logoScale;
  late final Animation<double> _contentOpacity;
  late final Animation<double> _progressValue;

  static const List<String> _loadingTextKeys = <String>[
    'loadingA',
    'loadingB',
    'loadingC',
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..repeat(reverse: true);
    _logoScale = Tween<double>(begin: 0.97, end: 1.03).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _contentOpacity = Tween<double>(begin: 0.75, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _progressValue = Tween<double>(begin: 0.18, end: 0.92).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _goNext();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _goNext() async {
    await Future<void>.delayed(const Duration(milliseconds: 1850));
    if (!mounted) {
      return;
    }
    final appState = context.read<AppState>();
    context.go(appState.isAuthenticated ? '/dashboard' : '/login');
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final logoHeight = width >= AppBreakpoints.tablet ? 84.0 : 62.0;

    return Scaffold(
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final loadingTexts = <String>[
            context.tr('loadingA'),
            context.tr('loadingB'),
            context.tr('loadingC'),
          ];
          final loadingTextIndex =
              (_controller.value * _loadingTextKeys.length).floor() %
                  _loadingTextKeys.length;

          return Stack(
            children: <Widget>[
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        Theme.of(context).colorScheme.surface,
                        Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.85),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: -120 + (50 * _controller.value),
                right: -120 + (25 * _controller.value),
                child: _GlowBubble(
                  size: width >= AppBreakpoints.tablet ? 360 : 260,
                  color: CompanyBranding.yellow.withValues(alpha: 0.35),
                ),
              ),
              Positioned(
                left: -90 + (40 * _controller.value),
                bottom: -140 + (35 * _controller.value),
                child: _GlowBubble(
                  size: width >= AppBreakpoints.tablet ? 300 : 220,
                  color: CompanyBranding.red.withValues(alpha: 0.24),
                ),
              ),
              SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: width >= AppBreakpoints.rail ? 1040 : 720,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Opacity(
                        opacity: _contentOpacity.value,
                        child: _buildSplashContent(
                          context: context,
                          logoHeight: logoHeight,
                          loadingText: loadingTexts[loadingTextIndex],
                          progressValue: _progressValue.value,
                          width: width,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSplashContent({
    required BuildContext context,
    required double logoHeight,
    required String loadingText,
    required double progressValue,
    required double width,
  }) {
    final isWide = width >= AppBreakpoints.rail;

    if (!isWide) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Transform.scale(
            scale: _logoScale.value,
            child: CompanyLogo(height: logoHeight),
          ),
          const SizedBox(height: AppSpacing.md),
          _WarehouseAnimation(progress: _controller.value),
          const SizedBox(height: AppSpacing.lg),
          Text(
            AppConstants.appName,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            context.tr('splashSubtitle'),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: AppSpacing.lg),
          _buildLoadingCard(
            context: context,
            loadingText: loadingText,
            progressValue: progressValue,
          ),
        ],
      );
    }

    return Row(
      children: <Widget>[
        Expanded(
          flex: 5,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Transform.scale(
                scale: _logoScale.value,
                alignment: Alignment.centerLeft,
                child: CompanyLogo(height: logoHeight),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                AppConstants.appName,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                context.tr('splashSubtitle'),
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: AppSpacing.lg),
              _buildLoadingCard(
                context: context,
                loadingText: loadingText,
                progressValue: progressValue,
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          flex: 4,
          child: _WarehouseAnimation(progress: _controller.value),
        ),
      ],
    );
  }

  Widget _buildLoadingCard({
    required BuildContext context,
    required String loadingText,
    required double progressValue,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    loadingText,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 7,
                value: progressValue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlowBubble extends StatelessWidget {
  const _GlowBubble({
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: color,
              blurRadius: 56,
              spreadRadius: 14,
            ),
          ],
        ),
      ),
    );
  }
}

class _WarehouseAnimation extends StatelessWidget {
  const _WarehouseAnimation({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final scannerX = -1 + (2 * progress);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: AspectRatio(
        aspectRatio: 3.1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Stack(
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List<Widget>.generate(8, (index) {
                    final base = 0.36 + ((index % 3) * 0.12);
                    final wave =
                        (0.08 * (0.5 - (progress - (index * 0.07)).abs())).clamp(
                      -0.04,
                      0.05,
                    ).toDouble();
                    final heightFactor = (base + wave).clamp(0.25, 0.8);

                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: FractionallySizedBox(
                            heightFactor: heightFactor,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: index.isEven
                                    ? colorScheme.primary.withValues(alpha: 0.82)
                                    : colorScheme.secondary.withValues(alpha: 0.78),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                Align(
                  alignment: Alignment(scannerX, 0),
                  child: Container(
                    width: 2,
                    height: double.infinity,
                    decoration: BoxDecoration(
                      color: CompanyBranding.red.withValues(alpha: 0.7),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: CompanyBranding.red.withValues(alpha: 0.5),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List<Widget>.generate(4, (index) {
                      final active = ((progress * 4).floor() % 4) == index;
                      return Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: active
                              ? CompanyBranding.yellow
                              : colorScheme.outline.withValues(alpha: 0.35),
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
