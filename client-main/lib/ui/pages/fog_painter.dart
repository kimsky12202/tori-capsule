import 'package:flutter/material.dart';

class FogPainter extends CustomPainter {
  final List<Offset> holes;
  final double radius;

  FogPainter({required this.holes, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final fogPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    for (final hole in holes) {
      fogPath.addOval(Rect.fromCircle(center: hole, radius: radius));
    }
    fogPath.fillType = PathFillType.evenOdd;

    canvas.drawPath(
      fogPath,
      Paint()..color = const Color(0xCC1A1A2E),
    );
  }

  @override
  bool shouldRepaint(FogPainter old) =>
      old.holes != holes || old.radius != radius;
}

class NightOverlayPainter extends CustomPainter {
  final List<Offset> holes;
  final double radius;

  NightOverlayPainter({required this.holes, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    for (final hole in holes) {
      path.addOval(Rect.fromCircle(center: hole, radius: radius));
    }
    path.fillType = PathFillType.evenOdd;

    canvas.drawPath(
      path,
      Paint()..color = const Color(0xCC05101F),
    );

    // 구멍 경계 블러 글로우
    for (final hole in holes) {
      canvas.drawCircle(
        hole,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 30
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20)
          ..color = const Color(0x8005101F),
      );
    }
  }

  @override
  bool shouldRepaint(NightOverlayPainter old) =>
      old.holes != holes || old.radius != radius;
}
