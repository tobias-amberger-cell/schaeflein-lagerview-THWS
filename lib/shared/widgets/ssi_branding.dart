import 'package:flutter/material.dart';

class CompanyBranding {
  const CompanyBranding._();

  static const Color yellow = Color(0xFF006FAE);
  static const Color red = Color(0xFFE30613);
  static const Color black = Color(0xFF111111);
}

class CompanyLogo extends StatelessWidget {
  const CompanyLogo({
    super.key,
    this.height = 36,
    this.showWordmark = true,
  });

  final double height;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    final logo = Image.asset(
      'assets/branding/schaeflein_logo.jpg',
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: CompanyBranding.red,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: const Text(
          'Sch\u00E4flein',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );

    if (showWordmark) {
      return SizedBox(
        height: height,
        child: logo,
      );
    }

    return SizedBox(
      height: height,
      child: ClipRect(
        child: Align(
          alignment: Alignment.centerLeft,
          widthFactor: 0.29,
          child: logo,
        ),
      ),
    );
  }
}

class CompanyAppBarTitle extends StatelessWidget {
  const CompanyAppBarTitle({
    super.key,
    required this.sectionTitle,
  });

  final String sectionTitle;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final showWordmark = width >= 360;
    final showSectionTitle =
        width >= 420 && sectionTitle.trim().isNotEmpty;

    return Row(
      children: <Widget>[
        CompanyLogo(height: 24, showWordmark: showWordmark),
        if (showSectionTitle) ...<Widget>[
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              sectionTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ],
    );
  }
}
