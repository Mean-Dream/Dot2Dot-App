import 'dart:math' as math;
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/dot_model.dart';

class PdfService {
  static Future<void> generateAndPrint(
    List<Dot> dots,
    String name, {
    Uint8List? imageBytes,
  }) async {
    final pdf = pw.Document();

    // Bounding box for page 1 (puzzle — dots only, no image)
    final double minX = dots.map((e) => e.x).reduce((a, b) => a < b ? a : b);
    final double maxX = dots.map((e) => e.x).reduce((a, b) => a > b ? a : b);
    final double minY = dots.map((e) => e.y).reduce((a, b) => a < b ? a : b);
    final double maxY = dots.map((e) => e.y).reduce((a, b) => a > b ? a : b);
    final double contentWidth = maxX - minX;
    final double contentHeight = maxY - minY;

    // --- PAGE 1: THE PUZZLE (numbered dots, no image) ---
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(50),
        build: (pw.Context context) {
          return pw.Column(
            children: [
              pw.Text(
                name.toUpperCase().split('-').last.split('.').first,
                style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 10),
              pw.Text(
                'Connect the dots in order!',
                style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
              ),
              pw.Divider(thickness: 1, color: PdfColors.grey300),
              pw.SizedBox(height: 20),
              pw.Expanded(
                child: pw.LayoutBuilder(
                  builder: (pw.Context context, pw.BoxConstraints? constraints) {
                    final double maxWidth = constraints?.maxWidth ?? 400;
                    final double maxHeight = constraints?.maxHeight ?? 600;
                    final double scale =
                        math.min(maxWidth / contentWidth, maxHeight / contentHeight) * 0.9;

                    return pw.Center(
                      child: pw.SizedBox(
                        width: contentWidth * scale,
                        height: contentHeight * scale,
                        child: pw.Stack(
                          children: dots.map((dot) {
                            return pw.Positioned(
                              left: (dot.x - minX) * scale,
                              top: (dot.y - minY) * scale,
                              child: pw.Row(
                                mainAxisSize: pw.MainAxisSize.min,
                                children: [
                                  pw.Container(
                                    width: 4,
                                    height: 4,
                                    decoration: const pw.BoxDecoration(
                                      color: PdfColors.black,
                                      shape: pw.BoxShape.circle,
                                    ),
                                  ),
                                  pw.SizedBox(width: 2),
                                  pw.Text(
                                    '${dot.sequenceOrder}',
                                    style: pw.TextStyle(
                                      fontSize: 7,
                                      fontWeight: pw.FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    );
                  },
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Divider(thickness: 0.5, color: PdfColors.grey300),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('MyAIDotToDot.com', style: const pw.TextStyle(fontSize: 9)),
                  pw.Text('Total Dots: ${dots.length}', style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
            ],
          );
        },
      ),
    );

    // --- PAGE 2: ANSWER KEY (original image + dot positions, no lines) ---
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(50),
        build: (pw.Context context) {
          return pw.Column(
            children: [
              pw.Text(
                'ANSWER KEY',
                style: pw.TextStyle(fontSize: 18, color: PdfColors.grey700),
              ),
              pw.SizedBox(height: 20),
              pw.Expanded(
                child: pw.LayoutBuilder(
                  builder: (pw.Context context, pw.BoxConstraints? constraints) {
                    final double avail = math.min(
                      constraints?.maxWidth ?? 400,
                      constraints?.maxHeight ?? 500,
                    );
                    final double scale = avail / 1024.0;

                    return pw.Center(
                      child: pw.SizedBox(
                        width: 1024 * scale,
                        height: 1024 * scale,
                        child: pw.Stack(
                          children: [
                            // Original image as background
                            if (imageBytes != null)
                              pw.Positioned.fill(
                                child: pw.Image(
                                  pw.MemoryImage(imageBytes),
                                  fit: pw.BoxFit.fill,
                                ),
                              ),

                            // Dot markers — white fill with dark border so they
                            // stand out on any image background.
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
                                    border: pw.Border.all(
                                      color: PdfColors.black,
                                      width: 0.75,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'DotToDot_${name.replaceAll(' ', '_')}.pdf',
    );
  }
}
