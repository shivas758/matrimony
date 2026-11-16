import 'customer.dart';
import 'profile.dart';

/// Where publishing my profile stands (SPEC §9.23 C / F): the family fills
/// in the profile first, then 1 chooses the agent → 2 pays ₹150 (or uses a
/// gift code) → 3 the agent approves → live. Payment and approval may happen
/// in either order; a gift code does all three at once.
enum PublishStep {
  agent,
  payment,
  approval,
  live;

  /// The step [customer] is on with [profile] (my profile row from
  /// `/customer/auth/me`; null falls back to the account's checklist).
  static PublishStep of(Customer customer, [ProfileSummary? profile]) => from(
        hasAgent: customer.agent != null,
        paid: profile?.paid ?? customer.unlock.paid,
        approved: customer.isActive,
      );

  /// No agent → [agent]; an agent but unpaid → [payment]; paid but the
  /// account not approved yet → [approval]; otherwise [live].
  static PublishStep from({required bool hasAgent, required bool paid, required bool approved}) {
    if (!hasAgent) return agent;
    if (!paid) return payment;
    if (!approved) return approval;
    return live;
  }
}

/// POST /customer/my-profiles/:id/gift-code {code} → {profile, customer}
/// (SPEC §9.23 B): the code is spent, the customer is linked to its agent if
/// they were not, approved, and the profile is paid and live.
class GiftCodeResult {
  const GiftCodeResult({required this.customer, this.profile});

  /// The refreshed account (same shape as `/customer/auth/me`'s customer).
  final Customer customer;

  /// My profile's own view after the redeem; null if the server left it out.
  final Profile? profile;

  factory GiftCodeResult.fromJson(Map<String, dynamic> j) => GiftCodeResult(
        customer: Customer.fromJson(j['customer'] as Map<String, dynamic>),
        profile: j['profile'] is Map<String, dynamic> ? Profile.fromJson(j['profile'] as Map<String, dynamic>) : null,
      );
}
