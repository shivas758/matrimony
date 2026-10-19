/// All user-facing text in one place so Telugu/Hindi can be added later
/// without touching screens (SPEC §9.11 — "Strings live in
/// customer_app/lib/ui/strings.dart"). Warm, simple words — no jargon.
class S {
  // ---- brand
  static const appTagline = 'MATRIMONY';
  static const appIntro = "Your agent's app for finding a match";

  // ---- phone screen
  static const phone = 'Mobile number';
  static const phoneTitle = 'Log in or sign up';
  static const phoneBody = 'We will send a one-time code to your mobile number. No password needed.';
  static const phoneInvalid = 'Enter your 10-digit mobile number';
  static const sendOtp = 'Send OTP';
  static const phoneFooter =
      'New here? Use the same button — we will only ask for your name next.';

  // ---- OTP screen
  static const otpTitle = 'Enter the code';
  static const otpSentTo = 'We sent a 6-digit code to';
  static const otpCode = 'One-time code';
  static const otpInvalidLength = 'Enter the 6-digit code';
  static const verify = 'Verify';
  static const resendOtp = 'Resend code';
  static String resendIn(int seconds) => 'Resend code in ${seconds}s';
  static String testModeHint(String code) => 'Test mode — enter $code';
  static const testModeTap = 'Tap to fill it in';
  static const changeNumber = 'Change number';
  static const otpResent = 'A new code has been sent';

  // ---- signup
  static const signupTitle = 'Create your account';
  static const signupBody =
      'This number is new to MILI. Tell us your name and start looking around.';
  static const yourNumber = 'Your number';
  static const fullName = 'Full name';
  static const fullNameHelper = 'As the family knows you';
  static const fullNameInvalid = 'Enter your full name';
  static const agentPhone = "Agent's mobile number";
  static const agentPhoneHelper = 'Ask your marriage bureau agent for their number';
  static const agentPhoneInvalid = "Enter your agent's 10-digit mobile number";
  static const createAccount = 'Create account';
  static const startAgain = 'Start again';
  static const signupNote =
      'You can browse as a guest straight away. To open profiles, choose your agent, register a profile and pay the registration fee.';

  // ---- waiting / pending / rejected / suspended
  static const pendingTitle = 'Waiting for approval';
  static String pendingBody(String agent) =>
      '$agent needs to approve your account before you can browse profiles.';
  static const pendingBodyNoAgent =
      'Your agent needs to approve your account before you can browse profiles.';
  static const pendingHint = 'Meanwhile, fill in your profile so your agent can get started. '
      'Pull down to check again.';
  static const rejectedTitle = 'Account not approved';
  static const rejectedBody =
      'Your agent did not approve this account. Please call them to sort it out.';
  static const suspendedTitle = 'Account suspended';
  static const suspendedBody = 'Your account has been suspended. Please contact your agent.';
  static const checkAgain = 'Check again';
  static const completeProfile = 'Complete your profile';
  static const editMyProfile = 'Edit my profile';
  static const yourAgent = 'Your agent';
  static const call = 'Call';
  static const callFailed = 'Could not open the phone dialler';
  static const statusChecked = 'Status checked';

  // ---- navigation
  static const browse = 'Browse';
  static const interested = 'Interested';
  static const myProfile = 'My profile';
  static const more = 'More';

  // ---- more screen
  static const myAgent = 'My agent';
  static const agency = 'Agency';
  static const city = 'City';
  static const communities = 'Communities';
  static const changeAgent = 'Change agent';
  static const changeAgentHint = 'Your current agent has to approve the move.';
  static String changeAgentPending(String name) => 'Waiting for approval to move to $name';
  static const logout = 'Logout';
  static const logoutConfirm = 'You will need a new one-time code to log in again.';
  static const version = 'v2.0';
  static const accountStatus = 'Account';

  // ---- customer statuses
  static const statusGuest = 'Guest';
  static const statusPending = 'Waiting for approval';
  static const statusActive = 'Active';
  static const statusRejected = 'Not approved';
  static const statusSuspended = 'Suspended';

