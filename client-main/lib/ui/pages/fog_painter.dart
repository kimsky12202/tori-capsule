import 'package:flutter/material.dart';

/// 구멍 모양: polygon이 있으면 건물 형태, 없으면 원형 fallback
class HoleShape {
  final Offset center;
  final List<Offset>? polygon;
  HoleShape({required this.center, this.polygon});
}

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
  final List<HoleShape> holes;
  final double circleRadius;

  NightOverlayPainter({required this.holes, required this.circleRadius});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    for (final hole in holes) {
      if (hole.polygon != null && hole.polygon!.length >= 3) {
        // 건물 폴리곤 모양으로 구멍
        final poly = Path();
        poly.moveTo(hole.polygon!.first.dx, hole.polygon!.first.dy);
        for (final pt in hole.polygon!.skip(1)) {
          poly.lineTo(pt.dx, pt.dy);
        }
        poly.close();
        path.addPath(poly, Offset.zero);
      } else {
        // 폴리곤 없으면 원형 fallback
        path.addOval(
          Rect.fromCircle(center: hole.center, radius: circleRadius),
        );
      }
    }
    path.fillType = PathFillType.evenOdd;

    canvas.drawPath(
      path,
      Paint()..color = const Color(0xCC05101F),
    );

    // 구멍 경계 블러 글로우
    for (final hole in holes) {
      if (hole.polygon != null && hole.polygon!.length >= 3) {
        final poly = Path();
        poly.moveTo(hole.polygon!.first.dx, hole.polygon!.first.dy);
        for (final pt in hole.polygon!.skip(1)) {
          poly.lineTo(pt.dx, pt.dy);
        }
        poly.close();
        canvas.drawPath(
          poly,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 20
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15)
            ..color = const Color(0x8005101F),
        );
      } else {
        canvas.drawCircle(
          hole.center,
          circleRadius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 30
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20)
            ..color = const Color(0x8005101F),
        );
      }
    }
  }

  @override
  bool shouldRepaint(NightOverlayPainter old) =>
      old.holes != holes || old.circleRadius != circleRadius;
}
