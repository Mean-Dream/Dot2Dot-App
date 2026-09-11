import 'package:flutter/material.dart';
import '../models/dot_model.dart';

// Extracted from home_page.dart. All three painters are self-contained —
// they receive all state through constructor parameters.

class DotPainter extends CustomPainter {
  final List<Dot> dots;
  final bool isHardMode;
  final Offset? mousePos;
  final Offset? lastErasedPos;
  final double rippleValue;
  final bool showLines;
  final bool isEraserMode;
  final bool isGameMode;
  final int nextTargetIndex;
  final double displayWidth;
  final double displayHeight;
  final double originalWidth;
  final double originalHeight;
  final bool showHint;
  final double currentZoom;
  final bool isPanMode;
  final bool isPenUp;
  final int? wrongDotIndex;
  final Set<int> wrongDotIndices;
  final bool isMediumMode;
  final int? insertAnchorIndex;

  DotPainter({
    required this.dots,
    required this.isHardMode,
    this.mousePos,
    this.lastErasedPos,
    this.rippleValue = 0.0,
    required this.showLines,
    required this.isEraserMode,
    this.isGameMode = false,
    this.nextTargetIndex = 0,
    required this.displayWidth,
    required this.displayHeight,
    required this.originalWidth,
    required this.originalHeight,
    required this.currentZoom,
    required this.isPanMode,
    this.showHint = false,
    required this.isPenUp,
    this.wrongDotIndex,
    required this.wrongDotIndices,
    required this.isMediumMode,
    this.insertAnchorIndex,
  }) : super();

  @override
  void paint(Canvas canvas, Size size) {
    if (dots.isEmpty) return;

    double scale = size.width / 1024;

    if (showLines && !isGameMode) {
      _drawGuideLines(canvas, scale);
    }

    _drawDots(canvas, scale, wrongDotIndex);

    if (isGameMode) {
      _drawGamePath(canvas, scale);
    }

    if (rippleValue > 0 && lastErasedPos != null) {
      _drawEraserRipple(canvas);
    }

    if (!isGameMode &&
        mousePos != null &&
        dots.isNotEmpty &&
        !isEraserMode &&
        !isPanMode &&
        !isPenUp) {
      _drawStudioGhostLine(canvas, scale);
    }
  }

  @override
  bool shouldRepaint(DotPainter old) =>
      old.dots != dots ||
      old.dots.length != dots.length ||
      old.nextTargetIndex != nextTargetIndex ||
      old.showHint != showHint ||
      old.wrongDotIndices != wrongDotIndices ||
      old.rippleValue != rippleValue ||
      old.mousePos != mousePos ||
      old.showLines != showLines ||
      old.isEraserMode != isEraserMode ||
      old.isGameMode != isGameMode ||
      old.isPanMode != isPanMode ||
      old.lastErasedPos != lastErasedPos ||
      old.insertAnchorIndex != insertAnchorIndex;

  void _drawGuideLines(Canvas canvas, double scale) {
    if (dots.length < 2) return;
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.1)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(dots[0].x * scale, dots[0].y * scale);

