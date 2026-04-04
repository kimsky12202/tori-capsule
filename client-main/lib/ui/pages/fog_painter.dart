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
      // 항상 큰 원을 기본 구멍으로 뚫음 (건물 주변 넓은 범위)
      holesPath.addOval(
        Rect.fromCircle(center: hole.center, radius: circleRadius),
      );
      // 건물 폴리곤이 있으면 추가로 더 정확한 형태도 합침
      if (hole.polygon != null && hole.polygon!.length >= 3) {
        final poly = Path();
        poly.moveTo(hole.polygon!.first.dx, hole.polygon!.first.dy);
        for (final pt in hole.polygon!.skip(1)) {
          poly.lineTo(pt.dx, pt.dy);
        }
        poly.close();
        holesPath.addPath(poly, Offset.zero);
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

    // 구멍 경계 글로우 (부드러운 블러)
    for (final hole in holes) {
      canvas.drawCircle(
        hole.center,
        circleRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 18
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16)
          ..color = const Color(0x5005101F),
      );
    }
  }

  @override
  bool shouldRepaint(NightOverlayPainter old) =>
      old.holes != holes || old.circleRadius != circleRadius;
}
