import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../config.dart';
import '../../../models/profile.dart';
import '../../../services/api_client.dart';
import '../../../services/profile_service.dart';
import '../../../state/auth_state.dart';
import '../../../state/masters_state.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/profile_sections.dart';
import '../payment/checkout_screen.dart';
import 'my_profiles_screen.dart';
import 'profile_form_screen.dart';

/// One of my profiles (SPEC §9.11 Gandharva 5 / §9.12): where it stands with
/// the fee and approval (with *Pay* while unpaid), the same cards as the
/// detail screen plus the on-request block (it is mine), Edit, photo
/// management, and *Delete* while it is still unpaid. A PAID profile can
/// only be deleted by the agent: *Request deletion* → banner with *Cancel
/// request* while it waits (SPEC §9.13). If the agent approved meanwhile
/// (404), it pops back to the list. [MyProfilesScreen] pushes it.
class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key, required this.profileId});

  final int profileId;

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  final _picker = ImagePicker();
  bool _photoBusy = false;
  bool _busy = false;
  bool _loading = true;
  String? _error;
  Profile? _profile;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MastersState>().load();
      _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await context.read<ProfileService>().myProfile(widget.profileId);
      if (mounted) setState(() => _profile = profile);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.status == 404 || e.code == 'profile_not_found') {
        // Deleted (the agent approved the deletion request) — back to the list.
        await _gone();
        return;
      }
      setState(() => _error = friendlyMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _gone() async {
    await context.read<AuthState>().refresh();
    if (!mounted) return;
    showSnack(context, S.profileGone);
    Navigator.of(context).pop();
  }

  Future<void> _openForm(Profile existing) async {
    final saved = await Navigator.of(context).push<Profile>(
      MaterialPageRoute(builder: (_) => ProfileFormScreen(existing: existing)),
    );
    if (saved == null || !mounted) return;
    setState(() => _profile = saved);
    showSnack(context, S.profileSaved);
    // Name / photo on the My profiles list.
    await context.read<AuthState>().refresh();
  }

  Future<void> _pay(Profile profile) async {
    final paid = await CheckoutScreen.open(context, profileId: profile.id, profileName: profile.fullName);
    if (!mounted) return;
    if (paid) await _load();
    if (mounted) await context.read<AuthState>().refresh();
  }

  Future<void> _delete(Profile profile) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(S.deleteProfile),
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
    if (ok != true || !mounted || _busy) return;
    setState(() => _busy = true);
    try {
      await context.read<ProfileService>().deleteProfile(profile.id);
      if (!mounted) return;
      await context.read<AuthState>().refresh();
      if (!mounted) return;
      showSnack(context, S.profileDeleted);
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyMessage(e), error: true);
      // Paid meanwhile (e.g. cash recorded by the agent) → show the right actions.
      if (e.code == 'approval_required') await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Paid profile: ask the agent to delete it, with an optional reason.
  Future<void> _requestDeletion(Profile profile) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(S.requestDeletion),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(S.requestDeletionBody),
            const SizedBox(height: 16),
            TextField(
              controller: reason,
              maxLength: 500,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: S.deletionReasonHint),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text(S.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text(S.sendRequest)),
        ],
      ),
    );
    final text = reason.text.trim();
    reason.dispose();
    if (ok != true || !mounted || _busy) return;
    await _runAction(() async {
      await context.read<ProfileService>().requestDeletion(profile.id, reason: text);
      if (mounted) showSnack(context, S.deletionRequestedSnack);
    });
  }

  Future<void> _cancelDeletion(DeleteRequest request) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(S.cancelRequest),
        content: const Text(S.deletionRequestedBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text(S.close)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text(S.cancelRequest)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _runAction(() async {
      await context.read<ProfileService>().cancelDeleteRequest(request.id);
      if (mounted) showSnack(context, S.deletionRequestCancelled);
    });
  }

  /// Runs a request, then re-reads this profile (its `delete_request`).
  /// `not_paid` / `already_pending` also just re-read — the screen then
  /// shows the right action.
  Future<void> _runAction(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, friendlyMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) await _load();
  }

  // ------------------------------------------------------------ photos

  Future<void> _runPhoto(Future<void> Function() action, String doneMessage) async {
    if (_photoBusy) return;
    setState(() => _photoBusy = true);
    try {
      await action();
      await _load();
      if (mounted) showSnack(context, doneMessage);
      // The list card shows the main photo.
      if (mounted) context.read<AuthState>().refresh();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, friendlyMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _addPhotos(Profile profile) async {
    final remaining = AppConfig.maxPhotos - profile.photos.length;
    if (remaining <= 0) {
      showSnack(context, S.maxPhotos(AppConfig.maxPhotos), error: true);
      return;
    }
    final picked = await _picker.pickMultiImage(imageQuality: 92, limit: remaining);
    if (picked.isEmpty || !mounted) return;
    final paths = picked.take(remaining).map((f) => f.path).toList();
    await _runPhoto(() => context.read<ProfileService>().addPhotos(profile.id, paths), S.photosAdded);
  }

  Future<void> _photoMenu(ProfilePhoto photo) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!photo.isPrimary)
              ListTile(
                leading: const Icon(Icons.star_rounded, color: AppColors.roseDark),
                title: const Text(S.makePrimary),
                onTap: () => Navigator.pop(ctx, 'primary'),
              ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: Theme.of(ctx).colorScheme.error),
              title: Text(S.removePhoto, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'primary') {
      await _runPhoto(() => context.read<ProfileService>().makePrimary(photo.id), S.primarySet);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(S.removePhoto),
        content: const Text(S.removePhotoBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text(S.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text(S.remove)),
        ],
      ),
    );
    if (ok == true && mounted) {
      await _runPhoto(() => context.read<ProfileService>().deletePhoto(photo.id), S.photoRemoved);
    }
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final fee = profile?.profileFeeInr ?? context.watch<AuthState>().customer?.profileFeeInr;
    final unpaid = profile != null && !profile.paid;

    return Scaffold(
      appBar: AppBar(
        title: Text(profile?.fullName ?? S.myProfile),
        actions: [
          if (profile != null)
            IconButton(
              tooltip: S.edit,
              icon: const Icon(Icons.edit_rounded),
              onPressed: () => _openForm(profile),
            ),
          if (profile != null && (unpaid || profile.deleteRequest == null))
            PopupMenuButton<String>(
              onSelected: (_) => unpaid ? _delete(profile) : _requestDeletion(profile),
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    unpaid ? S.deleteProfile : S.requestDeletion,
                    style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: _body(profile, fee),
      bottomNavigationBar: unpaid
          ? Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: AppColors.rule)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _pay(profile),
                    icon: const Icon(Icons.lock_rounded),
                    label: Text(S.payFee(fee)),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _body(Profile? profile, num? fee) {
    if (_loading && profile == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (profile == null) {
      return ErrorState(message: _error ?? S.somethingWrong, onRetry: _load);
    }

    final theme = Theme.of(context);
    final visibility = profile.visibility;
    final (icon, tint) = switch (visibility) {
      ProfileVisibility.paymentPending => (Icons.lock_rounded, AppColors.roseDark),
      ProfileVisibility.awaitingApproval => (Icons.hourglass_top_rounded, AppColors.warning),
      ProfileVisibility.live => (Icons.visibility_outlined, AppColors.success),
      _ => (Icons.visibility_off_outlined, theme.colorScheme.outline),
    };
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          if (profile.deleteRequest != null) ...[
            NoticeCard(
              icon: Icons.delete_outline_rounded,
              title: S.deletionRequestedTitle,
              body: S.deletionRequestedBody,
              tint: theme.colorScheme.error,
              action: OutlinedButton.icon(
                onPressed: _busy ? null : () => _cancelDeletion(profile.deleteRequest!),
                icon: _busy ? const ButtonSpinner(color: AppColors.maroon) : const Icon(Icons.close_rounded),
                label: const Text(S.cancelRequest),
              ),
            ),
            const SizedBox(height: 12),
          ],
          NoticeCard(
            icon: icon,
            title: S.visibilityTitle(visibility?.apiValue),
            body: S.visibilityNote(visibility?.apiValue),
            tint: tint,
          ),
          const SizedBox(height: 16),
          SectionHeader(
            S.photos,
            trailing: TextButton.icon(
              onPressed: _photoBusy ? null : () => _addPhotos(profile),
              icon: const Icon(Icons.add_a_photo_outlined, size: 18),
              label: const Text(S.addPhotos),
            ),
          ),
          _PhotoManager(
            photos: profile.photos,
            busy: _photoBusy,
            onTapPhoto: _photoMenu,
            onAdd: () => _addPhotos(profile),
          ),
          const SizedBox(height: 16),
          ProfileChipRow(
            profile: profile,
            trailing: [VisibilityChip(visibility: visibility, fee: fee)],
          ),
          const SizedBox(height: 16),
          ProfileFactGrid(profile: profile),
          const SizedBox(height: 20),
          ProfilePublicCards(profile: profile),
          const SectionHeader(S.profilePrivateSection),
          SharedDetailsCard(profile: profile, own: true),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => _openForm(profile),
            icon: const Icon(Icons.edit_rounded),
            label: const Text(S.edit),
          ),
          if (!profile.paid || profile.deleteRequest == null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _busy ? null : () => profile.paid ? _requestDeletion(profile) : _delete(profile),
              style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
              icon: const Icon(Icons.delete_outline_rounded),
              label: Text(profile.paid ? S.requestDeletion : S.deleteProfile),
            ),
          ],
        ],
      ),
    );
  }
}

/// Horizontal strip of my photos; tap one for Make main photo / Remove.
class _PhotoManager extends StatelessWidget {
  const _PhotoManager({
    required this.photos,
    required this.busy,
    required this.onTapPhoto,
    required this.onAdd,
  });

  final List<ProfilePhoto> photos;
  final bool busy;
  final ValueChanged<ProfilePhoto> onTapPhoto;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    final theme = Theme.of(context);
    if (photos.isEmpty) {
      return SurfaceCard(
        child: Row(
          children: [
            const Icon(Icons.photo_camera_outlined, color: AppColors.maroonLight),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                S.noPhotosYet,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
          ],
        ),
      );
    }
    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final photo = photos[i];
          return InkWell(
            onTap: busy ? null : () => onTapPhoto(photo),
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: AuthedPhoto(url: photo.absoluteUrl, api: api, width: 108, height: 132),
                ),
                if (photo.isPrimary)
                  const Positioned(
                    left: 6,
                    bottom: 6,
                    child: StatusChip(
                      label: S.primaryPhoto,
                      color: AppColors.roseDark,
                      icon: Icons.star_rounded,
                      solid: true,
                    ),
                  ),
                if (busy)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
