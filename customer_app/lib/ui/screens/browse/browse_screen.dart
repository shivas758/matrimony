import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/api_client.dart';
import '../../../state/auth_state.dart';
import '../../../state/browse_state.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/common.dart';
import '../../widgets/notification_bell.dart';
import '../get_started/get_started_screen.dart';
import 'filter_sheet.dart';
import 'profile_card.dart';
import 'profile_detail_screen.dart';

/// Browse (SPEC §9.11 Gandharva 3 / §9.12): the Bride / Groom toggle, the
/// filter sheet, infinite scroll and pull-to-refresh. Guest access: a banner
/// with *Get started*, locked teaser cards (tap → Get started), every filter
/// but no name search (SPEC §9.13). Full access: profiles in my agent's
/// communities, search by name, cards → detail. [HomeShell] mounts it.
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  final _scroll = ScrollController();
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final customer = context.read<AuthState>().customer;
      if (customer != null) context.read<BrowseState>().ensureLoaded(customer.id);
    });
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _search.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) {
      context.read<BrowseState>().loadMore();
    }
  }

  Future<void> _openFilters() async {
    final state = context.read<BrowseState>();
    final agent = context.read<AuthState>().agent;
    final next = await FilterSheet.show(
      context,
      state.filters,
      // Guests browse every community.
      communities: state.isGuest ? const [] : agent?.communities ?? const [],
      guest: state.isGuest,
    );
    if (next != null) await state.setFilters(next);
  }

  /// The account was suspended when the list loaded — re-read the account
  /// (the root swaps to the blocked screen).
  Future<void> _checkAgain() async {
    try {
      await context.read<AuthState>().refreshCustomer();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, friendlyMessage(e), error: true);
      return;
    }
    if (mounted) context.read<BrowseState>().refresh();
  }

  void _getStarted() => GetStartedScreen.open(context);

  void _openDetail(int id) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProfileDetailScreen(profileId: id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<BrowseState>();
    final theme = Theme.of(context);
    final guest = state.isGuest;
    final activeCount = state.filters.activeCount;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        actions: const [NotificationBell(), SizedBox(width: 4)],
        title: Row(
          children: [
            const AppLogo(size: 30, shadow: false),
            const SizedBox(width: 10),
            const AppWordmark(size: 22, showTagline: false),
            if (state.total > 0) ...[
              const SizedBox(width: 10),
              Text(
                S.matchesCount(state.total),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (guest) _GuestBanner(onGetStarted: _getStarted),
          _SearchBar(
            controller: _search,
            activeCount: activeCount,
            // Name search is ignored for guests (SPEC §9.12) — hide it.
            showSearch: !guest,
            gender: state.filters.gender,
            onGender: (g) => context.read<BrowseState>().setGender(g),
            onChanged: context.read<BrowseState>().setSearch,
            onClear: () {
              _search.clear();
              context.read<BrowseState>().setSearch('');
            },
            onOpenFilters: _openFilters,
          ),
          Expanded(child: _body(state)),
        ],
      ),
    );
  }

  Widget _body(BrowseState state) {
    if (state.loading && state.profiles.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    // Not an error: the account is not active (403 account_*). Friendly copy.
    if (state.blockedCode != null && state.profiles.isEmpty) {
      final (title, message) = switch (state.blockedCode) {
        'account_rejected' => (S.rejectedTitle, S.errAccountRejected),
        'account_pending' => (S.pendingTitle, S.errAccountPending),
        _ => (S.suspendedTitle, S.errAccountSuspended),
      };
      return _scrollable(
        EmptyState(
          icon: Icons.hourglass_top_rounded,
          title: title,
          message: message,
          actionLabel: S.checkAgain,
          onAction: _checkAgain,
        ),
      );
    }
    if (state.error != null && state.profiles.isEmpty) {
      return ErrorState(message: state.error!, onRetry: state.refresh);
    }
    if (state.isEmpty) {
      final filtered = state.filters.activeCount > 0 || state.filters.hasSearch;
      return _scrollable(
        EmptyState(
          icon: filtered ? Icons.search_off_rounded : Icons.people_outline_rounded,
          title: filtered ? S.noMatches : S.noProfiles,
          message: filtered ? S.noMatchesHint : S.noProfilesHint,
          actionLabel: filtered ? S.clearAll : null,
          onAction: filtered
              ? () {
                  _search.clear();
                  state.setFilters(state.filters.clearedFilters().copyWith(clearQuery: true));
                }
              : null,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: state.refresh,
      child: ListView.separated(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        itemCount: state.profiles.length + (state.loadingMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          if (i >= state.profiles.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final profile = state.profiles[i];
          if (profile.locked || state.isGuest) {
            return GuestProfileCard(profile: profile, onTap: _getStarted);
          }
          return ProfileCard(
            profile: profile,
            interested: state.isInterested(profile),
            onTap: () => _openDetail(profile.id),
          );
        },
      ),
    );
  }

  /// Empty states inside a scroll view so pull-to-refresh still works.
  Widget _scrollable(Widget child) => RefreshIndicator(
        onRefresh: context.read<BrowseState>().refresh,
        child: ListView(
          children: [SizedBox(height: MediaQuery.sizeOf(context).height * 0.12), child],
        ),
      );
}

/// Search field (full access only) + the Filters button with its
/// active-count badge, and the Bride / Groom toggle.
class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.activeCount,
    required this.showSearch,
    required this.gender,
    required this.onGender,
    required this.onChanged,
    required this.onClear,
    required this.onOpenFilters,
  });

  final TextEditingController controller;
  final int activeCount;
  final bool showSearch;

  /// 'bride' | 'groom' | null (both, or the server's default).
  final String? gender;
  final ValueChanged<String?> onGender;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onOpenFilters;

  @override
  Widget build(BuildContext context) {
    final genderChips = Wrap(
      spacing: 8,
      children: [
        for (final (value, label) in const [('bride', S.bride), ('groom', S.groom)])
          ChoiceChip(
            label: Text(label),
            selected: gender == value,
            // Tapping the selected one again shows both.
            onSelected: (on) => onGender(on ? value : null),
          ),
      ],
    );
    final filtersButton = Badge(
      isLabelVisible: activeCount > 0,
      label: Text('$activeCount'),
      child: IconButton.filledTonal(
        tooltip: S.filters,
        style: IconButton.styleFrom(
          minimumSize: const Size(52, 52),
          backgroundColor: activeCount > 0 ? AppColors.wine : AppColors.goldLight,
          foregroundColor: activeCount > 0 ? Colors.white : AppColors.wine,
        ),
        icon: const Icon(Icons.tune_rounded),
        onPressed: onOpenFilters,
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: showSearch
                    ? ValueListenableBuilder<TextEditingValue>(
                        valueListenable: controller,
                        builder: (_, value, _) => TextField(
                          controller: controller,
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: S.searchHint,
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: value.text.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: S.clear,
                                    icon: const Icon(Icons.close_rounded),
                                    onPressed: onClear,
                                  ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                          onChanged: onChanged,
                        ),
                      )
                    : genderChips,
              ),
              const SizedBox(width: 10),
              filtersButton,
            ],
          ),
          if (showSearch) ...[const SizedBox(height: 6), genderChips],
        ],
      ),
    );
  }
}

/// "You are browsing as a guest — register to open profiles" + Get started.
class _GuestBanner extends StatelessWidget {
  const _GuestBanner({required this.onGetStarted});

  final VoidCallback onGetStarted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline_rounded, color: AppColors.gold),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              S.guestBannerTitle,
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: AppColors.wineDeep,
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            onPressed: onGetStarted,
            child: const Text(S.getStarted),
          ),
        ],
      ),
    );
  }
}
