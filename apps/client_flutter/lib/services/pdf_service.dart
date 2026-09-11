import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/dot_model.dart';

class PdfService {
  /// Renders the puzzle and answer-key pages and opens the system print dialog.
  static Future<void> generateAndPrint(
    List<Dot> dots,
    String name, {
    Uint8List? imageBytes,
  }) async {
    if (dots.isEmpty) return;

    final puzzlePng = await _renderPuzzle(dots);

    final pdf = pw.Document();
    final puzzleImage = pw.MemoryImage(puzzlePng);

    // ── Page 1: puzzle (raster render, no lines, numbers only) ───────────────
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 36),
        build: (pw.Context ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(
              _cleanName(name),
              style: pw.TextStyle(
                fontSize: 24,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              'Connect the dots in order to reveal the picture!',
              style: const pw.TextStyle(
                fontSize: 11,
                color: PdfColors.grey600,
              ),
            ),
            pw.Divider(color: PdfColors.grey300, thickness: 0.5),
            pw.SizedBox(height: 8),
            pw.Expanded(
              child: pw.Center(child: pw.Image(puzzleImage)),
            ),
            pw.SizedBox(height: 8),
            pw.Divider(color: PdfColors.grey300, thickness: 0.5),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('WonderDot', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500)),
                pw.Text('${dots.length} dots', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500)),
              ],
            ),
          ],
        ),
      ),
    );

    // ── Page 2: answer key ────────────────────────────────────────────────────
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 36),
        build: (pw.Context ctx) {
          final answerPng = _buildAnswerKeyWidget(dots, imageBytes);
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                'ANSWER KEY — ${_cleanName(name)}',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.grey700,
                ),
              ),
              pw.SizedBox(height: 12),
              pw.Expanded(child: pw.Center(child: answerPng)),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (_) async => pdf.save(),
      name: 'WonderDot_${_cleanName(name).replaceAll(' ', '_')}.pdf',
    );
  }

  // ── Puzzle raster renderer ─────────────────────────────────────────────────

  static Future<Uint8List> _renderPuzzle(List<Dot> dots) async {
    const double size = 2048;
    const double pad = 100;

    final minX = dots.map((d) => d.x).reduce(math.min);
    final maxX = dots.map((d) => d.x).reduce(math.max);
    final minY = dots.map((d) => d.y).reduce(math.min);
    final maxY = dots.map((d) => d.y).reduce(math.max);

    final cw = (maxX - minX).clamp(1.0, double.infinity);
    final ch = (maxY - minY).clamp(1.0, double.infinity);
    final scale = math.min((size - pad * 2) / cw, (size - pad * 2) / ch);

    // Centre the content inside the canvas
    final ox = pad + ((size - pad * 2) - cw * scale) / 2;
    final oy = pad + ((size - pad * 2) - ch * scale) / 2;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));

    // White background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size, size),
      Paint()..color = Colors.white,
    );

    final dotPaint = Paint()..color = Colors.black;
    final penUpPaint = Paint()
      ..color = Colors.grey.shade400
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (final dot in dots) {
      final x = (dot.x - minX) * scale + ox;
      final y = (dot.y - minY) * scale + oy;
      final center = Offset(x, y);

      // Dot circle
      canvas.drawCircle(center, 4.5, dotPaint);

      // Pen-up ring — signals "lift pen here before continuing"
      if (dot.isNewPath) {
        canvas.drawCircle(center, 11.0, penUpPaint);
      }

      // Number label
      final tp = TextPainter(
        text: TextSpan(
          text: dot.label,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x + 6, y - 13));
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  // ── Answer key widget ─────────────────────────────────────────────────────

  static pw.Widget _buildAnswerKeyWidget(List<Dot> dots, Uint8List? imageBytes) {
    return pw.LayoutBuilder(
      builder: (_, constraints) {
        final double avail = math.min(
          constraints?.maxWidth ?? 400,
          constraints?.maxHeight ?? 500,
        );
        final double scale = avail / 1024.0;

        return pw.SizedBox(
          width: 1024 * scale,
          height: 1024 * scale,
          child: pw.Stack(
            children: [
              if (imageBytes != null)
                pw.Positioned.fill(
                  child: pw.Image(
                    pw.MemoryImage(imageBytes),
                    fit: pw.BoxFit.fill,
                  ),
                ),
              // Connection lines between consecutive dots
              pw.CustomPaint(
                size: PdfPoint(1024 * scale, 1024 * scale),
                painter: (pdfCanvas, pdfSize) {
                  pdfCanvas.setStrokeColor(
                    imageBytes != null ? PdfColors.white : PdfColors.grey400,
                  );
                  pdfCanvas.setLineWidth(0.6);
                  for (int i = 1; i < dots.length; i++) {
                    if (dots[i].isNewPath) continue;
                    pdfCanvas.moveTo(dots[i - 1].x * scale, pdfSize.y - dots[i - 1].y * scale);
                    pdfCanvas.lineTo(dots[i].x * scale, pdfSize.y - dots[i].y * scale);
                  }
                  pdfCanvas.strokePath();
                },
              ),
              // Dot markers
              ...dots.map(
                (dot) => pw.Positioned(
                  left: dot.x * scale - 3,
                  top: dot.y * scale - 3,
                  child: pw.Container(
                    width: 6,
                    height: 6,
                    decoration: pw.BoxDecoration(
                      color: PdfColors.white,
                      shape: pw.BoxShape.circle,
                      border: pw.Border.all(color: PdfColors.black, width: 0.75),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _cleanName(String raw) =>
      raw.split('-').last.split('.').first.trim();
}
