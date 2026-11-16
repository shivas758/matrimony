import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../models/profile.dart';
import '../../../services/api_client.dart';
import '../../../services/profile_service.dart';
import '../../../state/auth_state.dart';
import '../../../state/browse_state.dart';
import '../../../state/interests_state.dart';
import '../../../state/notifications_state.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/photo_viewer.dart';
import '../../widgets/profile_sections.dart';
import '../../widgets/report_sheet.dart';
import '../get_started/get_started_screen.dart';

/// Another family's profile (SPEC §9.11 Gandharva 3): photo carousel, chips,
/// at-a-glance tiles, the public cards, then the interest block — "I'm
/// interested" → pending banner → shared details with the days-left count,
/// or the declined / withdrawn / ended states with a way to ask again.
/// Nothing about who uploaded the profile is ever shown (the API does not
/// send it). Details the family switched off (SPEC §9.18 D) arrive empty —
/// a hidden name as "Profile 1042", a single photo — and the page says so
/// with a lock note; they come with the on-request block once the interest
/// is accepted. ⋮ → *Report profile* / *Block* (SPEC §9.22).
class ProfileDetailScreen extends StatefulWidget {
  const ProfileDetailScreen({super.key, required this.profileId});

  final int profileId;

  @override
  State<ProfileDetailScreen> createState() => _ProfileDetailScreenState();
}

class _ProfileDetailScreenState extends State<ProfileDetailScreen> {
  Profile? _profile;
  String? _error;

  /// 403 `unlock_required` — no full access yet (SPEC §9.12).
  bool _locked = false;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _locked = false;
    });
    try {
      final profile = await context.read<ProfileService>().detail(widget.profileId);
      if (mounted) setState(() => _profile = profile);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _locked = e.isUnlockRequired;
          _error = friendlyMessage(e);
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, friendlyMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Keeps the Browse cards and the Interested tab in step with what just happened.
  void _syncOthers({String? status, required bool interested}) {
    context.read<BrowseState>().noteInterest(widget.profileId, status: status, interested: interested);
    final customer = context.read<AuthState>().customer;
    if (customer != null) context.read<InterestsState>().load(customer.id, force: true);
  }

  Future<void> _express() async {
    // Several live profiles of mine could be the interested one → ask
    // "On behalf of" (SPEC §9.12); with one (or none) the server decides.
    int? fromProfileId;
    final target = _profile;
    // Fresh `profiles[]` — one may have gone live since the app last looked.
    await context.read<AuthState>().refresh();
    if (!mounted) return;
    final customer = context.read<AuthState>().customer;
    if (target != null && customer != null) {
      final candidates = customer.liveProfilesFor(target.gender);
      if (candidates.length > 1) {
        fromProfileId = await _pickOnBehalfOf(candidates);
        if (fromProfileId == null) return;
      }
    }
    if (!mounted) return;
    final note = await _promptNote();
    if (note == null) return;
    await _run(() async {
      await context
          .read<ProfileService>()
          .markInterested(widget.profileId, note: note, fromProfileId: fromProfileId);
      await _load();
      if (!mounted) return;
      _syncOthers(status: 'pending', interested: true);
      showSnack(context, S.interestSent);
    });
  }

  /// "On behalf of": which of my live profiles is interested; null = cancelled.
  Future<int?> _pickOnBehalfOf(List<ProfileSummary> options) => showDialog<int>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text(S.onBehalfOf),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(S.onBehalfOfBody),
            ),
            for (final p in options)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, p.id),
                child: Row(
                  children: [
                    const Icon(Icons.person_rounded, color: AppColors.goldDark),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        [p.displayName, if (p.age != null) '${p.age} ${S.yearsShort}'].join(' · '),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );

  /// Optional note dialog; returns '' for none, null when cancelled.
  Future<String?> _promptNote() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(S.interestNoteTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(S.interestNoteBody),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLength: 500,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: S.interestNoteHint),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text(S.cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text(S.sendInterest),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _withdraw() async {
    final interest = _profile?.interest;
    if (interest == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(S.withdrawConfirmTitle),
        content: const Text(S.withdrawConfirmBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text(S.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text(S.withdraw)),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await context.read<ProfileService>().withdraw(interest.id);
      await _load();
      if (!mounted) return;
      _syncOthers(status: 'withdrawn', interested: false);
      showSnack(context, S.withdrawnSnack);
    });
  }

  // ------------------------------------------------------------ report / block (SPEC §9.22)

  Future<void> _report() async {
    final sent = await showReportSheet(context, profileId: widget.profileId);
    if (sent && mounted) showSnack(context, S.reportThanks);
  }

  /// Confirm → block → back to where I came from, the profile gone from my lists.
  Future<void> _block() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(S.blockTitle),
        content: const Text(S.blockBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text(S.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(S.block),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() async {
      await context.read<ProfileService>().blockProfile(widget.profileId);
      if (!mounted) return;
      _forgetBlocked();
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text(S.profileBlocked)));
    });
  }

  /// The blocked profile leaves Browse and Interested now; the server's view
  /// (pending interests withdrawn) follows with a reload.
  void _forgetBlocked() {
    final id = widget.profileId;
    context.read<BrowseState?>()?.removeProfile(id);
    final interests = context.read<InterestsState?>();
    interests?.removeProfile(id);
    final customer = context.read<AuthState>().customer;
    if (interests != null && customer != null) interests.load(customer.id, force: true);
    context.read<NotificationsState?>()?.refresh();
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    if (_loading && _profile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_profile == null && _locked) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.lock_rounded,
          title: S.lockedDetailTitle,
          message: S.errUnlockRequired,
          actionLabel: S.getStarted,
          onAction: () => GetStartedScreen.open(context),
        ),
      );
    }
    if (_profile == null) {
      return Scaffold(
        appBar: AppBar(),
        body: ErrorState(message: _error ?? S.somethingWrong, onRetry: _load),
      );
    }

    final p = _profile!;
    final interest = p.interest;

    return Scaffold(
      body: ProfileDetailView(
        profile: p,
        onRefresh: _load,
        // Report / Block another family's profile (SPEC §9.22 D).
        actions: [
          if (!p.isMine)
            PopupMenuButton<_SafetyAction>(
              tooltip: S.moreOptions,
              icon: const Icon(Icons.more_vert_rounded),
              enabled: !_busy,
              onSelected: (action) => switch (action) {
                _SafetyAction.report => _report(),
                _SafetyAction.block => _block(),
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: _SafetyAction.report,
                  child: _MenuRow(icon: Icons.flag_outlined, label: S.reportProfile),
                ),
                PopupMenuItem(
                  value: _SafetyAction.block,
                  child: _MenuRow(
                    icon: Icons.block_rounded,
                    label: S.block,
                    color: Theme.of(ctx).colorScheme.error,
                  ),
                ),
              ],
            ),
        ],
        footer: InterestBlock(profile: p, interest: interest),
      ),
      bottomNavigationBar: _ActionBar(
        interest: interest,
        busy: _busy,
        onExpress: _express,
        onWithdraw: _withdraw,
      ),
    );
  }
}

