import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'pdf_download_stub.dart' if (dart.library.html) 'pdf_download_web.dart'
    as pdf_download;

// Define DietFoodItem class here since it's used in this file
class DietFoodItem {
  final String foodId;
  final String name;
  final String unit;
  final double baseQuantity;
  final double baseCalories, baseProtein, baseCarbs, baseFats;
  double quantity;

  DietFoodItem({
    required this.foodId,
    required this.name,
    required this.unit,
    required this.baseQuantity,
    required this.baseCalories,
    required this.baseProtein,
    required this.baseCarbs,
    required this.baseFats,
    required this.quantity,
  });

  double get factor => baseQuantity == 0 ? 0 : quantity / baseQuantity;
  double get calories => baseCalories * factor;
  double get protein => baseProtein * factor;
  double get carbs => baseCarbs * factor;
  double get fats => baseFats * factor;
}

const kDietSections = ['Breakfast', 'Lunch', 'Dinner', 'Snacks'];

// Column widths
const double _wQty = 36;
const double _wCal = 34;
const double _wMacro = 32;

class DietPreviewPage extends StatefulWidget {
  final Map<String, dynamic> member;
  final String dietName;
  final String dietType;
  final double calorieTarget;
  final double proteinTarget;
  final double carbsTarget;
  final double fatsTarget;
  final Map<String, List<DietFoodItem>> sections;
  final DateTime? lastUpdated;
  final VoidCallback? onSave;
  final VoidCallback? onQuit;
  final String? coachNameOverride;

  const DietPreviewPage({
    super.key,
    required this.member,
    required this.dietName,
    required this.dietType,
    required this.calorieTarget,
    required this.proteinTarget,
    required this.carbsTarget,
    required this.fatsTarget,
    required this.sections,
    this.lastUpdated,
    this.onSave,
    this.onQuit,
    this.coachNameOverride,
  });

  @override
  State<DietPreviewPage> createState() => _DietPreviewPageState();
}

class _DietPreviewPageState extends State<DietPreviewPage> {
  bool isGeneratingPdf = false;
  String lastSaveDate = '';

  @override
  void initState() {
    super.initState();
    _loadLastSaveDate();
  }

  Future<void> _loadLastSaveDate() async {
    if (widget.lastUpdated != null) {
      setState(() {
        lastSaveDate = _formatDateTime(widget.lastUpdated!);
      });
      return;
    }

    try {
      final slot = widget.dietType.toLowerCase() == 'veg' ? 1 : 2;
      final response = await Supabase.instance.client
          .from('diets')
          .select('updated_at')
          .eq('member_id', widget.member['id'])
          .eq('slot', slot)
          .maybeSingle();

      if (response != null && response['updated_at'] != null) {
        final DateTime dateTime = DateTime.parse(response['updated_at']);
        setState(() {
          lastSaveDate = _formatDateTime(dateTime);
        });
      } else {
        setState(() {
          lastSaveDate = 'Not saved yet';
        });
      }
    } catch (e) {
      setState(() {
        lastSaveDate = 'Not saved yet';
      });
    }
  }

  String _formatDateTime(DateTime dateTime) {
    final String day = dateTime.day.toString().padLeft(2, '0');
    final String month = dateTime.month.toString().padLeft(2, '0');
    final String year = dateTime.year.toString();
    final String hour = dateTime.hour.toString().padLeft(2, '0');
    final String minute = dateTime.minute.toString().padLeft(2, '0');
    return '$day-$month-$year $hour:$minute';
  }

  Map<String, double> get totals {
    double cal = 0, pro = 0, carb = 0, fat = 0;
    for (final list in widget.sections.values) {
      for (final item in list) {
        cal += item.calories;
        pro += item.protein;
        carb += item.carbs;
        fat += item.fats;
      }
    }
    return {'calories': cal, 'protein': pro, 'carbs': carb, 'fats': fat};
  }

  String get memberName => widget.member['full_name'] ?? 'Member';
  String get coachName =>
      widget.coachNameOverride ??
      Supabase.instance.client.auth.currentUser?.email ??
      'Coach';

  // Calculate dynamic font size based on content length
  double _getDynamicFontSize(int totalItems) {
    if (totalItems <= 10) return 10.0;
    if (totalItems <= 20) return 9.0;
    if (totalItems <= 35) return 8.0;
    return 7.5;
  }

