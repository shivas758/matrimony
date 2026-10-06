import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/profile.dart';
import '../../../services/api_client.dart';
import '../../../services/contact_service.dart';
import '../../../services/hold_service.dart';
import '../../../services/profile_service.dart';
import '../../../services/share_service.dart';
import '../../../state/auth_state.dart';
import '../../../state/profiles_state.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'profile_form_screen.dart';

class ProfileDetailScreen extends StatefulWidget {
  const ProfileDetailScreen({super.key, required this.profileId});

  final int profileId;

  @override
  State<ProfileDetailScreen> createState() => _ProfileDetailScreenState();
}

/// How the agent wants to send the profile (SPEC §4 Sharing).
enum ShareMode { link, pdf, card }

class _ProfileDetailScreenState extends State<ProfileDetailScreen> {
  Profile? _profile;
  String? _error;
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
    });
    try {
      final profile = await context.read<ProfileService>().detail(widget.profileId);
      if (mounted) setState(() => _profile = profile);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
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
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestContact() async {
    final note = await _promptNote();
    if (note == null) return;
    await _run(() async {
      await context.read<ContactService>().request(widget.profileId, note: note.isEmpty ? null : note);
      await _load();
      if (mounted) showSnack(context, S.contactRequested);
    });
  }

  Future<String?> _promptNote() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(S.requestContact),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'The uploader will see your name and bureau. Add a short note if you like.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLength: 200,
              maxLines: 2,
              decoration: const InputDecoration(hintText: 'e.g. Matching my client in Hyderabad'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text(S.cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Send request'),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ sharing

  /// Share button: asks how to send it, then runs the matching flow.
  Future<void> _share() async {
    final mode = await _ShareSheet.show(context);
    if (mode == null || !mounted) return;
    switch (mode) {
      case ShareMode.link:
        await _shareWhatsApp();
      case ShareMode.pdf:
        await _sharePdf();
      case ShareMode.card:
        await _downloadCard();
    }
  }

  Future<void> _shareWhatsApp() => _run(() async {
        final link = await context.read<ShareService>().shareLink(widget.profileId);
        final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(link.whatsappText)}');
        if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          // No WhatsApp installed — fall back to the system share sheet.
          await SharePlus.instance.share(ShareParams(text: link.whatsappText));
        }
      });

  String get _safeName => _profile!.fullName.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');

  /// PDF bio-data: fetched from the server (masked, watermarked) and handed
  /// to the system share sheet as a file — WhatsApp shows it as a document.
  Future<void> _sharePdf() => _run(() async {
        showSnack(context, S.preparingPdf);
        final bytes = await context.read<ShareService>().downloadPdf(widget.profileId);
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/${_safeName}_profile.pdf');
        await file.writeAsBytes(bytes, flush: true);
        if (!mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path, mimeType: 'application/pdf', name: '${_safeName}_profile.pdf')],
            text: '${_profile!.fullName} — profile',
          ),
        );
      });

  Future<void> _downloadCard() => _run(() async {
        showSnack(context, S.preparingCard);
        final bytes = await context.read<ShareService>().downloadCard(widget.profileId);
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$_safeName.jpg');
        await file.writeAsBytes(bytes, flush: true);
        if (!mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        await SharePlus.instance.share(
          ShareParams(files: [XFile(file.path, mimeType: 'image/jpeg')], text: _profile!.fullName),
        );
      });

  // ------------------------------------------------------------------ shortlist

  Future<void> _shortlist() async {
    final service = context.read<ShortlistService>();
    List<String> labels = const [];
    try {
      labels = await service.labels();
    } on ApiException {
      // Fall back to a free-text label.
    }
    if (!mounted) return;

    final label = await _promptShortlistLabel(labels);
    if (label == null) return;
    await _run(() async {
      await service.add(widget.profileId, label);
      if (mounted) {
        showSnack(context, label.isEmpty ? 'Shortlisted' : 'Added to "$label"');
      }
    });
  }

  Future<String?> _promptShortlistLabel(List<String> existing) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(S.addToShortlist),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (existing.isNotEmpty) ...[
              const Text('Pick a client'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final label in existing)
                    ActionChip(
                      label: Text(label.isEmpty ? 'Unlabelled' : label),
                      onPressed: () => Navigator.pop(ctx, label),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
            ],
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              autofocus: existing.isEmpty,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: S.clientLabel,
                hintText: "e.g. Ramesh's daughter",
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text(S.cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ProfileFormScreen(existing: _profile)),
    );
    if (saved == true) {
      await _load();
      if (mounted && _profile != null) {
        context.read<ProfilesState>().replaceProfile(_profile!);
      }
    }
  }

  // ------------------------------------------------------------ hold / delete

  /// Re-reads the profile after a hold change and keeps the list in step.
  Future<void> _reloadAfterHold(String message) async {
    await _load();
    if (!mounted) return;
    final p = _profile;
    if (p != null) {
      // A profile that just went on hold vanishes from other agents' lists;
      // for the holder / uploader it stays, with the new status.
      context.read<ProfilesState>().replaceProfile(p);
    }
    context.read<AuthState>().refreshNotifications();
    showSnack(context, message);
  }

  /// Any agent: ask the uploader for a hold (approval needed).
  Future<void> _requestHold() async {
    final note = await _promptHoldNote();
    if (note == null) return;
    await _run(() async {
      await context.read<HoldService>().request(widget.profileId, note: note.isEmpty ? null : note);
      await _reloadAfterHold(S.holdRequested);
    });
  }

  /// Uploader / admin: put on hold right away (approved on the spot).
  Future<void> _putOnHold() async {
    final note = await _promptHoldNote(own: true);
    if (note == null) return;
    await _run(() async {
      await context.read<HoldService>().request(widget.profileId, note: note.isEmpty ? null : note);
      await _reloadAfterHold('Profile is on hold — hidden from other agents');
    });
  }

  Future<String?> _promptHoldNote({bool own = false}) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(own ? S.putOnHold : S.requestHold),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(own ? S.holdApprovedBody : S.holdRequestBody),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLength: 200,
              maxLines: 2,
              decoration: const InputDecoration(hintText: 'Note (optional), e.g. talks with my client'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text(S.cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(own ? S.putOnHold : S.requestHold),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelHold() async {
    final id = _profile?.holdRequestId;
    if (id == null) return;
    await _run(() async {
      await context.read<HoldService>().cancel(id);
      await _reloadAfterHold('Hold request cancelled');
    });
  }

  /// Holder, uploader or admin: release the hold; the profile is active again.
  Future<void> _releaseHold() async {
    final p = _profile;
    if (p == null) return;
    final id = p.holdMine ? p.holdRequestId : p.heldBy?.holdRequestId;
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(S.releaseHold),
        content: const Text('The profile becomes visible to other agents again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text(S.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text(S.releaseHold)),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await context.read<HoldService>().release(id);
      await _reloadAfterHold(S.holdReleasedMsg);
    });
  }

  /// Uploader or admin: permanent delete, photos and links included.
  Future<void> _delete() async {
    final p = _profile;
    if (p == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${S.deleteProfile}: ${p.fullName}?'),
        content: const Text(S.deleteProfileBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text(S.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(S.delete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await context.read<ProfileService>().delete(p.id);
      if (!mounted) return;
      context.read<ProfilesState>().removeProfile(p.id);
      showSnack(context, S.profileDeleted);
      Navigator.of(context).pop(true);
    });
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    if (_loading && _profile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_profile == null) {
      return Scaffold(
        appBar: AppBar(),
        body: ErrorState(message: _error ?? S.somethingWrong, onRetry: _load),
      );
    }

    final p = _profile!;
    final theme = Theme.of(context);
    final facts = _facts(p);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 420,
              pinned: true,
              backgroundColor: AppColors.navy,
              foregroundColor: Colors.white,
              systemOverlayStyle: SystemUiOverlayStyle.light,
              actions: [
                if (p.canEdit)
                  IconButton(
                    tooltip: S.editProfile,
                    icon: const Icon(Icons.edit_rounded),
                    onPressed: _edit,
                  ),
                // Hold and delete live in a menu: hold for everyone who can see
                // the profile, delete for the uploader / admin only (SPEC §4).
                PopupMenuButton<String>(
                  tooltip: 'More',
                  enabled: !_busy,
                  onSelected: (action) => switch (action) {
                    'hold' => p.canEdit ? _putOnHold() : _requestHold(),
                    'cancel_hold' => _cancelHold(),
                    'release' => _releaseHold(),
                    'delete' => _delete(),
                    _ => null,
                  },
                  itemBuilder: (_) => [
                    if (p.status == ProfileStatus.active && !p.holdPending)
                      PopupMenuItem(
                        value: 'hold',
                        child: ListTile(
                          leading: const Icon(Icons.pause_circle_outline_rounded),
                          title: Text(p.canEdit ? S.putOnHold : S.requestHold),
                        ),
                      ),
                    if (p.holdPending)
                      const PopupMenuItem(
                        value: 'cancel_hold',
                        child: ListTile(
                          leading: Icon(Icons.undo_rounded),
                          title: Text(S.cancelHoldRequest),
                        ),
                      ),
                    if (p.isOnHold && (p.holdMine || p.heldBy != null))
                      const PopupMenuItem(
                        value: 'release',
                        child: ListTile(
                          leading: Icon(Icons.play_circle_outline_rounded),
                          title: Text(S.releaseHold),
                        ),
                      ),
                    if (p.canDelete)
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: Icon(Icons.delete_outline_rounded, color: theme.colorScheme.error),
                          title: Text(S.deleteProfile,
                              style: TextStyle(color: theme.colorScheme.error)),
                        ),
                      ),
                  ],
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsetsDirectional.only(start: 56, end: 100, bottom: 14),
                expandedTitleScale: 1.55,
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
                    // Who this is, in one glance.
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        StatusChip(
                          label: p.genderLabel,
                          color: p.isBride ? const Color(0xFFC2185B) : const Color(0xFF1565C0),
                          icon: p.isBride ? Icons.female_rounded : Icons.male_rounded,
                        ),
                        if (p.ageDobLine != null)
                          StatusChip(label: p.ageDobLine!, color: AppColors.navy, icon: Icons.cake_outlined),
                        if (p.communityLine != null)
                          StatusChip(label: p.communityLine!, color: AppColors.goldDark, icon: Icons.groups_rounded),
                        if (p.isNri)
                          StatusChip(label: p.nriLabel ?? 'NRI', color: const Color(0xFF00695C), icon: Icons.public_rounded),
                        if (p.status != ProfileStatus.active)
                          StatusChip(
                            label: p.status.label,
                            color: StatusColors.forProfileStatus(p.status.apiValue, theme.colorScheme),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _HoldBanner(
                      profile: p,
                      busy: _busy,
                      onRequest: _requestHold,
                      onCancel: _cancelHold,
                      onRelease: _releaseHold,
                    ),
                    _ActionRow(busy: _busy, onShare: _share, onShortlist: _shortlist),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.shield_outlined, size: 14, color: theme.colorScheme.outline),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            S.shareNote,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.outline),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _ContactSection(profile: p, busy: _busy, onRequest: _requestContact),
                    if (facts.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 2.55,
                        children: [
                          for (final f in facts) FactTile(icon: f.$1, label: f.$2, value: f.$3),
                        ],
                      ),
                    ],
                    const SizedBox(height: 20),
                    const SectionHeader(S.basicDetails),
                    SurfaceCard(
                      child: Column(
                        children: [
                          if (p.age != null) DetailRow(label: S.age, value: '${p.age} years'),
                          if (p.dobLabel != null) DetailRow(label: S.dob, value: p.dobLabel!),
                          if (p.heightLabel != null) DetailRow(label: S.height, value: p.heightLabel!),
                          if (p.weightLabel != null) DetailRow(label: S.weight, value: p.weightLabel!),
                          if (p.complexion != null)
                            DetailRow(label: S.complexion, value: p.complexion!.name),
                          if (p.maritalStatus != null)
                            DetailRow(label: S.maritalStatus, value: p.maritalStatus!.name),
                          if (p.religion != null) DetailRow(label: S.religion, value: p.religion!.name),
                          if (p.community != null) DetailRow(label: S.community, value: p.community!.name),
                          if (p.subcaste != null) DetailRow(label: S.subcaste, value: p.subcaste!.name),
                          if ((p.gothram ?? '').isNotEmpty) DetailRow(label: S.gothram, value: p.gothram!),
                          if (p.motherTongue != null)
                            DetailRow(label: S.motherTongue, value: p.motherTongue!.name),
                          if (p.knownLanguagesLabel != null)
                            DetailRow(label: S.knownLanguages, value: p.knownLanguagesLabel!),
                          if (p.foodHabit != null) DetailRow(label: S.foodHabit, value: p.foodHabit!.name),
                          if (p.nationality != null)
                            DetailRow(label: S.nationality, value: p.nationality!.name),
                          if (p.educationLine != null)
                            DetailRow(label: S.education, value: p.educationLine!),
                          // The education table (SPEC §9.7): one row per filled level.
                          for (final lv in p.educationLevels)
                            if (lv.valueLine != null) DetailRow(label: lv.label, value: lv.valueLine!),
                          if (p.professionLine != null)
                            DetailRow(label: S.profession, value: p.professionLine!),
                          if (p.occupationType != null)
                            DetailRow(label: S.occupationType, value: p.occupationType!.name),
                          // Public coarse location (SPEC §9.8); the exact work
                          // place is in the personal-details card above.
                          if (p.workCountry != null)
                            DetailRow(label: S.worksIn, value: p.workCountry!.name),
                          if (p.nriLabel != null) DetailRow(label: S.nri, value: p.nriLabel!),
                          if ((p.incomeText ?? '').isNotEmpty)
                            DetailRow(label: S.income, value: p.incomeText!),
                          if ((p.otherIncome ?? '').isNotEmpty)
                            DetailRow(label: S.otherIncome, value: p.otherIncome!),
                        ],
                      ),
                    ),
                    // Birth place is protected (SPEC §9.8) — it is in the
                    // personal-details card, not here.
                    if (p.starRasi != null || p.birthTimeLabel != null) ...[
                      const SizedBox(height: 16),
                      const SectionHeader(S.horoscope),
                      SurfaceCard(
                        child: Column(
                          children: [
                            if (p.nakshatram != null)
                              DetailRow(label: S.nakshatram, value: p.nakshatram!.name),
                            if (p.zodiac != null) DetailRow(label: S.rasi, value: p.zodiac!.label),
                            if (p.dobLabel != null) DetailRow(label: S.dob, value: p.dobLabel!),
                            if (p.birthTimeLabel != null)
                              DetailRow(label: S.birthTime, value: p.birthTimeLabel!),
                          ],
                        ),
                      ),
                    ],
                    // Siblings and family details are protected since v2.1 —
                    // they live in the personal-details card (_ContactSection).
                    if ((p.about ?? '').isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const SectionHeader(S.about),
                      SurfaceCard(
                        child: Text(p.about!, style: theme.textTheme.bodyLarge?.copyWith(height: 1.5)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The six most useful facts for the tile grid, in priority order.
  List<(IconData, String, String)> _facts(Profile p) {
    final all = <(IconData, String, String)>[
      if (p.heightLabel != null) (Icons.straighten_rounded, S.height, p.heightLabel!),
      if (p.education != null) (Icons.school_rounded, S.education, p.education!.name),
      if (p.profession != null) (Icons.work_outline_rounded, S.profession, p.profession!.name),
      if (p.religion != null) (Icons.temple_hindu_rounded, S.religion, p.religion!.name),
      if (p.motherTongue != null) (Icons.translate_rounded, S.motherTongue, p.motherTongue!.name),
      if (p.foodHabit != null) (Icons.restaurant_rounded, S.foodHabit, p.foodHabit!.name),
      if (p.maritalStatus != null) (Icons.favorite_border_rounded, S.maritalStatus, p.maritalStatus!.name),
      // Public location only: the NRI country or the work country (SPEC §9.8).
      if (p.worksIn != null) (Icons.public_rounded, S.worksIn, p.worksIn!),
      if (p.starRasi != null) (Icons.auto_awesome_rounded, S.starRasi, p.starRasi!),
    ];
    return all.take(6).toList();
  }
}

class _PhotoCarousel extends StatelessWidget {
  const _PhotoCarousel({
    required this.profile,
    required this.index,
    required this.onIndexChanged,
  });

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
        // Scrim so the collapsing title and the dots read on any photo.
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(0, 0.1),
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0xD9081C33)],
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
                colors: [Color(0x80081C33), Colors.transparent],
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

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.busy, required this.onShare, required this.onShortlist});

  final bool busy;
  final VoidCallback onShare;
  final VoidCallback onShortlist;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: busy ? null : onShare,
              icon: busy
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.share_rounded, size: 18),
              label: const Text(S.shareTitle),
            ),
          ),
          const SizedBox(width: 10),
          IconButton.outlined(
            tooltip: S.shortlist,
            iconSize: 22,
            style: IconButton.styleFrom(
              minimumSize: const Size(52, 52),
              side: const BorderSide(color: AppColors.navy, width: 1.2),
              foregroundColor: AppColors.navy,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.bookmark_add_outlined),
            onPressed: busy ? null : onShortlist,
          ),
        ],
      );
}