  // ---- interest statuses (SPEC §9.4)
  static String interestStatusLabel(String status) => switch (status) {
        'pending' => 'Waiting for reply',
        'accepted' => 'Details shared',
        'declined' => 'Declined',
        'withdrawn' => 'Withdrawn',
        'revoked' => 'Access ended',
        'expired' => 'Expired',
        _ => status,
      };
  static String daysLeft(int days) => days == 1 ? '1 day left' : '$days days left';

  /// Short chip text for the Interested list: Waiting / Details shared · N days / …
  static String interestChip(String status, int? daysLeft) => switch (status) {
        'pending' => 'Waiting',
        'accepted' => daysLeft == null
            ? 'Details shared'
            : 'Details shared · $daysLeft ${daysLeft == 1 ? 'day' : 'days'}',
        'declined' => 'Declined',
        'withdrawn' => 'Withdrawn',
        'revoked' => 'Access ended',
        'expired' => 'Expired',
        _ => status,
      };

  // ---- browse
  static const searchHint = 'Search by name';
  static const filters = 'Filters';
  static const clearAll = 'Clear all';
  static const apply = 'Show matches';
  static String matchesCount(int n) => n == 1 ? '1 profile' : '$n profiles';
  static const noProfiles = 'No profiles yet';
  static const noProfilesHint =
      'Your agent has not added matching profiles yet. Check back in a few days.';
  static const noMatches = 'No profiles match';
  static const noMatchesHint = 'Try fewer filters or a wider age range.';
  static const profileRequiredTitle = 'Complete your profile first';
  static const profileRequiredBody =
      'We need your details before we can show you matching profiles.';
  static const fillMyDetails = 'Fill in my details';
  static const ageRange = 'Age';
  static const heightRange = 'Height';
  static const any = 'any';
  static const nriOnly = 'Living abroad (NRI) only';
  static const nriOnlyOn = 'Pick one or more countries below, or leave it as any';
  static const nriOnlyOff = 'Profiles living or working abroad';
  static const anyCountry = 'Any country';
  static const worksIn = 'Works in';
  static const place = 'Place';
  static const placeHint = 'Town or city';
  static const sortBy = 'Sort by';
  static const sortNewest = 'Newest first';
  static const sortOldest = 'Oldest first';
  static const sortName = 'Name (A–Z)';
  static const sortAgeAsc = 'Age (young to old)';
  static const sortAgeDesc = 'Age (old to young)';
  static const interestedChip = 'Interested';
  static const yearsShort = 'yrs';

  // ---- profile detail
  static const personal = 'Personal';
  static const educationCareer = 'Education & career';
  static const horoscope = 'Horoscope';
  static const rasi = 'Rasi';
  static const nakshatram = 'Star (nakshatram)';
  static const educationLevels = 'Education by level';
  static const highestQualification = 'Highest qualification';
  static const interestHintTitle = 'Like this profile?';
  static const interestHintBody =
      "Tap I'm interested. Your agent will speak to the other family's agent — nothing goes to the family directly.";
  static const imInterested = "I'm interested";
  static const interestNoteTitle = 'Add a note?';
  static const interestNoteBody =
      'Your agent will see this note when they follow up. It is optional.';
  static const interestNoteHint = 'e.g. Family is in Guntur, happy to meet';
  static const sendInterest = 'Send';
  static const interestSent = 'Interest sent';
  static const interestSentBody =
      "Your agent will follow up with the other family's agent. We will show their details here once they agree.";
  static const withdraw = 'Withdraw';
  static const withdrawConfirmTitle = 'Withdraw your interest?';
  static const withdrawConfirmBody =
      'Your agent will stop following this up. You can express interest again later.';
  static const withdrawnSnack = 'Interest withdrawn';
  static const detailsShared = 'Details shared with you';
  static const detailsSharedBody =
      'The other family agreed to share these details. They stay visible for a limited time.';
  static const notTakenForward = 'Not taken forward';
  static const notTakenForwardBody =
      'The other family did not take this forward. You can express interest again if things change.';
  static const withdrawnTitle = 'You withdrew this interest';
  static const withdrawnBody = 'You can express interest again whenever you like.';
  static const accessEndedTitle = 'Details no longer shared';
  static const accessEndedBody =
      'The other family stopped sharing their details. You can express interest again.';
  static const expiredTitle = 'Sharing period is over';
  static const expiredBody =
      'The shared details are hidden again after 15 days. You can express interest again.';
  static const expressAgain = 'Express interest again';
  static const sharedDetailsTitle = 'Family & contact details';
  static const noPersonalDetails = 'Nothing more has been recorded yet.';
  static const sharedOnlyAfterApproval =
      'Family, contact and place details are shown to another family only after your agent approves their interest.';
  static const contactPerson = 'Contact person';
  static const birthDetails = 'Birth details';
  static const father = 'Father';
  static const mother = 'Mother';
  static const copyNumber = 'Copy';
  static const numberCopied = 'Number copied';