  Future<void> downloadPdf() async {
    setState(() => isGeneratingPdf = true);
    try {
      final bytes = await _buildPdfBytes();
      final safeName = memberName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final fileName = '${safeName}_${widget.dietType}_diet.pdf';

      if (kIsWeb) {
        pdf_download.downloadPdfBytes(bytes, fileName);
      } else {
        await Printing.sharePdf(bytes: bytes, filename: fileName);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('PDF failed: $e')));
      }
    } finally {
      if (mounted) setState(() => isGeneratingPdf = false);
    }
  }

  Future<Uint8List> _buildPdfBytes() async {
    final doc = pw.Document();
    final t = totals;

    // Count total items for dynamic font sizing
    int totalItems = 0;
    for (final section in kDietSections) {
      totalItems += (widget.sections[section] ?? []).length;
    }
    final dynamicFontSize = _getDynamicFontSize(totalItems);

    final headerStyle =
        pw.TextStyle(fontSize: dynamicFontSize, fontWeight: pw.FontWeight.bold);
    final cellStyle = pw.TextStyle(fontSize: dynamicFontSize);
    const pad = pw.EdgeInsets.symmetric(vertical: 4, horizontal: 3);

    // Column widths for PDF
    final columnWidths = {
      0: const pw.FixedColumnWidth(140),
      1: const pw.FixedColumnWidth(50),
      2: const pw.FixedColumnWidth(50),
      3: const pw.FixedColumnWidth(50),
      4: const pw.FixedColumnWidth(50),
      5: const pw.FixedColumnWidth(50),
    };

    final List<pw.TableRow> allRows = [];

    // Header row
    allRows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          pw.Padding(
            padding: pad,
            child: pw.Text('Food',
                style: headerStyle, textAlign: pw.TextAlign.left),
          ),
          pw.Padding(
            padding: pad,
            child: pw.Text('Qty',
                style: headerStyle, textAlign: pw.TextAlign.right),
          ),
          pw.Padding(
            padding: pad,
            child: pw.Text('Cal',
                style: headerStyle, textAlign: pw.TextAlign.right),
          ),
          pw.Padding(
            padding: pad,
            child: pw.Text('Prot',
                style: headerStyle, textAlign: pw.TextAlign.right),
          ),
          pw.Padding(
            padding: pad,
            child: pw.Text('Carb',
                style: headerStyle, textAlign: pw.TextAlign.right),
          ),
          pw.Padding(
            padding: pad,
            child: pw.Text('Fat',
                style: headerStyle, textAlign: pw.TextAlign.right),
          ),
        ],
      ),
    );

    // Build all sections
    for (final section in kDietSections) {
      final items = widget.sections[section] ?? [];
      if (items.isEmpty) continue;

      // Section header
      allRows.add(
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
          children: [
            pw.Padding(
              padding:
                  const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 3),
              child: pw.Text(section,
                  style: pw.TextStyle(
                      fontSize: dynamicFontSize + 1,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.black)),
            ),
            pw.SizedBox(),
            pw.SizedBox(),
            pw.SizedBox(),
            pw.SizedBox(),
            pw.SizedBox(),
          ],
        ),
      );

      // Food items
      for (final item in items) {
        String qtyText =
            '${item.quantity.toStringAsFixed(item.quantity.truncateToDouble() == item.quantity ? 0 : 1)}${item.unit}';
        allRows.add(
          pw.TableRow(
            children: [
              pw.Padding(
                padding: pad,
                child: pw.Text(item.name, style: cellStyle),
              ),
              pw.Padding(
                padding: pad,
                child: pw.Text(qtyText,
                    style: cellStyle, textAlign: pw.TextAlign.right),
              ),
              pw.Padding(
                padding: pad,
                child: pw.Text(item.calories.toStringAsFixed(1),
                    style: cellStyle, textAlign: pw.TextAlign.right),
              ),
              pw.Padding(
                padding: pad,
                child: pw.Text('${item.protein.toStringAsFixed(1)}g',
                    style: cellStyle, textAlign: pw.TextAlign.right),
              ),
              pw.Padding(
                padding: pad,
                child: pw.Text('${item.carbs.toStringAsFixed(1)}g',
                    style: cellStyle, textAlign: pw.TextAlign.right),
              ),
              pw.Padding(
                padding: pad,
                child: pw.Text('${item.fats.toStringAsFixed(1)}g',
                    style: cellStyle, textAlign: pw.TextAlign.right),
              ),
            ],
          ),
        );
      }
    }

    // Total row at the bottom
    allRows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          pw.Padding(
            padding: pad,
            child: pw.Text('Total',
                style: headerStyle, textAlign: pw.TextAlign.left),
          ),
          pw.Padding(
            padding: pad,
            child: pw.Text('', style: headerStyle),
          ),
          pw.Padding(
            padding: pad,
            child: pw.Text(t['calories']!.toStringAsFixed(1),
                style: headerStyle, textAlign: pw.TextAlign.right),
          ),
          pw.Padding(
            padding: pad,
            child: pw.Text('${t['protein']!.toStringAsFixed(1)}g',
                style: headerStyle, textAlign: pw.TextAlign.right),
          ),
          pw.Padding(
            padding: pad,
            child: pw.Text('${t['carbs']!.toStringAsFixed(1)}g',
                style: headerStyle, textAlign: pw.TextAlign.right),
          ),
          pw.Padding(
            padding: pad,
            child: pw.Text('${t['fats']!.toStringAsFixed(1)}g',
                style: headerStyle, textAlign: pw.TextAlign.right),
          ),
        ],
      ),
    );

    // Check if we have data to show watermark
    bool hasData = false;
    for (final section in kDietSections) {
      if ((widget.sections[section] ?? []).isNotEmpty) {
        hasData = true;
        break;
      }
    }

    pw.Widget tableWidget = pw.Table(
      columnWidths: columnWidths,
      border: pw.TableBorder.symmetric(
          inside: const pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
      children: allRows,
    );

    final now = DateTime.now();
    final currentDate = _formatDateTime(now);

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          buildBackground: (context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Container(color: PdfColors.white),
          ),
        ),
        build: (context) => [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('$memberName - ${widget.dietType}',
                  style: pw.TextStyle(
                      fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text(
                'Weight: ${widget.member['weight_kg'] ?? '-'} kg   Height: ${widget.member['height_cm'] ?? '-'} cms',
                style: const pw.TextStyle(fontSize: 10),
              ),
              pw.Text('Coach: $coachName',
                  style: const pw.TextStyle(fontSize: 10)),
              pw.Text('Date: $currentDate',
                  style: const pw.TextStyle(fontSize: 10)),
              pw.SizedBox(height: 8),
              pw.Container(
                child: pw.Stack(
                  children: [
                    tableWidget,
                    if (hasData)
                      pw.Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: pw.Center(
                          child: pw.Transform.rotate(
                            angle: -0.785,
                            child: pw.Opacity(
                              opacity: 0.05,
                              child: pw.Text(
                                'THE CONQUER CLUB',
                                style: pw.TextStyle(
                                  fontSize: 30,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.grey,
                                  letterSpacing: 4,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return doc.save();
  }

  @override
  Widget build(BuildContext context) {
    final t = totals;

    // Count total items for dynamic font sizing
    int totalItems = 0;
    for (final section in kDietSections) {
      totalItems += (widget.sections[section] ?? []).length;
    }
    final dynamicFontSize = _getDynamicFontSize(totalItems);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Diet Preview',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        actions: [
          isGeneratingPdf
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : IconButton(
                  icon: const Icon(Icons.download, color: Colors.black),
                  onPressed: downloadPdf,
                ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$memberName - ${widget.dietType}',
                    style: const TextStyle(
                        color: Colors.black,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 12,
                  children: [
                    _infoLabel(
                        'Weight: ', '${widget.member['weight_kg'] ?? '-'} kg'),
                    _infoLabel(
                        'Height: ', '${widget.member['height_cm'] ?? '-'} cms'),
                  ],
                ),
                const SizedBox(height: 2),
                _infoLabel('Coach: ', coachName),
                const SizedBox(height: 2),
                _infoLabel('Date: ', lastSaveDate),
              ],
            ),
          ),
          const Divider(color: Colors.black, thickness: 1, height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: _buildTableWithWatermark(t, dynamicFontSize),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoLabel(String label, String value) {
    return RichText(
      text: TextSpan(children: [
        TextSpan(
            text: label,
            style: const TextStyle(color: Colors.black87, fontSize: 13)),
        TextSpan(
            text: value,
            style: const TextStyle(
                color: Colors.black,
                fontSize: 13,
                fontWeight: FontWeight.bold)),
      ]),
    );
  }

  String _compactFoodName(String name) => name.replaceAll('/ ', '/');

  Widget _foodCell(String text, {bool bold = false, double? fontSize}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
        child: Text(
          text,
          overflow: TextOverflow.visible,
          softWrap: true,
          style: TextStyle(
              color: Colors.black,
              fontSize: fontSize ?? 9.5,
              height: 1.15,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal),
        ),
      ),
    );
  }

  Widget _numCell(String text, double width,
      {bool bold = false, double? fontSize}) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 1),
        child: Text(
          text,
          textAlign: TextAlign.right,
          overflow: TextOverflow.visible,
          softWrap: false,
          maxLines: 1,
          style: TextStyle(
              color: Colors.black,
              fontSize: fontSize ?? 9.5,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal),
        ),
      ),
    );
  }

  Widget _verticalDivider() {
    return Container(
      width: 1,
      height: double.infinity,
      color: Colors.grey.shade300,
    );
  }

  Widget _buildTableWithWatermark(Map<String, double> t, double fontSize) {
    final List<Widget> tableRows = [];

    bool hasData = false;
    for (final section in kDietSections) {
      if ((widget.sections[section] ?? []).isNotEmpty) {
        hasData = true;
        break;
      }
    }

    Widget row({required Color color, required Widget child}) {
      return SizedBox(
        width: double.infinity,
        child: ColoredBox(color: color, child: child),
      );
    }

    // Header row
    tableRows.add(
      row(
        color: Colors.white,
        child: Row(children: [
          _foodCell('Food', bold: true, fontSize: fontSize),
          _verticalDivider(),
          _numCell('Qty', _wQty, bold: true, fontSize: fontSize),
          _verticalDivider(),
          _numCell('Cal', _wCal, bold: true, fontSize: fontSize),
          _verticalDivider(),
          _numCell('Prot', _wMacro, bold: true, fontSize: fontSize),
          _verticalDivider(),
          _numCell('Carb', _wMacro, bold: true, fontSize: fontSize),
          _verticalDivider(),
          _numCell('Fat', _wMacro, bold: true, fontSize: fontSize),
        ]),
      ),
    );
    tableRows.add(const Divider(color: Colors.grey, height: 1));

    // Build all sections
    for (final section in kDietSections) {
      final items = widget.sections[section] ?? [];
      if (items.isEmpty) continue;

      tableRows.add(
        row(
          color: Colors.white,
          child: Row(children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Text(section,
                    style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: fontSize + 1.5)),
              ),
            ),
            _verticalDivider(),
            SizedBox(width: _wQty, child: const SizedBox()),
            _verticalDivider(),
            SizedBox(width: _wCal, child: const SizedBox()),
            _verticalDivider(),
            SizedBox(width: _wMacro, child: const SizedBox()),
            _verticalDivider(),
            SizedBox(width: _wMacro, child: const SizedBox()),
            _verticalDivider(),
            SizedBox(width: _wMacro, child: const SizedBox()),
          ]),
        ),
      );

      for (final item in items) {
        tableRows.add(
          row(
            color: Colors.white,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _foodCell(_compactFoodName(item.name), fontSize: fontSize),
                _verticalDivider(),
                _numCell(
                    '${item.quantity.toStringAsFixed(item.quantity.truncateToDouble() == item.quantity ? 0 : 1)}${item.unit}',
                    _wQty,
                    fontSize: fontSize),
                _verticalDivider(),
                _numCell(item.calories.toStringAsFixed(1), _wCal,
                    fontSize: fontSize),
                _verticalDivider(),
                _numCell('${item.protein.toStringAsFixed(1)}g', _wMacro,
                    fontSize: fontSize),
                _verticalDivider(),
                _numCell('${item.carbs.toStringAsFixed(1)}g', _wMacro,
                    fontSize: fontSize),
                _verticalDivider(),
                _numCell('${item.fats.toStringAsFixed(1)}g', _wMacro,
                    fontSize: fontSize),
              ],
            ),
          ),
        );
        tableRows.add(const Divider(color: Color(0xFFEEEEEE), height: 1));
      }
    }

    // Total row at the bottom
    tableRows.add(
      row(
        color: Colors.white,
        child: Row(children: [
          _foodCell('Total', bold: true, fontSize: fontSize),
          _verticalDivider(),
          _numCell('', _wQty, fontSize: fontSize),
          _verticalDivider(),
          _numCell(t['calories']!.toStringAsFixed(1), _wCal,
              bold: true, fontSize: fontSize),
          _verticalDivider(),
          _numCell('${t['protein']!.toStringAsFixed(1)}g', _wMacro,
              bold: true, fontSize: fontSize),
          _verticalDivider(),
          _numCell('${t['carbs']!.toStringAsFixed(1)}g', _wMacro,
              bold: true, fontSize: fontSize),
          _verticalDivider(),
          _numCell('${t['fats']!.toStringAsFixed(1)}g', _wMacro,
              bold: true, fontSize: fontSize),
        ]),
      ),
    );

    return SizedBox(
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: tableRows,
          ),
          if (hasData)
            Positioned.fill(
              child: IgnorePointer(
                ignoring: true,
                child: Center(
                  child: Opacity(
                    opacity: 0.05,
                    child: Transform.rotate(
                      angle: -0.785,
                      child: Text(
                        'THE CONQUER CLUB',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: Colors.grey,
                          letterSpacing: 4,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
