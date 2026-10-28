import 'package:flutter/material.dart';

class TranslationChoices extends StatelessWidget {
  const TranslationChoices({
    super.key,
    required this.choices,
    required this.value,
    required this.onChanged,
    this.label = 'Перевод',
  });

  final Map<String, String> choices;
  final String? value;
  final ValueChanged<String>? onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outlineVariant;
    return Semantics(
      container: true,
      label: label,
      child: RadioGroup<String>(
        groupValue: value,
        onChanged: (next) {
          if (next != null && next != value) onChanged?.call(next);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final entry in choices.entries)
              CustomPaint(
                painter: _TranslationBranchPainter(
                  color: color,
                  isLast: entry.key == choices.keys.last,
                ),
                child: Padding(
                  padding: const EdgeInsets.only(left: 20),
                  child: RadioListTile<String>(
                    key: ValueKey(entry.key),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      entry.value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    value: entry.key,
                    enabled: onChanged != null,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TranslationBranchPainter extends CustomPainter {
  const _TranslationBranchPainter({required this.color, required this.isLast});

  final Color color;
  final bool isLast;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    final middle = size.height / 2;
    canvas.drawLine(
      const Offset(1, 0),
      Offset(1, isLast ? middle : size.height),
      paint,
    );
    canvas.drawLine(Offset(1, middle), Offset(20, middle), paint);
  }

  @override
  bool shouldRepaint(_TranslationBranchPainter oldDelegate) =>
      color != oldDelegate.color || isLast != oldDelegate.isLast;
}