/// The profile page itself, without anything that acts on it: the photo
/// carousel under a collapsing title, the chips, the "some details are
/// hidden" note, the at-a-glance tiles, the public cards and then [footer].
/// [ProfileDetailScreen] adds the ⋮ menu, the interest block and the action
/// bar; the "View as others see it" preview (SPEC §9.23 D) shows it as is.
class ProfileDetailView extends StatefulWidget {
  const ProfileDetailView({
    super.key,
    required this.profile,
    this.actions = const [],
    this.footer,
    this.onRefresh,
    this.showBackButton = true,
    this.expandedHeight = 400,
  });

  final Profile profile;

  /// App bar actions (the ⋮ menu).
  final List<Widget> actions;

  /// Below the public cards (the interest block, a note, the shared details).
  final Widget? footer;

  /// Pull to refresh, when set.
  final Future<void> Function()? onRefresh;

  /// A page of its own (back arrow, pinned title) — false inside a tab.
  final bool showBackButton;
  final double expandedHeight;

  @override
  State<ProfileDetailView> createState() => _ProfileDetailViewState();
}

class _ProfileDetailViewState extends State<ProfileDetailView> {
  int _photoIndex = 0;

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final scroll = CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: widget.expandedHeight,
          pinned: widget.showBackButton,
          automaticallyImplyLeading: widget.showBackButton,
          backgroundColor: AppColors.wine,
          foregroundColor: Colors.white,
          // The theme's wine icons would vanish on the wine bar / dark photo scrim.
          iconTheme: const IconThemeData(color: Colors.white),
          actionsIconTheme: const IconThemeData(color: Colors.white),
          systemOverlayStyle: SystemUiOverlayStyle.light,
          actions: widget.actions,
          flexibleSpace: FlexibleSpaceBar(
            titlePadding: EdgeInsetsDirectional.only(start: widget.showBackButton ? 56 : 16, end: 24, bottom: 14),
            expandedTitleScale: 1.5,
            title: Text(
              p.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AppTheme.displayFont,
                fontWeight: FontWeight.w600,
                fontVariations: [FontVariation('wght', 600)],
                color: Colors.white,
                fontSize: 18,
                shadows: [Shadow(color: Color(0x99000000), blurRadius: 12)],
              ),
            ),
            background: _PhotoCarousel(
              profile: p,
              index: _photoIndex,
              onIndexChanged: (i) => setState(() => _photoIndex = i),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProfileChipRow(profile: p),
                // Some details are kept back until the family approves.
                if (p.hasMaskedFields) ...[
                  const SizedBox(height: 12),
                  const LockNote(text: S.someDetailsHidden),
                ],
                const SizedBox(height: 16),
                ProfileFactGrid(profile: p),
                const SizedBox(height: 20),
                ProfilePublicCards(profile: p),
                ?widget.footer,
              ],
            ),
          ),
        ),
      ],
    );
    final refresh = widget.onRefresh;
    return refresh == null ? scroll : RefreshIndicator(onRefresh: refresh, child: scroll);
  }
}