    for (int i = 1; i < dots.length; i++) {
      if (dots[i].isNewPath) {
        path.moveTo(dots[i].x * scale, dots[i].y * scale);
      } else {
        path.lineTo(dots[i].x * scale, dots[i].y * scale);
      }
    }
    canvas.drawPath(path, paint);
  }

  void _drawDots(Canvas canvas, double scale, int? wrongIndex) {
    bool shouldActuallyDraw = showLines && isGameMode && nextTargetIndex > 0;

    if (shouldActuallyDraw) {
      final linePath = Path();
      bool isFirstPoint = true;

      for (int i = 0; i < dots.length; i++) {
        if (i >= nextTargetIndex) break;
        final pos = Offset(dots[i].x * scale, dots[i].y * scale);

        if (isFirstPoint || dots[i].isNewPath) {
          linePath.moveTo(pos.dx, pos.dy);
          isFirstPoint = false;
        } else {
          linePath.lineTo(pos.dx, pos.dy);
        }
      }

      final linePaint = Paint()
        ..color = Colors.green.withValues(alpha: 0.4)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      canvas.drawPath(linePath, linePaint);
    }

    for (int i = 0; i < dots.length; i++) {
      final currentDot = dots[i];
      final center = Offset(currentDot.x * scale, currentDot.y * scale);

      final bool isCompleted = isGameMode && i < nextTargetIndex;
      final bool isTarget = isGameMode && i == nextTargetIndex;
      final bool isInsertAnchor = insertAnchorIndex == i;

      // Anchor glow ring for insert mode
      if (isInsertAnchor) {
        canvas.drawCircle(
          center,
          18.0,
          Paint()
            ..color = Colors.amber.withValues(alpha: 0.35)
            ..style = PaintingStyle.fill,
        );
        canvas.drawCircle(
          center,
          18.0,
          Paint()
            ..color = Colors.amber
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0,
        );
      }

      double currentRadius = isGameMode ? 6.0 : 3.0;

      if (mousePos != null && !isPanMode) {
        final double distance = (center - mousePos!).distance;
        if (distance < 30.0) {
          bool showHoverEffects = !isHardMode && !isMediumMode;

          if (isEraserMode) {
            canvas.drawCircle(
              center,
              14.0,
              Paint()..color = Colors.red.withValues(alpha: 0.15),
            );
            currentRadius += (30.0 - distance) * 0.15;
          } else if (showHoverEffects) {
            if (isTarget) {
              canvas.drawCircle(
                center,
                14.0,
                Paint()..color = Colors.green.withValues(alpha: 0.2),
              );
            }
            currentRadius += (30.0 - distance) * 0.15;
          }
        }
      }

      Color dotColor;
      if (wrongDotIndices.contains(i)) {
        dotColor = Colors.redAccent;
      } else if (isTarget) {
        bool showOrange = (!isHardMode && !isMediumMode) || showHint;
        dotColor = showOrange
            ? Colors.orange
            : Colors.blueAccent.withValues(alpha: isHardMode ? 0.4 : 0.15);
      } else if (isCompleted) {
        dotColor = Colors.green.withValues(alpha: 0.5);
      } else {
        dotColor = Colors.blueAccent.withValues(alpha: isHardMode ? 0.4 : 0.15);
      }

      double finalRadius = (currentRadius * scale).clamp(4.0, 10.0);
      if (wrongDotIndices.contains(i)) finalRadius *= 1.5;
      canvas.drawCircle(center, finalRadius, Paint()..color = dotColor);

      // Pen-lift ring
      if (isGameMode && currentDot.isNewPath) {
        final ringOpacity = isCompleted ? 0.2 : 0.9;
        canvas.drawCircle(
          center,
          finalRadius + 5.0,
          Paint()
            ..color = Colors.amber.withValues(alpha: ringOpacity)
            ..strokeWidth = 1.5
            ..style = PaintingStyle.stroke,
        );
        if (!isCompleted) {
          final liftTp = TextPainter(
            text: TextSpan(
              text: '↑',
              style: TextStyle(
                color: Colors.amber.shade800,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                height: 1,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          liftTp.paint(
            canvas,
            Offset(center.dx - liftTp.width / 2, center.dy - finalRadius - 13),
          );
        }
      }

      if (!isEraserMode) {
        bool showNumber = !isGameMode || !isHardMode || (showHint && isTarget);
        bool showTargetHighlight =
            isTarget && ((!isHardMode && !isMediumMode) || showHint);

        if (showNumber) {
          final textPainter = TextPainter(
            text: TextSpan(
              text: currentDot.label,
              style: TextStyle(
                color: isCompleted ? Colors.black26 : Colors.black87,
                fontSize: (showTargetHighlight) ? 12 : 9,
                fontWeight: (showTargetHighlight)
                    ? FontWeight.w900
                    : FontWeight.normal,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();

          if (showTargetHighlight) {
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                Rect.fromLTWH(
                  center.dx + 2,
                  center.dy - 14,
                  textPainter.width + 4,
                  textPainter.height,
                ),
                const Radius.circular(4),
              ),
              Paint()..color = Colors.white.withValues(alpha: 0.8),
            );
          }
          textPainter.paint(canvas, center + const Offset(5, -12));
        }
      }
    }
  }

  void _drawGamePath(Canvas canvas, double scale) {
    if (nextTargetIndex < 1) return;

    final linePaint = Paint()
      ..color = Colors.green
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < nextTargetIndex - 1; i++) {
      if (dots[i + 1].isNewPath) continue;
      final p1 = Offset(dots[i].x * scale, dots[i].y * scale);
      final p2 = Offset(dots[i + 1].x * scale, dots[i + 1].y * scale);
      canvas.drawLine(p1, p2, linePaint);
    }

    if (nextTargetIndex < dots.length && mousePos != null) {
      final lastDot = dots[nextTargetIndex - 1];
      final startPoint = Offset(lastDot.x * scale, lastDot.y * scale);
      canvas.drawLine(
        startPoint,
        mousePos!,
        Paint()
          ..color = Colors.green.withValues(alpha: 0.4)
          ..strokeWidth = 2.0,
      );
    }
  }

  void _drawStudioGhostLine(Canvas canvas, double scale) {
    final lastDot = dots.last;
    Offset lastDotScreenPos = Offset(lastDot.x * scale, lastDot.y * scale);
    final double distance = (lastDotScreenPos - mousePos!).distance;
    if (distance < 300.0) {
      canvas.drawLine(
        lastDotScreenPos,
        mousePos!,
        Paint()
          ..color = Colors.blueAccent.withValues(alpha: 0.5)
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke,
      );
    }
  }

  void _drawEraserRipple(Canvas canvas) {
    final ripplePaint = Paint()
      ..color = Colors.cyanAccent.withValues(alpha:
        (1.0 - rippleValue).clamp(0.0, 1.0),
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(lastErasedPos!, rippleValue * 35, ripplePaint);
  }
}

class MaskPainter extends CustomPainter {
  final List<Offset> erasedPoints;
  final bool isGameMode;
  final double currentZoom;

  MaskPainter({
    required this.erasedPoints,
    required this.isGameMode,
    this.currentZoom = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!isGameMode && erasedPoints.isEmpty) return;

    final double scale = size.width / 1024;
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white,
    );

    final double holeRadius = (20.0 / currentZoom) * scale;

    final holePaint = Paint()
      ..blendMode = BlendMode.clear
      ..isAntiAlias = true;

    for (final point in erasedPoints) {
      canvas.drawCircle(
        Offset(point.dx * scale, point.dy * scale),
        holeRadius,
        holePaint,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(MaskPainter old) =>
      old.erasedPoints != erasedPoints ||
      old.erasedPoints.length != erasedPoints.length ||
      old.isGameMode != isGameMode ||
      old.currentZoom != currentZoom;
}

/// Lightweight painter used in project-card thumbnails (editor lobby).
/// Draws connecting lines and dots at thumbnail scale — no numbers, no game state.
class ThumbnailDotPainter extends CustomPainter {
  final List<Dot> dots;

  const ThumbnailDotPainter(this.dots);

  @override
  void paint(Canvas canvas, Size size) {
    if (dots.isEmpty) return;

    // Match BoxFit.cover: scale so the 1024-unit space fills the container
    // on both axes (largest scale wins), then center on the other axis.
    final double coverScale =
        size.width > size.height ? size.width / 1024 : size.height / 1024;
    final double offsetX = (size.width - 1024 * coverScale) / 2;
    final double offsetY = (size.height - 1024 * coverScale) / 2;

    Offset toPos(Dot d) =>
        Offset(d.x * coverScale + offsetX, d.y * coverScale + offsetY);

    if (dots.length > 1) {
      final linePaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.75)
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final path = Path();
      final first = toPos(dots[0]);
      path.moveTo(first.dx, first.dy);
      for (int i = 1; i < dots.length; i++) {
        final pos = toPos(dots[i]);
        if (dots[i].isNewPath) {
          path.moveTo(pos.dx, pos.dy);
        } else {
          path.lineTo(pos.dx, pos.dy);
        }
      }
      canvas.drawPath(path, linePaint);
    }

    final fillPaint = Paint()..color = Colors.white;
    final borderPaint = Paint()
      ..color = Colors.black54
      ..strokeWidth = 0.6
      ..style = PaintingStyle.stroke;

    for (final dot in dots) {
      final pos = toPos(dot);
      canvas.drawCircle(pos, 2.0, fillPaint);
      canvas.drawCircle(pos, 2.0, borderPaint);
    }
  }

  @override
  bool shouldRepaint(ThumbnailDotPainter old) =>
      old.dots.length != dots.length || old.dots != dots;
}