  // ---- interests screen
  static const noInterests = 'No interests yet';
  static const noInterestsHint =
      'Tap "I\'m interested" on a profile you like. Your agent takes it forward from there.';
  static String sentOn(String date) => 'Sent on $date';
  static const viewProfile = 'View profile';

  // ---- my profile
  static const myProfileIntroTitle = 'Tell us about yourself';
  static const myProfileIntroBody =
      'Fill in the registration form once. Your agent uses it to find matches. Other families see only the public part.';
  static const myProfileIntroPending =
      'You can do this while you wait for your agent\'s approval.';
  static const profileSaved = 'Profile saved';
  static const edit = 'Edit';
  static const managePhotos = 'Photos';
  static const makePrimary = 'Make main photo';
  static const primaryPhoto = 'Main photo';
  static const removePhoto = 'Remove photo';
  static const removePhotoBody = 'This photo will be deleted from your profile.';
  static const addPhotos = 'Add photos';
  static String maxPhotos(int n) => 'You can add up to $n photos';
  static const photosAdded = 'Photos added';
  static const photoRemoved = 'Photo removed';
  static const primarySet = 'Main photo updated';
  static const noPhotosYet = 'No photos yet. Add a clear, recent photo — families look at it first.';
  static const profileHiddenNote =
      'Your profile becomes visible to other families once your agent approves your account.';
  static const profileVisibleNote =
      'Other families see only the public part. Family, contact and place details are shared only after your agent approves an interest.';
  static const profilePublicSection = 'What other families see';
  static const profilePrivateSection = 'Shared only after approval';

  // ---- profile form (the paper form's order — SPEC §9.11 item 5)
  static const newProfileTitle = 'Register a profile';
  static const editProfileTitle = 'Edit profile';
  static const basicDetails = 'Basic details';
  static const communitySection = 'Community';
  static const appearance = 'Appearance & lifestyle';
  static const educationSection = 'Education';
  static const professional = 'Work & income';
  static const family = 'Family';
  static const property = 'Property';
  static const nameRequired = 'Enter your full name';
  static const dobRequired = 'Select your date of birth';
  static const communityRequired = 'Select your community';
  static const selectDate = 'Select date';
  static const selectTime = 'Select time';
  static const selectHeight = 'Select height';
  static const clear = 'Clear';
  static const feet = 'Feet';
  static const inches = 'Inches';
  static const heightPickerTitle = 'Your height';
  static const weightHint = '25–250';
  static const subcasteHint = 'Type to search or add';
  static const subcasteNeedsCommunity = 'Select a community first';
  static const subcasteNew = 'New — will be added when you save';
  static const nativeCity = 'Native place — city';
  static const nativeState = 'State';
  static const educationLevelsHint = 'Fill in the levels that apply. Leave the rest empty.';
  static const educationLevelDetailsHint = 'School / college, year';
  static const country = 'Country';
  static const otherEducation = 'Other education details';
  static const occupation = 'Occupation';
  static const salary = 'Salary / income';
  static const salaryHint = 'e.g. 8 LPA';
  static const otherIncomeHint = 'e.g. rent, farm, family business';
  static const otherProfessional = 'Other work details';
  static const otherProfessionalHint = 'Employer, designation';
  static const workPlaceHint = 'Town / city where you work or live now';
  static const nriSwitch = 'Lives or works abroad (NRI)';
  static const nriPlaceHint = 'e.g. New Jersey, Dubai, Melbourne';
  static const hasSiblings = 'Brothers and sisters';
  static const familyDetailsHint = 'A few lines about the family';
  static const propertyShareHint = 'e.g. Equal share with brother';
  static const propertyDetailsHint = 'House, land, other assets';
  static const aboutHint = 'A few lines about yourself';
  static const onRequestNote =
      'Family, contact and place details are shared with another family only after your agent approves their interest.';
  static const saveProfile = 'Save my profile';
  static const saveChanges = 'Save changes';
  static const gothramHint = 'e.g. Bharadwaja';
  static const occupationHint = 'e.g. Farmer, Retired teacher';

