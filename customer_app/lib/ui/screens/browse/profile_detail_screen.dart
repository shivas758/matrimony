import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../models/profile.dart';
import '../../../services/api_client.dart';
import '../../../services/profile_service.dart';
import '../../../state/auth_state.dart';
import '../../../state/browse_state.dart';
import '../../../state/interests_state.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/profile_sections.dart';
import '../get_started/get_started_screen.dart';

/// Another family's profile (SPEC §9.11 Gandharva 3): photo carousel, chips,
/// at-a-glance tiles, the public cards, then the interest block — "I'm
/// interested" → pending banner → shared details with the days-left count,
/// or the declined / withdrawn / ended states with a way to ask again.
/// Nothing about who uploaded the profile is ever shown (the API does not
/// send it).
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
  int _photoIndex = 0;

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
                    const Icon(Icons.person_rounded, color: AppColors.roseDark),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        [p.fullName, if (p.age != null) '${p.age} ${S.yearsShort}'].join(' · '),
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
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 400,
              pinned: true,
              backgroundColor: AppColors.maroon,
              foregroundColor: Colors.white,
              systemOverlayStyle: SystemUiOverlayStyle.light,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsetsDirectional.only(start: 56, end: 24, bottom: 14),
                expandedTitleScale: 1.5,
                title: Text(
                  p.fullName,
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
                    const SizedBox(height: 16),
                    ProfileFactGrid(profile: p),
                    const SizedBox(height: 20),
                    ProfilePublicCards(profile: p),
                    _InterestBlock(profile: p, interest: interest),
                  ],
                ),
              ),
            ),
          ],
        ),
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

/// The state card at the bottom of the page (SPEC §9.11 Gandharva 3).
class _InterestBlock extends StatelessWidget {
  const _InterestBlock({required this.profile, required this.interest});

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
        tint: AppColors.roseDark,
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
        icon: busy ? const ButtonSpinner(color: AppColors.maroon) : const Icon(Icons.undo_rounded),
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
          AuthedPhoto(url: null, api: api, placeholderInitials: initialsOf(profile.fullName))
        else
          PageView.builder(
            onPageChanged: onIndexChanged,
            itemCount: photos.length,
            itemBuilder: (_, i) => AuthedPhoto(url: photos[i].absoluteUrl, api: api),
          ),
        // Scrims so the collapsing title and the counter read on any photo.
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(0, 0.1),
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0xD92E0F18)],
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
                colors: [Color(0x802E0F18), Colors.transparent],
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
