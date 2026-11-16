import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/profile.dart';
import '../../../services/api_client.dart';
import '../../../services/profile_service.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../browse/profile_detail_screen.dart';

/// "View as others see it" (SPEC §9.23 D): my profile exactly as another
/// family sees it, in two tabs — *Before interest is accepted* (public
/// fields, my switched-off details masked, no on-request block) and *After
/// interest is accepted* (everything, with the family & contact details).
/// Each tab loads GET /customer/my-profiles/:id/preview?as=before|after and
/// renders the normal profile page ([ProfileDetailView]) without the
/// interest, report and block actions, under the banner "Preview — this is
/// how other families see your profile". Opened from My profile.
class ProfilePreviewScreen extends StatelessWidget {
  const ProfilePreviewScreen({super.key, required this.profileId});

  final int profileId;

  static Future<void> open(BuildContext context, int profileId) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ProfilePreviewScreen(profileId: profileId)),
      );

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(S.previewTitle),
          bottom: const TabBar(
            tabs: [
              Tab(text: S.previewTabBefore),
              Tab(text: S.previewTabAfter),
            ],
          ),
        ),
        body: Column(
          children: [
            const _PreviewBanner(),
            Expanded(
              child: TabBarView(
                children: [
                  _PreviewTab(profileId: profileId, after: false),
                  _PreviewTab(profileId: profileId, after: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Preview — this is how other families see your profile".
class _PreviewBanner extends StatelessWidget {
  const _PreviewBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: const BoxDecoration(
        color: AppColors.goldLight,
        border: Border(bottom: BorderSide(color: AppColors.gold)),
      ),
      child: Row(
        children: [
          const Icon(Icons.visibility_outlined, size: 18, color: AppColors.wine),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              S.previewBanner,
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.wine, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// One tab: loads its preview once (kept while switching tabs).
class _PreviewTab extends StatefulWidget {
  const _PreviewTab({required this.profileId, required this.after});

  final int profileId;
  final bool after;

  @override
  State<_PreviewTab> createState() => _PreviewTabState();
}

class _PreviewTabState extends State<_PreviewTab> with AutomaticKeepAliveClientMixin {
  Profile? _profile;
  String? _error;
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

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
      final p = await context.read<ProfileService>().preview(widget.profileId, after: widget.after);
      if (mounted) setState(() => _profile = p);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = friendlyMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final p = _profile;
    if (p == null) {
      return _loading
          ? const Center(child: CircularProgressIndicator())
          : ErrorState(message: _error ?? S.somethingWrong, onRetry: _load);
    }
    return ProfileDetailView(
      profile: p,
      showBackButton: false,
      expandedHeight: 340,
      onRefresh: _load,
      footer: widget.after
          // What they see once their interest is accepted: the shared block.
          ? InterestBlock(profile: p, interest: p.interest)
          : const LockNote(text: S.previewBeforeNote),
    );
  }
}