  // ---- change agent
  static const changeAgentExplain =
      'Your current agent must approve the change. Your profile moves with you.';
  static const changeAgentPendingTitle = 'Waiting for approval';
  static const changeAgentPendingBody =
      'Your current agent will approve or reject this. Until then nothing changes.';
  static const cancelRequest = 'Cancel request';
  static const cancelRequestBody =
      'Your request to move will be withdrawn. You stay with your current agent.';
  static const requestCancelled = 'Request cancelled';
  static const agentDirectory = 'Find an agent';
  static const searchAgents = 'Search by name or agency';
  static const cityFilterHint = 'Filter by city';
  static const allCommunities = 'All communities';
  static const noAgents = 'No agents found';
  static const noAgentsHint = 'Try a different name, city or community.';
  static String moveTo(String name) => 'Move to $name?';
  static String moveToBody(String name) =>
      'Your current agent has to approve this. Once approved, $name becomes your agent and your profile moves with you.';
  static const changeNoteHint = 'Why do you want to move? (optional)';
  static const sendRequest = 'Send request';
  static const requestSent = 'Request sent — your current agent will decide';
  static const pastRequests = 'Past requests';
  static const newAgent = 'New agent';
  static const currentAgentChip = 'Current';
  static String requestStatusLabel(String status) => switch (status) {
        'pending' => 'Waiting',
        'approved' => 'Approved',
        'rejected' => 'Not approved',
        'cancelled' => 'Cancelled',
        _ => status,
      };
  static String requestLine(String from, String to) => '$from → $to';

  // ---- profile field labels (shared by the detail and form screens)
  static const gender = 'Gender';
  static const bride = 'Bride';
  static const groom = 'Groom';
  static const age = 'Age';
  static const dob = 'Date of birth';
  static const height = 'Height';
  static const weight = 'Weight';
  static const complexion = 'Complexion';
  static const maritalStatus = 'Marital status';
  static const religion = 'Religion';
  static const community = 'Community';
  static const subcaste = 'Subcaste';
  static const gothram = 'Gothram';
  static const motherTongue = 'Mother tongue';
  static const knownLanguages = 'Languages known';
  static const foodHabit = 'Food habit';
  static const nationality = 'Nationality';
  static const education = 'Education';
  static const educationDetails = 'Education details';
  static const profession = 'Profession';
  static const professionDetails = 'Profession details';
  static const occupationType = 'Occupation type';
  static const workCountry = 'Work country';
  static const workPlace = 'Work place';
  static const income = 'Income';
  static const otherIncome = 'Other income';
  static const nri = 'NRI';
  static const nriCountry = 'Country';
  static const nriPlace = 'Place abroad';
  static const starRasi = 'Star / Rasi';
  static const birthTime = 'Birth time';
  static const birthPlace = 'Birth place';
  static const birthState = 'Birth state';
  static const birthCountry = 'Birth country';
  static const nativePlace = 'Native place';
  static const fatherName = "Father's name";
  static const fatherOccupation = "Father's occupation";
  static const fatherPhone = "Father's phone";
  static const motherName = "Mother's name";
  static const motherOccupation = "Mother's occupation";
  static const motherPhone = "Mother's phone";
  static const contactPersonName = 'Contact person';
  static const contactPersonPhone = 'Contact phone';
  static const siblings = 'Siblings';
  static const siblingsDetails = 'About brothers and sisters';
  static const elderSisters = 'Elder sisters';
  static const youngerSisters = 'Younger sisters';
  static const elderBrothers = 'Elder brothers';
  static const youngerBrothers = 'Younger brothers';
  static const familyDetails = 'Family details';
  static const propertyShare = 'Property share';
  static const propertyDetails = 'Property details';
  static const about = 'About';
  static const photos = 'Photos';
  static const yes = 'Yes';
  static const no = 'No';
  static const notRecorded = 'Not recorded';
  static const none = 'None';

