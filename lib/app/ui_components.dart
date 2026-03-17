import 'package:flutter/material.dart';

const double kAppMaxContentWidth = 1480;
const AssetImage kCircleOfFifthsAsset = AssetImage('cord.jpg');

class AppContentFrame extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  const AppContentFrame({
    super.key,
    required this.child,
    this.maxWidth = kAppMaxContentWidth,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 20),
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: const Color(0xFFF0F4FA),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Stack(
            children: [
              Positioned(
                right: -90,
                top: -48,
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        scheme.primaryContainer.withValues(alpha: 0.46),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: -120,
                bottom: -120,
                child: Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        scheme.secondaryContainer.withValues(alpha: 0.42),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Padding(padding: padding, child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class AppHeroPanel extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> actions;

  const AppHeroPanel({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon = Icons.bolt_rounded,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF0E4E87).withValues(alpha: 0.96),
            const Color(0xFF2A7DB0).withValues(alpha: 0.9),
          ],
        ),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 50,
            height: 50,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                ),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Wrap(spacing: 8, runSpacing: 8, children: actions),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AppSectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;
  final EdgeInsetsGeometry contentPadding;
  final IconData? icon;

  const AppSectionCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.contentPadding = const EdgeInsets.all(16),
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(18),
              ),
              border: Border(
                bottom: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.24),
                ),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null) ...[
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      color: scheme.primaryContainer.withValues(alpha: 0.82),
                    ),
                    child: Icon(icon, size: 16),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          Padding(padding: contentPadding, child: child),
        ],
      ),
    );
  }
}

class AppStateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool isError;

  const AppStateCard({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.isError = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final containerColor = isError
        ? colorScheme.errorContainer.withValues(alpha: 0.55)
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.68);
    return Container(
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (isError ? colorScheme.error : colorScheme.outlineVariant)
              .withValues(alpha: 0.26),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 26,
              color: isError ? colorScheme.error : colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(message, style: Theme.of(context).textTheme.bodyMedium),
                  if (actionLabel != null && onAction != null) ...[
                    const SizedBox(height: 10),
                    FilledButton.tonal(
                      onPressed: onAction,
                      child: Text(actionLabel!),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppActionListTile extends StatelessWidget {
  final Widget title;
  final Widget? subtitle;
  final List<Widget> actions;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final double borderRadius;

  const AppActionListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const <Widget>[],
    this.onTap,
    this.backgroundColor,
    this.borderRadius = 14,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        color:
            backgroundColor ??
            colorScheme.surfaceContainerHighest.withValues(alpha: 0.46),
      ),
      child: ListTile(
        title: title,
        subtitle: subtitle,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        minVerticalPadding: 10,
        trailing: actions.isEmpty
            ? null
            : Wrap(
                spacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: actions,
              ),
        onTap: onTap,
      ),
    );
  }
}

class AppInfoPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? borderColor;

  const AppInfoPill({
    super.key,
    required this.label,
    this.icon,
    this.backgroundColor,
    this.foregroundColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final resolvedForeground = foregroundColor ?? colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color:
            backgroundColor ??
            colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
        border: Border.all(
          color:
              borderColor ?? colorScheme.outlineVariant.withValues(alpha: 0.32),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: resolvedForeground),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: resolvedForeground,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class AppLoadingState extends StatelessWidget {
  final String message;

  const AppLoadingState({super.key, this.message = '불러오는 중입니다...'});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          const SizedBox(height: 10),
          Text(message, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

InputDecoration appInputDecoration(
  BuildContext context, {
  required String label,
  String? hint,
  String? helper,
  Widget? prefixIcon,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    helperText: helper,
    prefixIcon: prefixIcon,
    filled: true,
    fillColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0.74),
    border: const OutlineInputBorder(),
  );
}

class CircleOfFifthsHelpButton extends StatelessWidget {
  final String label;
  final bool compact;

  const CircleOfFifthsHelpButton({
    super.key,
    this.label = '5도권 참고',
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final button = compact
        ? OutlinedButton.icon(
            onPressed: () => _openDialog(context),
            icon: const Icon(Icons.library_music_rounded, size: 16),
            label: Text(label),
          )
        : FilledButton.tonalIcon(
            onPressed: () => _openDialog(context),
            icon: const Icon(Icons.library_music_rounded),
            label: Text(label),
          );
    return Tooltip(message: '5도권 참고표 보기', child: button);
  }

  Future<void> _openDialog(BuildContext context) async {
    await precacheImage(kCircleOfFifthsAsset, context);
    if (!context.mounted) return;
    await _showCircleOfFifthsDialog(context);
  }
}

Future<void> _showCircleOfFifthsDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: CircleOfFifthsGuideCard(),
        ),
      ),
    ),
  );
}

class CircleOfFifthsGuideCard extends StatelessWidget {
  const CircleOfFifthsGuideCard({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.music_note_rounded),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '5도권 키 참고표',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Text(
            '팀에서 "악보 시작 코드"로 키를 기억할 때 빠르게 비교하는 참고표입니다.',
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: RepaintBoundary(
              child: Container(
                color: Colors.black12,
                constraints: const BoxConstraints(maxHeight: 520),
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Image(
                    image: kCircleOfFifthsAsset,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '• 시계 방향: 완전5도 올림  (+1)\n'
            '• 반시계 방향: 완전5도 내림 (-1)\n'
            '• 동음이명: Db = C#, Gb = F#, B = Cb',
            style: textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
