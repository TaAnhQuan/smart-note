import 'package:flutter/material.dart';

class ContentExtractSelectionPainter extends CustomPainter {
  final List<Offset> gesturePoints;
  final Rect? selectionRect;
  final double animationValue;
  final double pulseValue;
  final bool isDrawing;

  ContentExtractSelectionPainter({
    required this.gesturePoints,
    this.selectionRect,
    required this.animationValue,
    required this.pulseValue,
    required this.isDrawing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gesturePaint = Paint()
      ..color = Colors.blue.withValues(alpha: 0.6)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final selectionPaint = Paint()
      ..color = Colors.blue.withValues(alpha: 0.8 * animationValue)
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke;

    if (isDrawing && gesturePoints.length > 1) {
      Path gesturePath = Path();
      gesturePath.moveTo(gesturePoints.first.dx, gesturePoints.first.dy);
      for (int i = 1; i < gesturePoints.length; i++) {
        gesturePath.lineTo(gesturePoints[i].dx, gesturePoints[i].dy);
      }
      canvas.drawPath(gesturePath, gesturePaint);
    }

    if (selectionRect != null && !isDrawing) {
      final center = selectionRect!.center;
      final animatedRect = Rect.fromCenter(
        center: center,
        width: selectionRect!.width * animationValue,
        height: selectionRect!.height * animationValue,
      );
      final animatedRRect = RRect.fromRectAndRadius(
          animatedRect, Radius.circular(12.0 * animationValue));

      canvas.drawRRect(animatedRRect, selectionPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