  // ---- friendly error text by API code (SPEC §9.1 / §9.3 / §9.9)
  static const errInvalidOtp = 'That code is not correct. Please check and try again.';
  static const errOtpExpired = 'That code has expired. Ask for a new one.';
  static const errTooManyAttempts = 'Too many wrong attempts. Ask for a new code.';
  static const errOtpCooldown = 'Please wait a little before asking for another code.';
  static const errOtpLimit = 'Too many codes requested. Please try again after an hour.';
  static const errPhoneNotVerified = 'Your number check has expired. Please start again.';
  static const errPhoneTaken = 'This number is already registered. Log in with it instead.';
  static const errAgentNotFound = 'No agent found with that mobile number. Check with your agent.';
  static const errAgentNotActive = "That agent's account is not active yet. Check with your agent.";
  static const errNetwork = 'Cannot reach the server. Check your internet connection.';
  static const errAccountPending = 'Your account is waiting for your agent\'s approval.';
  static const errAccountRejected = 'Your account was not approved. Please contact your agent.';
  static const errAccountSuspended = 'Your account has been suspended. Please contact your agent.';
  static const errProfileRequired = 'Fill in your profile first so we can show you matches.';
  static const errAlreadyPending = 'Your agent is already following this up.';
  static const errAlreadyAccepted = 'This family has already shared their details with you.';
  static const errOwnProfile = 'This is your own profile.';
  static const errWrongStatus = 'This has already been decided. Pull down to refresh.';
  static const errSameAgent = 'That is already your agent.';
  static const errProfileExists = 'You already have a profile — edit it instead.';
  static const errNoProfile = 'Fill in your profile first.';
  static const errTooManyPhotos = 'A profile can have at most 8 photos.';
  static const errNoPhotos = 'Pick at least one photo.';
  static const errProfileNotFound = 'This profile is no longer available.';
  static const errValidation = 'Please check the details and try again.';
  static const errUnlockRequired =
      'Choose your agent, register a profile and pay the registration fee to open profiles.';
  static const errAgentRequired = 'Choose your agent first.';
  static const errProfileLimit = 'You have already registered your profile — each account has one.';
  static const errAlreadyPaid = 'This profile is already paid for.';
  static const errFromProfileRequired = 'Choose which of your profiles is interested.';
  static const errNoMatchingProfile =
      'None of your live profiles can express interest in this profile.';
  static const errInvalidFromProfile = 'Pick one of your live profiles.';
  static const errApprovalRequired =
      'This profile is paid for — ask your agent to delete it (Request deletion).';
  static const errNotPaid = 'This profile is not paid for yet — you can delete it straight away.';
  static const errPaymentUnsupported = 'Online payment is coming soon — contact your agent.';
  static const errPaymentVerification = 'We could not verify this payment. Please contact your agent.';

