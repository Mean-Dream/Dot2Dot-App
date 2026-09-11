import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/project_model.dart';

abstract final class ShareService {
  /// Renders a 1080×1080 share card for [project] and opens the native share
  /// sheet. Silently no-ops on web (file sharing not available).
  static Future<void> shareCompletion(Project project) async {
    if (kIsWeb) return;

    try {
      final bytes = await _buildCard(project);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/wonderdot_share.png');
      await file.writeAsBytes(bytes);

      final level = project.hardCleared
          ? 'Hard'
          : project.mediumCleared
              ? 'Medium'
              : 'Easy';

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: 'I just completed "$level" on "${project.name}" in WonderDot! 🎨',
      );
    } catch (e) {
      debugPrint('ShareService error: $e');
    }
  }

  // ── Card renderer ─────────────────────────────────────────────────────────────

  static Future<Uint8List> _buildCard(Project project) async {
    const w = 1080.0;
    const h = 1080.0;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));

    // Background gradient
    final bgPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        const Offset(w, h),
        [const Color(0xFF111E18), const Color(0xFF253B30)],
      );
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), bgPaint);

    _drawDotGrid(canvas, w, h);

    // Center card panel
    final cardRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(80, 200, w - 160, h - 380),
      const Radius.circular(40),
    );
    canvas.drawRRect(cardRect, Paint()..color = const Color(0xFF1D3028));
    canvas.drawRRect(
      cardRect,
      Paint()
        ..color = const Color(0xFF4EFE98).withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Labels
    _drawText(canvas, '✨  I COMPLETED',
        fontSize: 32, color: const Color(0xFF7CB897), bold: false,
        letterSpacing: 3, centerX: w / 2, y: 290, maxWidth: w - 200);

    _drawText(canvas, project.name,
        fontSize: 72, color: Colors.white, bold: true,
        centerX: w / 2, y: 380, maxWidth: w - 160);

    _drawStars(canvas, project, w / 2, 580);

    // Divider
    canvas.drawLine(
      const Offset(160, 680),
      const Offset(w - 160, 680),
      Paint()
        ..color = const Color(0xFF4EFE98).withValues(alpha: 0.2)
        ..strokeWidth = 1.5,
    );

    _drawText(canvas, 'Connect the dots. Reveal the picture.',
        fontSize: 30, color: const Color(0xFFB0C4B8), bold: false,
        centerX: w / 2, y: 720, maxWidth: w - 200);

    _drawText(canvas, 'WonderDot',
        fontSize: 48, color: const Color(0xFF4EFE98), bold: true,
        centerX: w / 2, y: 910, maxWidth: w - 200);

    final picture = recorder.endRecording();
    final image = await picture.toImage(w.toInt(), h.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  static void _drawDotGrid(Canvas canvas, double w, double h) {
    final paint = Paint()
      ..color = const Color(0xFF4EFE98).withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (double x = 60; x < w; x += 60) {
      for (double y = 60; y < h; y += 60) {
        canvas.drawCircle(Offset(x, y), 2, paint);
      }
    }
  }

  static void _drawStars(Canvas canvas, Project project, double cx, double y) {
    const size = 56.0;
    const gap = 32.0;
    final levels = [
      ('Easy', project.easyCleared),
      ('Medium', project.mediumCleared),
      ('Hard', project.hardCleared),
    ];

    final totalW = levels.length * size + (levels.length - 1) * gap;
    double x = cx - totalW / 2;

    for (final (label, cleared) in levels) {
      final fill = cleared ? const Color(0xFFF7D060) : const Color(0xFF3A4A40);
      canvas.drawCircle(Offset(x + size / 2, y + size / 2), size / 2,
          Paint()..color = fill);
      _drawText(canvas, label,
          fontSize: 22,
          color: cleared ? const Color(0xFFF7D060) : const Color(0xFF556655),
          bold: false,
          centerX: x + size / 2,
          y: y + size + 10,
          maxWidth: 140);
      x += size + gap;
    }
  }

  static void _drawText(
    Canvas canvas,
    String text, {
    required double fontSize,
    required Color color,
    required bool bold,
    required double centerX,
    required double y,
    required double maxWidth,
    double letterSpacing = 0,
  }) {
    final style = ui.ParagraphStyle(
      textAlign: TextAlign.center,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      fontSize: fontSize,
    );
    final builder = ui.ParagraphBuilder(style)
      ..pushStyle(ui.TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        letterSpacing: letterSpacing,
      ))
      ..addText(text);
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: maxWidth));
    canvas.drawParagraph(paragraph, Offset(centerX - maxWidth / 2, y));
  }
}