/// "Share profile" bottom sheet: WhatsApp link, PDF, or photo card.
class _ShareSheet extends StatelessWidget {
  const _ShareSheet();

  static Future<ShareMode?> show(BuildContext context) => showModalBottomSheet<ShareMode>(
        context: context,
        useSafeArea: true,
        builder: (_) => const _ShareSheet(),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(S.shareTitle, style: theme.textTheme.titleLarge?.copyWith(color: AppColors.navy)),
          const SizedBox(height: 4),
          Text(
            S.shareSubtitle,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 16),
          _ShareOption(
            icon: Icons.chat_rounded,
            iconColor: const Color(0xFF25D366),
            title: S.shareLinkTitle,
            body: S.shareLinkBody,
            onTap: () => Navigator.pop(context, ShareMode.link),
          ),
          const SizedBox(height: 10),
          _ShareOption(
            icon: Icons.picture_as_pdf_rounded,
            iconColor: const Color(0xFFD32F2F),
            title: S.sharePdfTitle,
            body: S.sharePdfBody,
            onTap: () => Navigator.pop(context, ShareMode.pdf),
          ),
          const SizedBox(height: 10),
          _ShareOption(
            icon: Icons.image_rounded,
            iconColor: AppColors.navyLight,
            title: S.shareCardTitle,
            body: S.shareCardBody,
            onTap: () => Navigator.pop(context, ShareMode.card),
          ),
        ],
      ),
    );
  }
}

