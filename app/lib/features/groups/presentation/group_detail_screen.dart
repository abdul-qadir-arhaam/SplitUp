import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/mock/mock_data.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/widgets.dart';

class GroupDetailScreen extends StatefulWidget {
  final String groupId;

  const GroupDetailScreen({super.key, required this.groupId});

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final group = MockDataRepository.groups.firstWhere(
      (g) => g.id == widget.groupId,
      orElse: () => MockDataRepository.groups.first,
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: colors.textPrimary, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text(
          group.name,
          style: SplitUpTypography.title(color: colors.textPrimary),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.hub_outlined, color: colors.accentBrass, size: 24),
            tooltip: 'Settle Graph',
            onPressed: () => context.push('/groups/${group.id}/graph'),
          ),
          IconButton(
            icon: Icon(Icons.more_vert_rounded, color: colors.textPrimary),
            onPressed: () {},
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: colors.accentReceive,
          labelColor: colors.textPrimary,
          unselectedLabelColor: colors.textMuted,
          labelStyle: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 14),
          tabs: const [
            Tab(text: 'Expenses'),
            Tab(text: 'Dashboard'),
            Tab(text: 'Settle'),
          ],
        ),
      ),
      body: AppBackground(
        child: SafeArea(
          bottom: false,
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildExpensesTab(colors, group),
              _buildDashboardTab(colors, group),
              _buildSettleTab(colors, group),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: colors.accentReceive,
        foregroundColor: Colors.white,
        onPressed: () => context.push('/add-expense'),
        child: const Icon(Icons.add_rounded, size: 28),
      ),
    );
  }

  Widget _buildExpensesTab(SplitUpColors colors, MockGroup group) {
    final expenses = MockDataRepository.expenses;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      children: [
        GlassCard(
          strong: true,
          padding: const EdgeInsets.all(18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'YOUR GROUP BALANCE',
                    style: SplitUpTypography.caption(color: colors.textMuted).copyWith(
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  MoneyText(group.myNetPaise, variant: MoneyVariant.title, showSign: true),
                ],
              ),
              if (group.myNetPaise < 0)
                SettleButton(
                  amountPaise: group.myNetPaise.abs(),
                  onPressed: () => context.push('/groups/${group.id}/graph'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Group Activity',
          style: SplitUpTypography.title(color: colors.textPrimary),
        ),
        const SizedBox(height: 12),
        ...expenses.map((exp) {
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surfaceFlat,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.divider),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.surfaceFlatRaised,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.restaurant_rounded, size: 20, color: colors.accentBrass),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(exp.title, style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 15)),
                      const SizedBox(height: 2),
                      Text('Paid by ${exp.paidBy.displayName}', style: SplitUpTypography.caption(color: colors.textMuted)),
                    ],
                  ),
                ),
                MoneyText(exp.totalPaise, variant: MoneyVariant.body, colored: false),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildDashboardTab(SplitUpColors colors, MockGroup group) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      children: [
        // Category Donut Chart
        GlassCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Spending by Category',
                style: SplitUpTypography.title(color: colors.textPrimary),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 160,
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 3,
                    centerSpaceRadius: 40,
                    sections: [
                      PieChartSectionData(
                        value: 45,
                        color: colors.accentReceive,
                        title: 'Food (45%)',
                        titleStyle: SplitUpTypography.caption(color: Colors.white),
                        radius: 36,
                      ),
                      PieChartSectionData(
                        value: 30,
                        color: colors.accentBrass,
                        title: 'Travel (30%)',
                        titleStyle: SplitUpTypography.caption(color: Colors.white),
                        radius: 36,
                      ),
                      PieChartSectionData(
                        value: 25,
                        color: colors.statusInfo,
                        title: 'Stay (25%)',
                        titleStyle: SplitUpTypography.caption(color: Colors.white),
                        radius: 36,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Member Spending breakdown
        Text(
          'Member Breakdown',
          style: SplitUpTypography.title(color: colors.textPrimary),
        ),
        const SizedBox(height: 12),
        ...group.members.map((m) {
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.surfaceFlat,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.divider),
            ),
            child: Row(
              children: [
                Avatar(name: m.displayName, size: 40),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.displayName, style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 15)),
                      Text('Paid ₹12,000 · Share ₹9,700', style: SplitUpTypography.caption(color: colors.textMuted)),
                    ],
                  ),
                ),
                MoneyText(230000, variant: MoneyVariant.body, showSign: true),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSettleTab(SplitUpColors colors, MockGroup group) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      children: [
        // Settle Graph CTA Card
        GlassCard(
          strong: true,
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(Icons.hub_rounded, size: 48, color: colors.accentBrass),
              const SizedBox(height: 12),
              Text(
                'Settlement Node Graph',
                style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 18),
              ),
              const SizedBox(height: 6),
              Text(
                'View simplified multi-party payments (at most N-1 transactions) or pairwise actual debts.',
                textAlign: TextAlign.center,
                style: SplitUpTypography.body(color: colors.textMuted).copyWith(fontSize: 13),
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: 'Open Settlement Graph',
                icon: Icons.hub_outlined,
                onPressed: () => context.push('/groups/${group.id}/graph'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Direct Settlement Options',
          style: SplitUpTypography.title(color: colors.textPrimary),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.surfaceFlat,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.divider),
          ),
          child: Row(
            children: [
              Avatar(name: MockDataRepository.userRahul.displayName, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pay Rahul Sharma', style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 15)),
                    Text('Simplified debt: ₹1,200', style: SplitUpTypography.caption(color: colors.textMuted)),
                  ],
                ),
              ),
              SettleButton(
                amountPaise: 120000,
                compact: true,
                onPressed: () {},
              ),
            ],
          ),
        ),
      ],
    );
  }
}
