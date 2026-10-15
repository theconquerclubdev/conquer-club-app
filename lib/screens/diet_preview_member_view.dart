part of 'diet_preview_page.dart';

// ============================================================
// Member-facing diet view (only used when memberStyle: true).
// Pretty on-screen UI. The PDF download is the SAME function the
// coach screen uses (downloadPdf), so the PDF stays exactly as is.
// ============================================================

const Color _kProtein = Color(0xFF4FC3F7);
const Color _kCarbs = Color(0xFFFFB74D);
const Color _kFats = Color(0xFFBA68C8);

const Map<String, IconData> _kMealIcons = {
  'Breakfast': Icons.free_breakfast_rounded,
  'Lunch': Icons.lunch_dining_rounded,
  'Snacks': Icons.cookie_rounded,
  'Dinner': Icons.dinner_dining_rounded,
};

BoxDecoration _card3d({double radius = 20}) => BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF2A2A2A), Color(0xFF151515)],
      ),
      border: Border.all(color: Colors.white.withOpacity(0.07)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.55),
          blurRadius: 18,
          offset: const Offset(0, 10),
        ),
        BoxShadow(
          color: Colors.white.withOpacity(0.04),
          blurRadius: 2,
          offset: const Offset(0, -1),
        ),
      ],
    );

String _qtyText(DietFoodItem it) =>
    '${it.quantity.toStringAsFixed(it.quantity.truncateToDouble() == it.quantity ? 0 : 1)}${it.unit}';

class MemberDietView extends StatelessWidget {
  final String memberName;
  final String dietType;
  final String coachName;
  final String lastSaveDate;
  final double calorieTarget;
  final double proteinTarget;
  final double carbsTarget;
  final double fatsTarget;
  final Map<String, List<DietFoodItem>> sections;
  final Map<String, double> totals;
  final bool isGeneratingPdf;
  final VoidCallback onDownload;