class _ShareOption extends StatelessWidget {
  const _ShareOption({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: AppColors.ivory,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      body,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hold state, shown only when there is something to say: my pending request,
/// my approved hold, or (uploader/admin) who holds it and who is waiting.
class _HoldBanner extends StatelessWidget {
  const _HoldBanner({
    required this.profile,
    required this.busy,
    required this.onRequest,
    required this.onCancel,
    required this.onRelease,
  });

  final Profile profile;
  final bool busy;
  final VoidCallback onRequest;
  final VoidCallback onCancel;
  final VoidCallback onRelease;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = profile;

    String? title;
    String? body;
    Widget? action;
    IconData icon = Icons.pause_circle_outline_rounded;
    Color tint = const Color(0xFF3949AB);

    if (p.holdMine) {
      title = S.heldByYou;
      body = S.holdApprovedBody;
      action = TextButton(onPressed: busy ? null : onRelease, child: const Text(S.releaseHold));
    } else if (p.holdPending) {
      title = S.holdRequested;
      body = 'The uploader will decide. Other agents can still see the profile until then.';
      icon = Icons.hourglass_top_rounded;
      tint = const Color(0xFFEF6C00);
      action = TextButton(onPressed: busy ? null : onCancel, child: const Text(S.cancel));
    } else if (p.canEdit && p.isOnHold) {
      final by = p.heldBy;
      title = by == null
          ? S.onHold
          : '${S.onHold} · ${[by.fullName, by.agencyName].whereType<String>().where((s) => s.isNotEmpty).join(', ')}';
      body = by?.since == null
          ? S.holdApprovedBody
          : '${S.holdApprovedBody} Since ${formatDate(by!.since)}.';
      action = TextButton(onPressed: busy ? null : onRelease, child: const Text(S.releaseHold));
    } else if (p.canEdit && p.pendingHoldRequests > 0) {
      final n = p.pendingHoldRequests;
      title = '$n hold ${n == 1 ? 'request' : 'requests'} ${S.holdPendingApproval}';
      body = 'Approve or reject them from the Requests tab.';
      icon = Icons.hourglass_top_rounded;
      tint = const Color(0xFFEF6C00);
    } else if (p.holdRequestStatus == 'rejected' && p.status == ProfileStatus.active) {
      title = S.holdRejected;
      body = 'You can ask again if things change.';
      icon = Icons.info_outline_rounded;
      tint = scheme.outline;
      action = TextButton(onPressed: busy ? null : onRequest, child: const Text(S.requestHold));
    }
    if (title == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tint.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 20, color: tint),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleSmall?.copyWith(color: tint)),
                  if (body != null) ...[
                    const SizedBox(height: 3),
                    Text(body, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
            ?action,
          ],
        ),
      ),
    );
  }
}