  // ---- guest mode / Get started (SPEC §9.12)
  static const guestBannerTitle = 'You are browsing as a guest — register to open profiles';
  static const getStarted = 'Get started';
  static const getStartedTitle = 'Open full profiles';
  static const getStartedIntro =
      'Four steps to see full profiles, express interest and let your agent take it forward.';
  static const lockedProfile = 'Locked';
  static const step1Title = 'Choose your agent';
  static const step1Body = "Enter your marriage bureau agent's mobile number, or pick one from the list.";
  static const step2Title = 'Register your profile';
  static const step2Body = 'Fill in the registration form for the bride or groom.';
  static String step3Title(num? fee) => 'Pay ${feeLabel(fee)}';
  static String step3Body(num? fee) =>
      'A one-time registration fee of ${feeLabel(fee)}. Your profile is shown to other families only after this.';
  static const step4Title = 'Agent approval';
  static String step4Waiting(String agent) => 'Waiting for $agent to approve your account.';
  static const step4WaitingNoAgent = 'Your agent approves your account after you choose them.';
  static const step4Rejected =
      'Your agent did not approve this account. Call them, or choose a different agent above.';
  static const step4Done = 'Your agent approved your account.';
  static const allSetTitle = 'You are all set';
  static const allSetBody = 'You can now open full profiles and express interest.';
  static const startBrowsing = 'Start browsing';
  static const agentPhoneLink = 'Link agent';
  static const pickFromDirectory = 'Pick from directory';
  static const change = 'Change';
  static const agentLinkedSnack = 'Agent chosen — they will approve your account';
  static const profileRegistered = 'Profile registered';
  static const allPaid = 'Registration fee paid';
  static const needAgentFirst = 'Choose your agent first (step 1).';
  static const needProfileFirst = 'Register your profile first (step 2).';
  static const chooseYourAgent = 'Choose your agent';
  static const chooseYourAgentBody =
      'Your agent registers your profile with the bureau and takes interests forward for you.';
  static String chooseAgentConfirm(String name) => 'Choose $name?';
  static String chooseAgentConfirmBody(String name) =>
      '$name will be your agent. They approve your account and follow up interests for you. Your profile moves to them.';
  static const choose = 'Choose';
  static const chooseAgentExplain =
      'Pick the marriage bureau agent you want to work with. They approve your account.';
  static const lockedInterestsTitle = 'Interests open after registration';
  static const lockedInterestsBody =
      'Choose your agent, register a profile and pay the registration fee. Once your agent approves you, you can express interest.';
  static const lockedDetailTitle = 'This profile is locked';

  // ---- my profile (SPEC §9.12, one per account since §9.17)
  static const addProfile = 'Create profile';
  static const addProfileNeedsAgent = 'Choose your agent first — tap Get started.';
  static const noProfilesYetTitle = 'Register your profile';
  static const noProfilesYetBody =
      'Fill in the registration form for the bride or groom. Each account registers one profile.';
  static String chipPay(num? fee) => 'Pay ${feeLabel(fee)}';
  static const chipWaitingForAgent = 'Waiting for agent';
  static const chipLive = 'Live';
  static const chipHidden = 'Hidden';
  static String visibilityTitle(String? visibility) => switch (visibility) {
        'payment_pending' => 'Registration fee not paid',
        'awaiting_approval' => 'Waiting for your agent',
        'live' => 'Live — other families can see it',
        _ => 'Hidden',
      };
  static String visibilityNote(String? visibility) => switch (visibility) {
        'payment_pending' => 'Pay the registration fee so this profile can be shown to other families.',
        'awaiting_approval' => 'Paid. It goes live once your agent approves your account.',
        'live' =>
          'Other families see only the public part. Family, contact and place details are shared only after your agent approves an interest.',
        _ => 'Your agent has hidden this profile for now. Call them to know more.',
      };
  static const deleteProfile = 'Delete profile';
  static const deleteProfileBody =
      'This profile and its photos will be deleted. A profile can be deleted only before it is paid for.';
  static const delete = 'Delete';
  static const profileDeleted = 'Profile deleted';
  static const requestDeletion = 'Request deletion';
  static const requestDeletionBody =
      'This profile is paid for, so your agent has to approve deleting it. Tell them why (optional).';
  static const deletionReasonHint = 'Reason (optional)';
  static const deletionRequestedSnack = 'Request sent — your agent will decide';
  static const deletionRequestedTitle = 'Deletion requested — waiting for your agent';
  static const deletionRequestedBody =
      'Your agent will approve or reject this. Until then the profile stays as it is.';
  static const deletionRequestCancelled = 'Deletion request cancelled';
  static const chipDeleteRequested = 'Delete requested';
  static const profileGone = 'This profile has been deleted';
  static const onBehalfOf = 'On behalf of';
  static const onBehalfOfBody = 'Which of your profiles is interested?';
  static String forProfile(String name) => 'for $name';

