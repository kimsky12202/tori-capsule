import 'package:flutter/material.dart';

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
    // 모든 구멍을 하나의 Path로 합침 (겹쳐도 정상)
    final holesPath = Path();
    for (final hole in holes) {
      if (hole.polygon != null && hole.polygon!.length >= 3) {
        final poly = Path();
        poly.moveTo(hole.polygon!.first.dx, hole.polygon!.first.dy);
        for (final pt in hole.polygon!.skip(1)) {
          poly.lineTo(pt.dx, pt.dy);
        }
        poly.close();
        holesPath.addPath(poly, Offset.zero);
      } else {
        holesPath.addOval(
          Rect.fromCircle(center: hole.center, radius: circleRadius),
        );
      }
    }

    // 전체 오버레이에서 구멍을 뺌 (겹침 문제 해결)
    final overlay = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final result = Path.combine(PathOperation.difference, overlay, holesPath);

    canvas.drawPath(
      result,
      Paint()..color = const Color(0xCC05101F),
    );

    // 구멍 경계 글로우 (블러 경계만)
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
            ..strokeWidth = 12
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10)
            ..color = const Color(0x6005101F),
        );
      } else {
        canvas.drawCircle(
          hole.center,
          circleRadius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 12
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10)
            ..color = const Color(0x6005101F),
        );
      }
    }
  }

  @override
  bool shouldRepaint(NightOverlayPainter old) =>
      old.holes != holes || old.circleRadius != circleRadius;
}
