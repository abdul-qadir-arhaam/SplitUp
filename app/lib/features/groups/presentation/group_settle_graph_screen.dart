import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/widgets.dart';

class GroupSettleGraphScreen extends StatefulWidget {
  final String groupId;

  const GroupSettleGraphScreen({super.key, required this.groupId});

  @override
  State<GroupSettleGraphScreen> createState() => _GroupSettleGraphScreenState();
}

class _GroupSettleGraphScreenState extends State<GroupSettleGraphScreen> {
  bool _simplifiedMode = true;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // Mock graph nodes
    final nodes = [
      {'name': 'Arhaam (You)', 'net': -120000, 'x': 0.5, 'y': 0.8},
      {'name': 'Rahul', 'net': 240000, 'x': 0.2, 'y': 0.25},
      {'name': 'Priya', 'net': 150000, 'x': 0.8, 'y': 0.25},
      {'name': 'Amit', 'net': -270000, 'x': 0.5, 'y': 0.1},
    ];

    // Mock payment links
    final links = _simplifiedMode
        ? [
            {'from': 'Arhaam (You)', 'to': 'Rahul', 'amount': 120000},
            {'from': 'Amit', 'to': 'Rahul', 'amount': 120000},
            {'from': 'Amit', 'to': 'Priya', 'amount': 150000},
          ]
        : [
            {'from': 'Arhaam (You)', 'to': 'Rahul', 'amount': 80000},
            {'from': 'Arhaam (You)', 'to': 'Priya', 'amount': 40000},
            {'from': 'Amit', 'to': 'Rahul', 'amount': 160000},
            {'from': 'Amit', 'to': 'Priya', 'amount': 110000},
          ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: colors.textPrimary, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Settlement Graph',
          style: SplitUpTypography.title(color: colors.textPrimary),
        ),
      ),
      body: AppBackground(
        child: SafeArea(
          child: Column(
            children: [
              // Toggle: Simplified vs Actual
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: SegmentedControl<bool>(
                  values: const [true, false],
                  labels: const ['Simplified Plan (Min. Steps)', 'Actual Debts (Pairwise)'],
                  selected: _simplifiedMode,
                  onSelected: (val) => setState(() => _simplifiedMode = val),
                ),
              ),

              // Canvas Visualizer
              Expanded(
                flex: 5,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: GlassCard(
                    padding: EdgeInsets.zero,
                    child: CustomPaint(
                      painter: _GraphPainter(
                        colors: colors,
                        nodes: nodes,
                        links: links,
                      ),
                      child: Container(),
                    ),
                  ),
                ),
              ),

              // Accessible payment list
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Payment List (${links.length} transactions)',
                      style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 15),
                    ),
                    Text(
                      _simplifiedMode ? 'Optimized' : 'Pairwise',
                      style: SplitUpTypography.caption(color: colors.accentBrass),
                    ),
                  ],
                ),
              ),

              Expanded(
                flex: 4,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  itemCount: links.length,
                  itemBuilder: (context, index) {
                    final l = links[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: colors.surfaceFlat,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: colors.divider),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.arrow_forward_rounded, color: colors.accentReceive, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: l['from'] as String,
                                    style: SplitUpTypography.label(color: colors.textPrimary).copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  TextSpan(
                                    text: ' pays ',
                                    style: SplitUpTypography.label(color: colors.textMuted),
                                  ),
                                  TextSpan(
                                    text: l['to'] as String,
                                    style: SplitUpTypography.label(color: colors.textPrimary).copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          MoneyText(l['amount'] as int, variant: MoneyVariant.body, customColor: colors.accentReceive),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  final SplitUpColors colors;
  final List<Map<String, dynamic>> nodes;
  final List<Map<String, dynamic>> links;

  _GraphPainter({
    required this.colors,
    required this.nodes,
    required this.links,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linkPaint = Paint()
      ..color = colors.accentReceive.withValues(alpha: 0.7)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final nodePaintReceive = Paint()..color = colors.accentReceive;
    final nodePaintOwe = Paint()..color = colors.accentOwe;

    // Draw links
    for (final link in links) {
      final fromNode = nodes.firstWhere((n) => n['name'] == link['from']);
      final toNode = nodes.firstWhere((n) => n['name'] == link['to']);

      final p1 = Offset((fromNode['x'] as double) * size.width, (fromNode['y'] as double) * size.height);
      final p2 = Offset((toNode['x'] as double) * size.width, (toNode['y'] as double) * size.height);

      canvas.drawLine(p1, p2, linkPaint);

      // Arrow head at midpoint
      final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
      canvas.drawCircle(mid, 3.5, Paint()..color = colors.accentBrass);
    }

    // Draw nodes
    for (final node in nodes) {
      final center = Offset((node['x'] as double) * size.width, (node['y'] as double) * size.height);
      final net = node['net'] as int;
      final p = net >= 0 ? nodePaintReceive : nodePaintOwe;

      // Outer glow / border
      canvas.drawCircle(center, 22, Paint()..color = colors.glassBorder);
      // Inner circle
      canvas.drawCircle(center, 18, Paint()..color = colors.surfaceFlatRaised);
      canvas.drawCircle(center, 14, p);

      // Label
      final tp = TextPainter(
        text: TextSpan(
          text: node['name'] as String,
          style: TextStyle(color: colors.textPrimary, fontSize: 11, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy + 24));
    }
  }

  @override
  bool shouldRepaint(covariant _GraphPainter oldDelegate) => true;
}
