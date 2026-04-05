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

  // 폴리곤을 중심에서 scale배 확장
  List<Offset> _scalePolygon(List<Offset> pts, double scale) {
    final cx = pts.map((p) => p.dx).reduce((a, b) => a + b) / pts.length;
    final cy = pts.map((p) => p.dy).reduce((a, b) => a + b) / pts.length;
    return pts.map((p) => Offset(
      cx + (p.dx - cx) * scale,
      cy + (p.dy - cy) * scale,
    )).toList();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final holesPath = Path();
    for (final hole in holes) {
      // 폴리곤이 있을 때만 뚫음 (원형 fallback 없음)
      if (hole.polygon == null || hole.polygon!.length < 3) continue;
      final expanded = _scalePolygon(hole.polygon!, 1.0);
      final poly = Path();
      poly.moveTo(expanded.first.dx, expanded.first.dy);
      for (final pt in expanded.skip(1)) {
        poly.lineTo(pt.dx, pt.dy);
      }
      poly.close();
      holesPath.addPath(poly, Offset.zero);
    }

    final screenRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final overlay = Path()..addRect(screenRect);
    // 폴리곤을 화면 영역으로 clip → 꼭짓점이 화면 밖으로 나갈 때 삼각형 아티팩트 방지
    final clippedHoles = Path.combine(
      PathOperation.intersect,
      Path()..addRect(screenRect),
      holesPath,
    );
    final result = Path.combine(PathOperation.difference, overlay, clippedHoles);

    canvas.drawPath(
      result,
      Paint()..color = const Color(0xCC05101F),
    );

    // 경계 글로우 (화면 안으로 clip)
    canvas.save();
    canvas.clipRect(screenRect);
    for (final hole in holes) {
      if (hole.polygon == null || hole.polygon!.length < 3) continue;
      final expanded = _scalePolygon(hole.polygon!, 1.0);
      final poly = Path();
      poly.moveTo(expanded.first.dx, expanded.first.dy);
      for (final pt in expanded.skip(1)) {
        poly.lineTo(pt.dx, pt.dy);
      }
      poly.close();
      canvas.drawPath(
        poly,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 18
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16)
          ..color = const Color(0x5005101F),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(NightOverlayPainter old) =>
      old.holes != holes || old.circleRadius != circleRadius;
}