  // ---- checkout (mock now, Razorpay later)
  static const checkoutTitle = 'Registration fee';
  static String checkoutFor(String name) => 'For the profile of $name';
  static const checkoutWhat =
      "One-time registration fee. After payment and your agent's approval, your profile is shown to other families.";
  static const testModeNoCharge = 'Test mode — no money is charged';
  static String payFee(num? fee) => 'Pay ${feeLabel(fee)}';
  static const simulateFailure = 'Simulate failure';
  static const paymentComingSoon = 'Online payment is coming soon — contact your agent.';
  static const paymentSuccessTitle = 'Payment successful';
  static const paymentLiveNow = 'Live now — other families can see this profile.';
  static const paymentAwaitingApproval =
      "Waiting for your agent's approval — the profile goes live once they approve.";
  static const paymentFailedTitle = 'Payment failed';
  static const paymentFailedBody = 'No money was taken. You can try again.';
  static const tryAgain = 'Try again';
  static const amount = 'Amount';

  /// "₹150" (or "₹150.50"); "the fee" when the server did not say.
  static String feeLabel(num? fee) {
    if (fee == null) return 'the fee';
    final whole = fee == fee.roundToDouble();
    return '₹${whole ? fee.toInt() : fee.toStringAsFixed(2)}';
  }

  // ---- blocked (suspended)
  static const blockedHint = 'Please call your agent to sort it out.';

  // ---- notifications (SPEC §9.15)
  static const notifications = 'Notifications';
  static const needsYourAction = 'Needs your action';
  static const updates = 'Updates';
  static const noNotifications = 'Nothing new';
  static const noNotificationsHint =
      "Payment reminders, your agent's decisions and replies to your interests show up here.";
  static const newDot = 'New';
  static const view = 'View';

  /// "Just now", "5 min ago", "3 h ago", "Yesterday", "4 days ago",
  /// "12 Sep 2026"; future times (an interest that ends soon) read "in 2 days".
  static String relativeTime(DateTime at, DateTime now) {
    final diff = now.difference(at);
    if (diff.isNegative) {
      final ahead = at.difference(now);
      if (ahead.inMinutes < 1) return 'Just now';
      if (ahead.inMinutes < 60) return 'in ${ahead.inMinutes} min';
      if (ahead.inHours < 24) return 'in ${ahead.inHours} h';
      final days = (ahead.inHours / 24).ceil();
      return days == 1 ? 'in 1 day' : 'in $days days';
    }
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    final days = today.difference(day).inDays;
    if (days == 0) return '${diff.inHours} h ago';
    if (days == 1) return 'Yesterday';
    if (days < 7) return '$days days ago';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${at.day} ${months[at.month - 1]} ${at.year}';
  }

  // ---- generic
  static const retry = 'Retry';
  static const cancel = 'Cancel';
  static const close = 'Close';
  static const confirm = 'Confirm';
  static const ok = 'OK';
  static const save = 'Save';
  static const done = 'Done';
  static const remove = 'Remove';
  static const loading = 'Loading…';
  static const somethingWrong = 'Something went wrong';

  // ---- photo editor + camera (SPEC §9.17)
  static const takePhoto = 'Take photo';
  static const takePhotoHint = 'Use the camera now';
  static const chooseFromGallery = 'Choose from gallery';
  static String chooseFromGalleryHint(int n) => n == 1 ? 'Pick 1 more photo' : 'Pick up to $n photos';
  static const photoEditHint = 'Each photo opens the editor next — crop and rotate it so it shows the way you want.';
  static const editPhoto = 'Edit photo';
  static const viewFullPhoto = 'View full photo';
}