/// The contact block — the visible half of CLAUDE.md rule 4.
class _ContactSection extends StatelessWidget {
  const _ContactSection({required this.profile, required this.busy, required this.onRequest});

  final Profile profile;
  final bool busy;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget shell({required Color background, Color? border, required List<Widget> children}) =>
        SurfaceCard(
          color: background,
          borderColor: border ?? Colors.transparent,
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
        );

    if (profile.contactAccess == ContactAccess.granted) {
      final days = profile.contactDaysLeft;
      bool has(String? s) => s != null && s.isNotEmpty;
      return shell(
        background: AppColors.navyTint.withValues(alpha: 0.55),
        border: AppColors.navyTint,
        children: [
          Row(
            children: [
              Icon(Icons.lock_open_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Text(S.personalDetails, style: theme.textTheme.titleSmall),
              const Spacer(),
              if (days != null && !profile.isMine)
                StatusChip(
                  label: days <= 0 ? 'Expired' : '$days days left',
                  color: days <= 3 ? const Color(0xFFEF6C00) : const Color(0xFF2E7D32),
                  icon: Icons.schedule_rounded,
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Everything below is PROTECTED (SPEC §9.8) — omitted by the server
          // otherwise. Order: places, contacts, family, property.
          if (profile.nativePlace != null)
            DetailRow(label: S.nativePlace, value: profile.nativePlace!),
          if (profile.birthPlaceLine != null)
            DetailRow(label: S.birthPlace, value: profile.birthPlaceLine!),
          if (has(profile.workPlace)) DetailRow(label: S.workPlace, value: profile.workPlace!),
          if (profile.nriPlaceLabel != null)
            DetailRow(label: S.nriPlace, value: profile.nriPlaceLabel!),
          if (has(profile.fatherName)) DetailRow(label: S.fatherName, value: profile.fatherName!),
          if (has(profile.fatherOccupation))
            DetailRow(label: S.fatherOccupation, value: profile.fatherOccupation!),
          if (has(profile.fatherPhone))
            _PhoneRow(label: S.fatherPhone, phone: profile.fatherPhone!),
          if (has(profile.motherName)) DetailRow(label: S.motherName, value: profile.motherName!),
          if (has(profile.motherOccupation))
            DetailRow(label: S.motherOccupation, value: profile.motherOccupation!),
          if (has(profile.motherPhone))
            _PhoneRow(label: S.motherPhone, phone: profile.motherPhone!),
          if (has(profile.contactName))
            DetailRow(label: S.contactPersonName, value: profile.contactName!),
          if (has(profile.contactPhone))
            _PhoneRow(label: S.contactPersonPhone, phone: profile.contactPhone!),
          // Siblings: the breakdown when recorded, else the plain count.
          if (profile.siblingsBreakdown != null)
            DetailRow(label: S.siblings, value: profile.siblingsBreakdown!)
          else if (profile.siblingsLabel != null)
            DetailRow(label: S.siblings, value: profile.siblingsLabel!),
          if (has(profile.siblingsDetails))
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 2, 0, 8),
              child: Text(
                profile.siblingsDetails!,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
            ),
          if (has(profile.propertyShare))
            DetailRow(label: S.propertyShare, value: profile.propertyShare!),
          if (has(profile.propertyDetails))
            DetailRow(label: S.propertyDetails, value: profile.propertyDetails!),
          if (has(profile.familyDetails)) ...[
            const SizedBox(height: 6),
            Text(S.familyDetails, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.outline)),
            const SizedBox(height: 4),
            Text(
              profile.familyDetails!,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
          ],
          if (!profile.hasPersonalDetails)
            Text(
              S.noPersonalDetails,
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.outline),
            ),
        ],
      );
    }

    if (profile.contactAccess == ContactAccess.pending) {
      return shell(
        background: scheme.tertiaryContainer.withValues(alpha: 0.5),
        children: [
          Row(
            children: [
              Icon(Icons.hourglass_top_rounded, size: 18, color: scheme.onTertiaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(S.contactRequested, style: theme.textTheme.titleSmall),
              ),
              Icon(Icons.lock_rounded, size: 16, color: scheme.outline),
            ],
          ),
        ],
      );
    }

    final message = switch (profile.contactRequestStatus) {
      'rejected' => S.contactRejected,
      'revoked' => S.contactRevoked,
      'expired' => S.contactExpired,
      _ => S.contactHidden,
    };

    return shell(
      background: Colors.white,
      border: AppColors.rule,
      children: [
        Row(
          children: [
            Icon(Icons.lock_rounded, size: 18, color: scheme.outline),
            const SizedBox(width: 8),
            Text(S.personalDetails, style: theme.textTheme.titleSmall),
          ],
        ),
        const SizedBox(height: 8),
        Text(message, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.outline)),
        const SizedBox(height: 14),
        FilledButton.tonalIcon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.goldPale,
            foregroundColor: AppColors.navyDeep,
          ),
          onPressed: busy ? null : onRequest,
          icon: const Icon(Icons.lock_open_rounded, size: 18),
          label: const Text(S.requestContact),
        ),
      ],
    );
  }
}

class _PhoneRow extends StatelessWidget {
  const _PhoneRow({required this.phone, this.label = 'Phone'});

  final String phone;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
          ),
          Expanded(
            child: Text(
              phone,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy_rounded, size: 20),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: phone));
              showSnack(context, 'Phone number copied');
            },
          ),
          IconButton(
            tooltip: 'Call',
            icon: const Icon(Icons.call_rounded, size: 20),
            onPressed: () => launchUrl(Uri.parse('tel:$phone')),
          ),
        ],
      ),
    );
  }
}