enum _SafetyAction { report, block }

/// Icon + label in the ⋮ menu.
class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 20, color: color ?? AppColors.wine),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        ],
      );
}

/// The state card at the bottom of the page (SPEC §9.11 Gandharva 3) — with
/// the shared details while an accepted interest is live. Also the "after
/// interest is accepted" part of the preview (SPEC §9.23 D).
class InterestBlock extends StatelessWidget {
  const InterestBlock({super.key, required this.profile, required this.interest});

  final Profile profile;
  final Interest? interest;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final i = interest;

    if (i == null) {
      return const NoticeCard(
        icon: Icons.favorite_border_rounded,
        title: S.interestHintTitle,
        body: S.interestHintBody,
        tint: AppColors.goldDark,
      );
    }
    if (i.isPending) {
      return const NoticeCard(
        icon: Icons.hourglass_top_rounded,
        title: S.interestSent,
        body: S.interestSentBody,
        tint: AppColors.warning,
      );
    }
    if (i.isLive || profile.detailsShared) {
      final days = profile.accessDaysLeft;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NoticeCard(
            icon: Icons.lock_open_rounded,
            title: days == null ? S.detailsShared : '${S.detailsShared} · ${S.daysLeft(days)}',
            body: S.detailsSharedBody,
            tint: AppColors.success,
          ),
          const SizedBox(height: 12),
          SharedDetailsCard(profile: profile, daysLeft: days),
        ],
      );
    }
    final (icon, title, body, tint) = switch (i.status) {
      'declined' => (Icons.do_not_disturb_on_outlined, S.notTakenForward, S.notTakenForwardBody, scheme.error),
      'withdrawn' => (Icons.undo_rounded, S.withdrawnTitle, S.withdrawnBody, scheme.outline),
      'revoked' => (Icons.lock_outline_rounded, S.accessEndedTitle, S.accessEndedBody, scheme.error),
      _ => (Icons.schedule_rounded, S.expiredTitle, S.expiredBody, scheme.outline),
    };
    return NoticeCard(icon: icon, title: title, body: body, tint: tint);
  }
}

/// Always-visible primary action: "I'm interested" (or "Express interest
/// again"), "Withdraw" while pending, nothing while details are shared.
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.interest,
    required this.busy,
    required this.onExpress,
    required this.onWithdraw,
  });

  final Interest? interest;
  final bool busy;
  final VoidCallback onExpress;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) {
    final i = interest;
    Widget? button;
    if (i == null) {
      button = FilledButton.icon(
        onPressed: busy ? null : onExpress,
        icon: busy ? const ButtonSpinner() : const Icon(Icons.favorite_rounded),
        label: const Text(S.imInterested),
      );
    } else if (i.isPending) {
      button = OutlinedButton.icon(
        onPressed: busy ? null : onWithdraw,
        icon: busy ? const ButtonSpinner(color: AppColors.wine) : const Icon(Icons.undo_rounded),
        label: const Text(S.withdraw),
      );
    } else if (i.canReExpress) {
      button = FilledButton.icon(
        onPressed: busy ? null : onExpress,
        icon: busy ? const ButtonSpinner() : const Icon(Icons.favorite_rounded),
        label: const Text(S.expressAgain),
      );
    }
    if (button == null) return const SizedBox.shrink();
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.rule)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 10), child: button),
      ),
    );
  }
}

class _PhotoCarousel extends StatelessWidget {
  const _PhotoCarousel({required this.profile, required this.index, required this.onIndexChanged});

  final Profile profile;
  final int index;
  final ValueChanged<int> onIndexChanged;

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    final photos = profile.photos;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (photos.isEmpty)
          AuthedPhoto(url: null, api: api, placeholderInitials: initialsOf(profile.initialsSource ?? ''))
        else
          PageView.builder(
            onPageChanged: onIndexChanged,
            itemCount: photos.length,
            // Whole photo, never cut; tap → full screen (SPEC §9.17).
            itemBuilder: (_, i) => WholePhoto(
              url: photos[i].absoluteUrl,
              api: api,
              onTap: () => PhotoViewer.open(
                context,
                urls: [for (final ph in photos) ph.absoluteUrl],
                api: api,
                initialIndex: i,
              ),
            ),
          ),
        // Scrims so the collapsing title and the counter read on any photo.
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(0, 0.1),
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0xD93A0419)],
              ),
            ),
          ),
        ),
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment(0, -0.4),
                colors: [Color(0x803A0419), Colors.transparent],
              ),
            ),
          ),
        ),
        if (photos.length > 1)
          Positioned(
            right: 16,
            bottom: 18,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.photo_library_outlined, size: 13, color: Colors.white),
                  const SizedBox(width: 5),
                  Text(
                    '${index + 1}/${photos.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
