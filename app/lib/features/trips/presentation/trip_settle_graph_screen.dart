import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/money/paise.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/widgets.dart';
import '../../groups/domain/group_model.dart';
import '../../settlements/presentation/settle_sheet.dart';
import '../data/trips_repository.dart';

class TripSettleGraphScreen extends ConsumerStatefulWidget {
  final String tripId;

  const TripSettleGraphScreen({super.key, required this.tripId});

  @override
  ConsumerState<TripSettleGraphScreen> createState() => _TripSettleGraphScreenState();
}

class _TripSettleGraphScreenState extends ConsumerState<TripSettleGraphScreen> {
  bool _simplifiedMode = true;
  String? _highlightedUserId;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final graph = ref.watch(
      tripGraphProvider((tripId: widget.tripId, simplified: _simplifiedMode)),
    );
    final asyncTrip = ref.watch(tripDetailProvider(widget.tripId));
    final tripName = asyncTrip.maybeWhen(
      data: (t) => t.name,
      orElse: () => 'Trip',
    );

    // Compute circular positions for nodes
    final nodeCount = graph.nodes.length;
    final nodePositions = <String, Offset>{};
    for (int i = 0; i < nodeCount; i++) {
      final angle = (2 * math.pi * i) / (nodeCount > 0 ? nodeCount : 1) - (math.pi / 2);
      final x = 0.5 + 0.36 * math.cos(angle);
      final y = 0.5 + 0.36 * math.sin(angle);
      nodePositions[graph.nodes[i].userId] = Offset(x, y);
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: colors.textPrimary, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Settlement Graph',
              style: SplitUpTypography.title(color: colors.textPrimary),
            ),
            Text(
              tripName,
              style: SplitUpTypography.caption(color: colors.textMuted),
            ),
          ],
        ),
      ),
      body: AppBackground(
        child: SafeArea(
          child: Column(
            children: [
              // Isolation Notice
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: colors.accentBrass.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colors.accentBrass.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lock_clock_rounded, size: 16, color: colors.accentBrass),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Trip ledger is isolated. Settlements stay strictly within this trip.',
                          style: SplitUpTypography.caption(color: colors.textPrimary).copyWith(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Toggle: Simplified vs Actual
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: SegmentedControl<bool>(
                  values: const [true, false],
                  labels: const ['Simplified Plan (Min. Steps)', 'Actual Debts (Pairwise)'],
                  selected: _simplifiedMode,
                  onSelected: (val) => setState(() {
                    _simplifiedMode = val;
                    _highlightedUserId = null;
                  }),
                ),
              ),

              // Canvas Visualizer
              Expanded(
                flex: 5,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: GlassCard(
                    padding: EdgeInsets.zero,
                    child: graph.links.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle_outline_rounded, size: 56, color: colors.accentReceive),
                                const SizedBox(height: 12),
                                Text(
                                  'All Settled Up!',
                                  style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 18),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'No pending payments on this trip.',
                                  style: SplitUpTypography.body(color: colors.textMuted).copyWith(fontSize: 13),
                                ),
                              ],
                            ),
                          )
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              return GestureDetector(
                                onTapUp: (details) {
                                  // Find closest node
                                  for (final node in graph.nodes) {
                                    final pos = nodePositions[node.userId];
                                    if (pos == null) continue;
                                    final center = Offset(pos.dx * constraints.maxWidth, pos.dy * constraints.maxHeight);
                                    if ((details.localPosition - center).distance < 30) {
                                      setState(() {
                                        _highlightedUserId =
                                            _highlightedUserId == node.userId ? null : node.userId;
                                      });
                                      break;
                                    }
                                  }
                                },
                                child: CustomPaint(
                                  size: Size(constraints.maxWidth, constraints.maxHeight),
                                  painter: _TripGraphPainter(
                                    colors: colors,
                                    nodes: graph.nodes,
                                    links: graph.links,
                                    positions: nodePositions,
                                    highlightedUserId: _highlightedUserId,
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ),

              // Accessible payment list header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Payment List (${graph.links.length} transactions)',
                        style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 15),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _simplifiedMode ? 'Min. Steps' : 'Pairwise',
                      style: SplitUpTypography.caption(color: colors.accentBrass),
                    ),
                  ],
                ),
              ),

              // Transfers list
              Expanded(
                flex: 4,
                child: graph.links.isEmpty
                    ? Center(
                        child: Text(
                          'No debts to settle.',
                          style: SplitUpTypography.caption(color: colors.textMuted),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                        itemCount: graph.links.length,
                        itemBuilder: (context, index) {
                          final l = graph.links[index];
                          final fromNode = graph.nodes.firstWhere(
                            (n) => n.userId == l.fromUserId,
                            orElse: () => GraphNode(userId: l.fromUserId, name: l.fromUserId, netPaise: 0),
                          );
                          final toNode = graph.nodes.firstWhere(
                            (n) => n.userId == l.toUserId,
                            orElse: () => GraphNode(userId: l.toUserId, name: l.toUserId, netPaise: 0),
                          );

                          final isUserPayer = l.fromUserId == 'usr_arhaam';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: isUserPayer
                                  ? colors.accentOwe.withValues(alpha: 0.12)
                                  : colors.surfaceFlat,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isUserPayer
                                    ? colors.accentOwe.withValues(alpha: 0.4)
                                    : colors.divider,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  l.isPending ? Icons.pending_actions_rounded : Icons.arrow_forward_rounded,
                                  color: l.isPending ? colors.accentBrass : colors.accentReceive,
                                  size: 18,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: RichText(
                                    text: TextSpan(
                                      children: [
                                        TextSpan(
                                          text: fromNode.name,
                                          style: SplitUpTypography.label(color: colors.textPrimary).copyWith(fontWeight: FontWeight.w700),
                                        ),
                                        TextSpan(
                                          text: l.isPending ? ' pending to ' : ' pays ',
                                          style: SplitUpTypography.label(color: colors.textMuted),
                                        ),
                                        TextSpan(
                                          text: toNode.name,
                                          style: SplitUpTypography.label(color: colors.textPrimary).copyWith(fontWeight: FontWeight.w700),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                MoneyText(l.amountPaise, variant: MoneyVariant.body, customColor: colors.accentReceive),
                                if (isUserPayer && !l.isPending) ...[
                                  const SizedBox(width: 8),
                                  SettleButton(
                                    amountPaise: l.amountPaise,
                                    compact: true,
                                    onPressed: () {
                                      showModalBottomSheet(
                                        context: context,
                                        isScrollControlled: true,
                                        backgroundColor: Colors.transparent,
                                        builder: (ctx) => SettleSheet(
                                          friendId: toNode.userId,
                                          friendName: toNode.name,
                                          ledgerId: widget.tripId,
                                          amountPaise: l.amountPaise,
                                        ),
                                      );
                                    },
                                  ),
                                ],
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

class _TripGraphPainter extends CustomPainter {
  final SplitUpColors colors;
  final List<GraphNode> nodes;
  final List<GraphLink> links;
  final Map<String, Offset> positions;
  final String? highlightedUserId;

  _TripGraphPainter({
    required this.colors,
    required this.nodes,
    required this.links,
    required this.positions,
    this.highlightedUserId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linkPaint = Paint()
      ..color = colors.accentReceive.withValues(alpha: 0.7)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final pendingPaint = Paint()
      ..color = colors.accentBrass.withValues(alpha: 0.7)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final dimPaint = Paint()
      ..color = colors.divider.withValues(alpha: 0.2)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final nodePaintReceive = Paint()..color = colors.accentReceive;
    final nodePaintOwe = Paint()..color = colors.accentOwe;

    // Draw links
    for (final link in links) {
      final pos1 = positions[link.fromUserId];
      final pos2 = positions[link.toUserId];
      if (pos1 == null || pos2 == null) continue;

      final p1 = Offset(pos1.dx * size.width, pos1.dy * size.height);
      final p2 = Offset(pos2.dx * size.width, pos2.dy * size.height);

      final isHighlighted = highlightedUserId == null ||
          highlightedUserId == link.fromUserId ||
          highlightedUserId == link.toUserId;

      final paint = !isHighlighted
          ? dimPaint
          : (link.isPending ? pendingPaint : linkPaint);

      canvas.drawLine(p1, p2, paint);

      // Midpoint indicator
      final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
      canvas.drawCircle(
        mid,
        4.0,
        Paint()..color = link.isPending ? colors.accentBrass : colors.accentReceive,
      );

      // Amount label at midpoint if highlighted
      if (isHighlighted && links.length <= 6) {
        final tp = TextPainter(
          text: TextSpan(
            text: formatPaise(link.amountPaise),
            style: TextStyle(
              color: colors.accentBrass,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              backgroundColor: colors.surfaceFlat.withValues(alpha: 0.85),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(mid.dx - tp.width / 2, mid.dy - tp.height - 4));
      }
    }

    // Draw nodes
    for (final node in nodes) {
      final pos = positions[node.userId];
      if (pos == null) continue;

      final center = Offset(pos.dx * size.width, pos.dy * size.height);
      final isSelected = highlightedUserId == node.userId;
      final net = node.netPaise;
      final p = net >= 0 ? nodePaintReceive : nodePaintOwe;

      // Outer glow
      canvas.drawCircle(
        center,
        isSelected ? 26 : 22,
        Paint()..color = isSelected ? colors.accentBrass.withValues(alpha: 0.5) : colors.glassBorder,
      );
      // Inner circle
      canvas.drawCircle(center, 18, Paint()..color = colors.surfaceFlatRaised);
      canvas.drawCircle(center, 14, p);

      // Label
      final tp = TextPainter(
        text: TextSpan(
          text: node.name,
          style: TextStyle(
            color: isSelected ? colors.accentBrass : colors.textPrimary,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy + 22));
    }
  }

  @override
  bool shouldRepaint(covariant _TripGraphPainter oldDelegate) => true;
}