  const MemberDietView({
    super.key,
    required this.memberName,
    required this.dietType,
    required this.coachName,
    required this.lastSaveDate,
    required this.calorieTarget,
    required this.proteinTarget,
    required this.carbsTarget,
    required this.fatsTarget,
    required this.sections,
    required this.totals,
    required this.isGeneratingPdf,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final cal = totals['calories'] ?? 0;
    final pro = totals['protein'] ?? 0;
    final carb = totals['carbs'] ?? 0;
    final fat = totals['fats'] ?? 0;

    // Calories that come from each macro (protein 4, carbs 4, fats 9 kcal/g)
    final proKcal = pro * 4;
    final carbKcal = carb * 4;
    final fatKcal = fat * 9;
    final macroKcal = proKcal + carbKcal + fatKcal;
    double share(double k) => macroKcal > 0 ? k / macroKcal * 100 : 0;

    final meals =
        kDietSections.where((s) => (sections[s] ?? []).isNotEmpty).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'My Diet Plan',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          isGeneratingPdf
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.gold),
                  ),
                )
              : IconButton(
                  icon:
                      const Icon(Icons.download_rounded, color: AppColors.gold),
                  onPressed: onDownload,
                ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
            children: [
              _header(),
              const SizedBox(height: 16),
              _HeroCalorieCard(planned: cal, target: calorieTarget),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _MacroTile(
                      label: 'Protein',
                      planned: pro,
                      target: proteinTarget,
                      color: _kProtein,
                      sharePct: share(proKcal),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MacroTile(
                      label: 'Carbs',
                      planned: carb,
                      target: carbsTarget,
                      color: _kCarbs,
                      sharePct: share(carbKcal),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MacroTile(
                      label: 'Fats',
                      planned: fat,
                      target: fatsTarget,
                      color: _kFats,
                      sharePct: share(fatKcal),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _splitBar(proKcal, carbKcal, fatKcal, share),
              const SizedBox(height: 22),
              const Text(
                'YOUR MEALS',
                style: TextStyle(
                  color: AppColors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.6,
                ),
              ),
              const SizedBox(height: 10),
              if (meals.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: _card3d(),
                  child: const Center(
                    child: Text(
                      'No foods added to this plan yet.',
                      style: TextStyle(color: AppColors.grey),
                    ),
                  ),
                ),
              for (final s in meals) ...[
                _MealCard(
                  name: s,
                  items: sections[s] ?? [],
                  dayCalories: cal,
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _header() {
    final isVeg = dietType.toLowerCase() == 'veg';
    final initial =
        memberName.trim().isEmpty ? '?' : memberName.trim()[0].toUpperCase();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _card3d(),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFD54F), Color(0xFFC79100)],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.gold.withOpacity(0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  memberName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Coach: $coachName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.grey, fontSize: 12),
                ),
                if (lastSaveDate.isNotEmpty)
                  Text(
                    'Updated: $lastSaveDate',
                    style: const TextStyle(color: AppColors.grey, fontSize: 12),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: (isVeg ? Colors.green : Colors.red).withOpacity(0.16),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: (isVeg ? Colors.green : Colors.red).withOpacity(0.5),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle,
                    size: 8, color: isVeg ? Colors.green : Colors.red),
                const SizedBox(width: 6),
                Text(
                  dietType,
                  style: TextStyle(
                    color: isVeg ? Colors.greenAccent : Colors.redAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _splitBar(double proKcal, double carbKcal, double fatKcal,
      double Function(double) share) {
    final total = proKcal + carbKcal + fatKcal;
    int flexOf(double k) => total > 0 ? (k / total * 1000).round() : 0;
    final fp = flexOf(proKcal);
    final fc = flexOf(carbKcal);
    final ff = flexOf(fatKcal);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _card3d(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'WHERE YOUR CALORIES COME FROM',
            style: TextStyle(
              color: AppColors.grey,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 14,
              child: total <= 0
                  ? Container(color: Colors.white12)
                  : Row(
                      children: [
                        if (fp > 0)
                          Expanded(
                              flex: fp, child: Container(color: _kProtein)),
                        if (fc > 0)
                          Expanded(flex: fc, child: Container(color: _kCarbs)),
                        if (ff > 0)
                          Expanded(flex: ff, child: Container(color: _kFats)),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _legend('Protein', share(proKcal), _kProtein),
              _legend('Carbs', share(carbKcal), _kCarbs),
              _legend('Fats', share(fatKcal), _kFats),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legend(String label, double pct, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          '$label ${pct.round()}%',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}

// ---------- ring painter ----------
class _RingPainter extends CustomPainter {
  final double progress; // 0..1 (values above 1 draw a full ring)
  final Color color;
  final double stroke;

  _RingPainter({
    required this.progress,
    required this.color,
    required this.stroke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (size.shortestSide - stroke) / 2;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = Colors.white.withOpacity(0.08);
    canvas.drawCircle(center, radius, track);

    final p = progress.clamp(0.0, 1.0).toDouble();
    if (p <= 0) return;

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: [color.withOpacity(0.55), color],
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * p,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.color != color || old.stroke != stroke;
}

// ---------- hero 3D calorie card ----------
class _HeroCalorieCard extends StatefulWidget {
  final double planned;
  final double target;
  const _HeroCalorieCard({required this.planned, required this.target});

  @override
  State<_HeroCalorieCard> createState() => _HeroCalorieCardState();
}

class _HeroCalorieCardState extends State<_HeroCalorieCard> {
  double _tilt = 0;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final planned = widget.planned;
    final target = widget.target;
    final progress = target > 0 ? planned / target : 0.0;
    final over = progress > 1.05;
    final ringColor = over ? const Color(0xFFFF7043) : AppColors.gold;
    final pct = (progress * 100).round();

    return GestureDetector(
      // Horizontal drag only, so normal up/down scrolling is never blocked.
      onHorizontalDragUpdate: (d) => setState(() {
        _dragging = true;
        _tilt = (_tilt + d.delta.dx * 0.004).clamp(-0.3, 0.3).toDouble();
      }),
      onHorizontalDragEnd: (_) => setState(() {
        _dragging = false;
        _tilt = 0;
      }),
      onHorizontalDragCancel: () => setState(() {
        _dragging = false;
        _tilt = 0;
      }),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: _tilt, end: _tilt),
        duration: _dragging ? Duration.zero : const Duration(milliseconds: 450),
        curve: Curves.easeOutBack,
        builder: (context, t, child) => Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateX(-0.06)
            ..rotateY(t),
          child: child,
        ),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF33291A), Color(0xFF141414)],
            ),
            border: Border.all(color: AppColors.gold.withOpacity(0.28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.6),
                blurRadius: 22,
                offset: const Offset(0, 14),
              ),
              BoxShadow(
                color: AppColors.gold.withOpacity(0.16),
                blurRadius: 34,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Row(
            children: [
              SizedBox(
                width: 140,
                height: 140,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: progress.toDouble()),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) => CustomPaint(
                    painter:
                        _RingPainter(progress: v, color: ringColor, stroke: 14),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            planned.round().toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const Text(
                            'kcal / day',
                            style:
                                TextStyle(color: AppColors.grey, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'DAILY CALORIES',
                      style: TextStyle(
                        color: AppColors.grey,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      target > 0 ? '${target.round()} kcal' : 'No target set',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'your target',
                      style: TextStyle(color: AppColors.grey, fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    if (target > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: ringColor.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          over ? '$pct% - above target' : '$pct% of target',
                          style: TextStyle(
                            color: ringColor,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- macro tile ----------
class _MacroTile extends StatelessWidget {
  final String label;
  final double planned;
  final double target;
  final Color color;
  final double sharePct;

  const _MacroTile({
    required this.label,
    required this.planned,
    required this.target,
    required this.color,
    required this.sharePct,
  });

  @override
  Widget build(BuildContext context) {
    final progress = target > 0 ? planned / target : 0.0;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: _card3d(radius: 18),
      child: Column(
        children: [
          SizedBox(
            width: 70,
            height: 70,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: progress.toDouble()),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => CustomPaint(
                painter: _RingPainter(progress: v, color: color, stroke: 8),
                child: Center(
                  child: Text(
                    '${planned.round()}g',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            target > 0 ? 'of ${target.round()}g' : 'no target',
            style: const TextStyle(color: AppColors.grey, fontSize: 11),
          ),
          const SizedBox(height: 6),
          Text(
            '${sharePct.round()}% kcal',
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ---------- meal card ----------
class _MealCard extends StatelessWidget {
  final String name;
  final List<DietFoodItem> items;
  final double dayCalories;

  const _MealCard({
    required this.name,
    required this.items,
    required this.dayCalories,
  });

  Widget _chip(String letter, double grams, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$letter ${grams.toStringAsFixed(1)}g',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double cal = 0, pro = 0, carb = 0, fat = 0;
    for (final it in items) {
      cal += it.calories;
      pro += it.protein;
      carb += it.carbs;
      fat += it.fats;
    }
    final dayPct = dayCalories > 0 ? (cal / dayCalories * 100).round() : 0;

    return Container(
      decoration: _card3d(),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          iconColor: AppColors.gold,
          collapsedIconColor: AppColors.grey,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.gold.withOpacity(0.14),
            ),
            child: Icon(_kMealIcons[name] ?? Icons.restaurant_rounded,
                color: AppColors.gold, size: 22),
          ),
          title: Text(
            name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Text(
            '${cal.round()} kcal  |  $dayPct% of day  |  ${items.length} items',
            style: const TextStyle(color: AppColors.grey, fontSize: 12),
          ),
          children: [
            for (int i = 0; i < items.length; i++) ...[
              if (i > 0) const Divider(color: Colors.white10, height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            items[i].name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _qtyText(items[i]),
                          style: const TextStyle(
                              color: AppColors.grey, fontSize: 12),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${items[i].calories.round()} kcal',
                          style: const TextStyle(
                            color: AppColors.gold,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _chip('P', items[i].protein, _kProtein),
                        _chip('C', items[i].carbs, _kCarbs),
                        _chip('F', items[i].fats, _kFats),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Meal total',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  _chip('P', pro, _kProtein),
                  _chip('C', carb, _kCarbs),
                  _chip('F', fat, _kFats),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- 3D download button ----------
class _DownloadButton extends StatelessWidget {
  final bool busy;
  final VoidCallback onTap;
  const _DownloadButton({required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: Container(
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFD54F), Color(0xFFE0A100)],
          ),
          boxShadow: [
            const BoxShadow(
              color: Color(0xFF8A6200),
              offset: Offset(0, 5),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.55),
              blurRadius: 18,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Colors.black),
              )
            : const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.picture_as_pdf_rounded, color: Colors.black),
                  SizedBox(width: 10),
                  Text(
                    'DOWNLOAD PDF',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
