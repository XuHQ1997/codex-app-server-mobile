import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// Wraps markdown rendering behind a single widget so the underlying package
/// can be swapped without touching call sites.
///
/// Headings are deliberately flattened to near-body size (only weight and a
/// slight step differentiate them). In a chat transcript the default h1/h2
/// sizes are jarringly large and make the log look chaotic; keeping type nearly
/// uniform — like ChatGPT's chat UI — reads much calmer.
class MarkdownView extends StatelessWidget {
  const MarkdownView({super.key, required this.data, this.selectable = true});

  final String data;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyMedium;
    final bodySize = base?.fontSize ?? 14.0;
    // Headings step down toward the body size; the largest is only a bit
    // bigger than normal text and everything is bold rather than huge.
    final h1 = base?.copyWith(fontSize: bodySize + 3, fontWeight: FontWeight.w700);
    final h2 = base?.copyWith(fontSize: bodySize + 2, fontWeight: FontWeight.w700);
    final h3 = base?.copyWith(fontSize: bodySize + 1, fontWeight: FontWeight.w600);
    final hSmall = base?.copyWith(fontSize: bodySize, fontWeight: FontWeight.w600);

    return MarkdownBody(
      data: data,
      selectable: selectable,
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        h1: h1,
        h2: h2,
        h3: h3,
        h4: hSmall,
        h5: hSmall,
        h6: hSmall,
        // Tighten the vertical padding the package adds around headings so the
        // near-uniform sizes don't leave awkward gaps.
        h1Padding: const EdgeInsets.only(top: 8, bottom: 2),
        h2Padding: const EdgeInsets.only(top: 8, bottom: 2),
        h3Padding: const EdgeInsets.only(top: 6, bottom: 2),
        h4Padding: const EdgeInsets.only(top: 6, bottom: 2),
        h5Padding: const EdgeInsets.only(top: 4, bottom: 2),
        h6Padding: const EdgeInsets.only(top: 4, bottom: 2),
        code: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
        ),
        codeblockDecoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
