import 'dart:typed_data';
import 'dart:html' as html;

// Direct browser download via Blob + <a download>. Does not touch the
// printing package's web plugin channel (net.nfet.printing), so a stale
// build / service worker cache that hasn't registered that plugin can't
// throw MissingPluginException here.
void downloadPdfBytes(Uint8List bytes, String fileName) {
  final blob = html.Blob([bytes], 'application/pdf');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..click();
  html.Url.revokeObjectUrl(url);
}
