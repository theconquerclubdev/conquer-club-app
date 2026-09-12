import 'dart:typed_data';

// Used on non-web platforms (Android/iOS/desktop). downloadPdf() never
// calls this branch there — it calls Printing.sharePdf instead — but the
// function must exist so the conditional import compiles for every target.
void downloadPdfBytes(Uint8List bytes, String fileName) {
  throw UnsupportedError('downloadPdfBytes is web-only.');
}
