/// All user-facing text in one place so Telugu/Hindi can be added later
/// without touching screens (SPEC §9.11 — "Strings live in
/// customer_app/lib/ui/strings.dart"). Warm, simple words — no jargon.
class S {
  // ---- brand (SPEC §9.18 A: the app is "Wedbook Matrimony"; its full name
  // is AppConfig.appName, the wordmark reads "Wedbook" over "Matrimony")
  static const brandShort = 'Wedbook';
  static const appTagline = 'Matrimony';
  static const appIntro = "Your agent's app for finding a match";

  // ---- log in: mobile + password, the app's entry (SPEC §9.24 C)
  static const phone = 'Mobile number';
  static const phoneInvalid = 'Enter your 10-digit mobile number';
  static const loginTitle = 'Log in';
  static const loginBody = 'With your mobile number and password.';
  static const password = 'Password';
  static const passwordRequired = 'Enter your password';
  static const showPassword = 'Show password';
  static const hidePassword = 'Hide password';
  static const logIn = 'Log in';
  static const forgotPassword = 'Forgot password?';
  static const newHere = 'New here?';
  static const loginFooter =
      'Creating an account or resetting your password sends a one-time code to your mobile number.';
  static const errBadCredentials = 'Mobile number or password is incorrect';
  static const setPasswordFirst = "Set a password for this number first — we'll send you a code";

  // ---- the mobile number before a one-time code: Create account / Forgot password
  static const signupPhoneBody = 'We will send a one-time code to check that this number is yours.';
  static const resetPhoneTitle = 'Forgot password';
  static const resetPhoneBody =
      'Enter your registered mobile number. We will send a one-time code, then you choose a new password.';
  static const sendOtp = 'Send OTP';
  static const logInWithNumber = 'Log in with this number';
  static const errAccountNotFound = 'No account with this mobile number';

  // ---- passwords (6–100 characters, SPEC §9.24 C)
  static const passwordHelper = 'At least 6 characters';
  static const confirmPassword = 'Confirm password';
  static const passwordTooShort = 'Use at least 6 characters';
  static const passwordTooLong = 'Use at most 100 characters';
  static const passwordsDoNotMatch = 'Passwords do not match';

  // ---- Forgot password: the new password (SPEC §9.24 C)
  static const resetTitle = 'Choose a new password';
  static const resetBody = 'Your number is verified. Choose a new password — you are logged in straight after.';
  static const newPassword = 'New password';
  static const saveAndLogIn = 'Save and log in';

  // ---- More → Change password / Set a password (SPEC §9.24 C)
  static const changePassword = 'Change password';
  static const changePasswordHint = 'The password you log in with';
  static const changePasswordBody = 'Enter your current password, then the new one twice.';
  static const setPassword = 'Set a password';
  static const setPasswordHint = 'Log in with your mobile number and a password';
  static const setPasswordBody =
      'Choose a password. From now on you log in with your mobile number and this password.';
  static const currentPassword = 'Current password';
  static const errCurrentPasswordWrong = 'Current password is incorrect';
  static const savePassword = 'Save password';
  static const passwordChanged = 'Password changed';
  static const passwordSet = 'Password set';

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

  // ---- Firebase phone verification (SPEC §9.19 A) — Firebase's error
  // codes in plain words (see phoneAuthMessage)
  static const otpVerifyingAuto = 'Verifying automatically…';
  static const otpCouldNotSend = 'Could not send the code. Please try again.';
  static const phoneAuthTooManyRequests = 'Too many attempts from this phone. Please try again later.';
  static const phoneAuthQuotaExceeded = 'The SMS limit for today has been reached. Please try again later.';
  static const phoneAuthInvalidNumber = 'Enter a valid 10-digit mobile number.';
  static const phoneAuthNotSetUp = 'Phone verification is not set up yet — please contact support.';
  static const phoneAuthFailed = 'Could not verify the number — please try again.';

  // ---- signup
  static const signupTitle = 'Create your account';
  static const signupBody =
      'Your number is verified. Tell us your name and choose a password — you log in to Wedbook Matrimony with your mobile number and this password.';
  static const yourNumber = 'Your number';
  static const fullName = 'Full name';
  static const fullNameHelper = 'As the family knows you';
  static const fullNameInvalid = 'Enter your full name';
  // One field takes either (SPEC §9.18 B / G).
  static const agentPhoneOrCode = "Agent's mobile number or agent code";
  static const agentPhoneOrCodeHint = '98765 43210 or KA1A';
  static const agentPhoneOrCodeHelper = 'Ask your marriage bureau agent for their number or their agent code';
  static const agentPhoneOrCodeInvalid =
      "Enter your agent's 10-digit mobile number, or their agent code (like KA1A)";
  static const createAccount = 'Create account';
  static const startAgain = 'Start again';
  static const signupNote =
      'You can browse as a guest straight away. To open profiles, create your profile and publish it: choose your agent and pay the registration fee (or use a gift code).';

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
  static const logoutConfirm = 'You can log in again with your mobile number and password.';
  static const version = 'v3.5.0';
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
  // A profile whose family switched some details off (SPEC §9.18 D).
  static const someDetailsHidden =
      'Some details are hidden — they are shared after your interest is accepted.';
  static const someDetailsHiddenShort = 'Some details hidden';
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

  // ---- profile form: four steps (SPEC §9.18 F)
  static const newProfileTitle = 'Register a profile';
  static const editProfileTitle = 'Edit profile';
  static const stepPersonal = 'Personal details';
  static const stepProfessional = 'Professional details';
  static const stepHoroscope = 'Horoscope';
  static const stepFamily = 'Family & contact';

  /// The short labels under the numbered circles of the step header.
  static const stepPersonalShort = 'Personal';
  static const stepProfessionalShort = 'Professional';
  static const stepHoroscopeShort = 'Horoscope';
  static const stepFamilyShort = 'Family & contact';
  static String stepOf(int step, int total) => 'Step $step of $total';
  static const next = 'Next';
  static const back = 'Back';
  static String stepHasErrors(String step) => 'Please check the marked details in "$step".';
  static const discardTitle = 'Leave without saving?';
  static const discardBody = 'You have changes that are not saved yet. They will be lost if you leave now.';
  static const discard = 'Leave';
  static const keepEditing = 'Keep editing';
  static const basicDetails = 'Basic details';
  static const communitySection = 'Community & language';
  static const appearance = 'Appearance & lifestyle';
  static const educationSection = 'Education';
  static const professional = 'Work & income';
  static const starSection = 'Star & gothram';
  static const parents = 'Parents';
  static const family = 'Family';
  static const property = 'Property';
  static const nativePlaceSection = 'Native place';
  static const afterApprovalOnly = 'Visible only after approval';
  static const birthPlaceNote = 'Birth place, state and country are visible only after approval.';
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
  static const searchAgents = 'Name, agency or agent code';
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
  static const errPhoneTaken = 'This number is already registered — log in with your password';
  static const errAgentNotFound = 'No agent found with that mobile number or code. Check with your agent.';
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
      'Create your profile and publish it — choose your agent and pay the registration fee or use a gift code — to open profiles.';
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
  // The order since v3.4.0 (SPEC §9.23 C / F): 1 Create your profile · 2 Choose
  // your agent · 3 Pay or use a gift code · 4 Agent approval.
  static const step1Title = 'Create your profile';
  static const step1Body =
      'Fill in the registration form for the bride or groom. Do it now — you choose your agent and pay when you publish it.';
  static const step2Title = 'Choose your agent';
  static const step2Body =
      "Enter your marriage bureau agent's mobile number or agent code, or pick one from the list.";
  static String step3Title(num? fee) => 'Pay ${feeLabel(fee)} or use a gift code';
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
  static const needAgentFirst = 'Choose your agent first (step 2) — or use a gift code from an agent.';
  static const needProfileFirst = 'Create your profile first (step 1).';
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
      'Create your profile and publish it — choose your agent and pay the registration fee or use a gift code. Once your agent approves you, you can express interest.';
  static const lockedDetailTitle = 'This profile is locked';

  // ---- my profile (SPEC §9.12, one per account since §9.17)
  static const addProfile = 'Create profile';
  static const noProfilesYetTitle = 'Create your profile';
  static const noProfilesYetBody =
      'Fill in the registration form for the bride or groom — no agent needed yet. You choose your agent and pay when you publish it. Each account registers one profile.';
  static String chipPay(num? fee) => 'Pay ${feeLabel(fee)}';
  static const chipWaitingForAgent = 'Waiting for agent';
  static const chipLive = 'Live';
  static const chipHidden = 'Hidden';
  static String visibilityTitle(String? visibility) => switch (visibility) {
        'payment_pending' => 'Not published yet',
        'awaiting_approval' => 'Waiting for your agent',
        'live' => 'Live — other families can see it',
        _ => 'Hidden',
      };
  static String visibilityNote(String? visibility) => switch (visibility) {
        'payment_pending' =>
          'Publish it — choose your agent and pay the registration fee, or use a gift code — so other families can see it.',
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

  // ---- IDs and agent codes (SPEC §9.18 B / C)
  static const yourId = 'Your ID';
  static const idCopied = 'ID copied';
  static const tapToCopy = 'Tap to copy';
  static String idLine(String code) => 'ID $code';
  static const agentCode = 'Agent code';
  static String agentCodeLine(String code) => 'Agent code $code';
  static const agentCodeCopied = 'Agent code copied';

  // ---- privacy settings (SPEC §9.18 D / E)
  static const privacyTitle = 'Privacy settings';
  static const privacyIntro =
      'Choose what other families see before you approve them. Hidden details are shared only after you accept an interest or your agent approves a request.';
  static const privacyHeadline = 'You decide what others see';
  static const privacyAlwaysShown = 'Always shown';
  static const privacyAlwaysShownNote = 'Every family sees these — they cannot be hidden.';
  static const privacyShown = 'Shown to everyone';
  static const privacyHidden = 'Only after approval';
  static const privacyHiddenWithCommunity = 'Hidden together with your community';
  static const privacySearchNote = 'Hidden details cannot be used by others to find your profile.';
  static const privacyOtherSection = 'Other details';
  static String privacySectionTitle(String section) => switch (section) {
        'personal' => 'Personal',
        'professional' => 'Professional',
        'horoscope' => 'Horoscope',
        _ => privacyOtherSection,
      };
  static const audienceTitle = 'Show my profile to';
  static const audienceOwn = 'My community only';
  static String audienceOwnHint(String? community) => community == null || community.isEmpty
      ? 'Families of your own community'
      : 'Families of the $community community';
  static const audienceSelected = 'Selected communities';
  static const audienceSelectedHint = 'Your own community and the ones you pick';
  static const audienceAll = 'All communities';
  static const audienceAllHint = 'For families with no caste preference';
  static const audiencePickHint = 'Tap the communities that may also see your profile.';
  static const audienceNoOthers = 'There are no other communities to pick yet.';
  static const privacySaved = 'Privacy settings saved';
  static const privacyUnavailable = 'Privacy settings are not available right now. Please try again in a while.';
  static const privacyAfterCreateTitle = 'Profile registered';
  static const privacyAfterCreateBody =
      'One more thing — choose what other families may see. You can change this any time from My profile.';
  static const skipForNow = 'Skip for now';
  static const saveAndContinue = 'Save and continue';
  static const continueLabel = 'Continue';

  /// "3 details hidden · shown to all communities" — the one-line state of
  /// the privacy settings on the My profile page.
  static String privacySummary({required int hidden, required bool allCommunities, int extraCommunities = 0}) {
    final details = switch (hidden) {
      0 => 'All details shown',
      1 => '1 detail hidden',
      _ => '$hidden details hidden',
    };
    final audience = allCommunities
        ? 'shown to all communities'
        : switch (extraCommunities) {
            0 => 'shown to your community only',
            _ => 'shown to your community + $extraCommunities more',
          };
    return '$details · $audience';
  }

  // ---- checkout (mock, or Razorpay since v3.1 — SPEC §9.19 B)
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
  static const razorpaySecure = 'Secure payment by Razorpay — UPI, cards, net banking';
  static const paymentCancelled = 'Payment cancelled';
  static const paymentCancelledBody = 'No payment was made. You can pay whenever you are ready.';
  static const razorpayFailedTitle = 'Payment did not complete';
  static const razorpayFailedBody =
      'If money was deducted, it will show as paid within a few minutes — contact your agent if it does not.';
  static const errPaymentProviderChanged = 'The payment method has just changed. Please try again.';
  static const tryAgain = 'Try again';
  static const amount = 'Amount';

  // ---- direct UPI, verified by the Wedbook team (v3.2 — SPEC §9.20 B / E)
  static const upiStep1 = 'Pay by UPI';
  static String payWithUpiApp(num? fee) => 'Pay ${feeLabel(fee)} with UPI app';
  static const upiNoAppTitle = 'No UPI app could open this payment';
  static const upiNoAppBody = 'Scan the QR code below from another phone, or pay to the UPI ID shown.';
  static const upiScanCaption = 'Or scan with any UPI app on another phone';
  static const upiId = 'UPI ID';
  static const upiIdCopied = 'UPI ID copied';
  static const copy = 'Copy';
  static String upiPayTo(String name) => 'Pay to $name';
  static String upiAmountNote(num? fee) => 'Amount ${feeLabel(fee)} — enter it exactly if your app asks.';
  static const upiStep2 = 'After paying';
  static const upiStep2Body = 'Enter the 12-digit UPI reference (UTR) from your UPI app.';
  static const utrLabel = 'UPI reference / UTR (12 digits)';
  static const utrHelper = "Find it in your UPI app's payment details after paying";
  static const utrInvalid = 'Enter the 12-digit UTR exactly as your UPI app shows it';
  static const submitForVerification = 'Submit for verification';
  static const upiUnderReviewTitle = 'Payment under verification';
  static const upiUnderReviewBody = "We'll confirm within a few hours. You'll get a notification.";
  static String utrLine(String utr) => 'UTR $utr';
  static const checkStatus = 'Check status';
  static String upiNotVerified(String? reason) =>
      reason == null || reason.trim().isEmpty ? 'Payment not verified' : 'Payment not verified: ${reason.trim()}';
  static const upiNotVerifiedBody =
      'Check the 12-digit UTR in your UPI app and submit it again — or pay again if no money was taken.';
  static const step3UnderReview = "Payment under verification — we'll confirm within a few hours.";
  static const viewPaymentStatus = 'View payment status';
  static const fixPayment = 'Fix payment';
  static const chipVerifyingPayment = 'Verifying payment';
  static const chipPaymentNotVerified = 'Payment not verified';
  static const errUtrUsed =
      'This UTR has already been used. Check the 12-digit number in your UPI app.';
  static const errPaymentUnderReview = 'Your payment is already being verified.';

  // ---- the Google Play build (SPEC §9.20 G): no payment other than Google's
  static const paymentUnavailable = "Online payment isn't available in this version yet.";
  static const chipFeeNotPaid = 'Fee not paid';
  static const step3TitleNoPayment = 'Registration fee or gift code';

  // ---- publish last, gift codes, recommended agents (v3.4.0 — SPEC §9.23 B / C / F)
  /// "12 clients" — an agent's live clients.
  static String clientsCount(int n) => n == 1 ? '1 client' : '$n clients';
  static const publishMyProfile = 'Publish my profile';
  static const publishStepAgent = 'Agent';
  static const publishStepPayment = 'Payment';
  static const publishStepApproval = 'Approval';
  static const publishReadyTitle = 'Your profile is ready to publish';
  static String publishReadyBody(num? fee) =>
      'Choose your agent and pay ${feeLabel(fee)} — or use a gift code from an agent — so other families can see it.';
  static const publishReadyBodyNoPayment =
      'Choose your agent — use a gift code from them, or ask them to publish it for you.';
  static const publishNeedsProfileTitle = 'Create your profile first';
  static const publishNeedsProfileBody =
      'Fill in your profile. Then come back here to choose your agent and publish it.';
  static const publishAgentIntro =
      'Your agent takes your profile to other families and follows up interests for you.';
  static const giftCodeQuestion = 'Have a gift code from an agent?';
  static const giftCodeQuestionBody =
      'Enter it here — it links you to that agent and publishes your profile at once, with no fee.';
  static const giftCodeOnPayBody = 'Got a gift code from your agent? Enter it instead of paying.';
  static const giftCodeLabel = 'Gift code';
  static const giftCodeHint = 'WB-K7M2QX';
  static const giftCodeApply = 'Apply';
  static const giftCodeEmpty = 'Enter the gift code your agent gave you';
  static const giftCodeApplied = 'Gift code applied — your profile is live';
  static const useGiftCode = 'Use a gift code';
  static const errGiftCodeNotFound = 'This gift code is not valid — check it with your agent.';
  static const errGiftCodeUsed = 'This gift code has already been used.';
  static const errGiftCodeOtherAgent = 'This code is from another agent. Ask your agent for a code.';
  static const errGiftCodeTooMany = 'Too many wrong codes. Please try again in an hour.';
  static const recommendedTitle = 'Recommended for you';
  static const recommendedBasedOn = 'Based on your community and native place';
  static const recommendedNone =
      "No agents to recommend yet — search all agents or enter your agent's number.";
  static const searchAllAgents = 'Search all agents';
  static const enterAgentNumberOrCode = "Enter your agent's mobile number or code";
  static const publishPayIntro = 'Pay the one-time registration fee, or use a gift code from your agent.';
  static const publishWaitingTitle = "Waiting for your agent's approval";
  static String publishWaitingBody(String agent) =>
      '$agent approves your account, then your profile goes live. Call them if it takes long.';
  static const publishLiveTitle = 'Your profile is live';
  static const publishLiveBody = 'Other families can now find your profile. Your agent takes interests forward.';
  static String paidViaLine(String via) => switch (via) {
        'gift' => 'Fee: covered by a gift code',
        'cash' => 'Fee: paid in cash to your agent',
        'upi' || 'razorpay' => 'Fee: paid online',
        'waived' => 'Fee: waived',
        _ => 'Fee: paid',
      };

  // ---- "View as others see it" (v3.4.0 — SPEC §9.23 D)
  static const viewAsOthers = 'View as others see it';
  static const viewAsOthersHint = 'Check what other families see before and after you accept their interest';
  static const previewTitle = 'As others see it';
  static const previewBanner = 'Preview — this is how other families see your profile';
  static const previewTabBefore = 'Before interest is accepted';
  static const previewTabAfter = 'After interest is accepted';
  static const previewBeforeNote =
      'Family, contact and place details — and anything you switched off in Privacy settings — are shared only after you accept a family\'s interest.';

  // ---- searchable long lists (v3.4.0 — SPEC §9.23 E)
  static String searchIn(String what) => 'Search ${what.toLowerCase()}';
  static const nothingMatches = 'Nothing matches — try fewer letters.';
  static const selectHint = 'Select';
  static String selectedCount(int n) => '$n selected';
  static const chooseCommunities = 'Choose communities';

  // ---- Browse filters: long lists as picker fields (v3.5.0 — SPEC §9.24 B)
  static const anyValue = 'Any';
  static String removeValue(String name) => 'Remove $name';

  // ---- account deletion (SPEC §9.20 F)
  static const deleteAccount = 'Delete my account';
  static const deleteAccountSubtitle = 'Ask us to delete your account and data';
  static const deleteAccountBody =
      "We'll open our account deletion page. After we confirm with you on your registered number, your account, profile and photos are deleted within 7 days.";
  static const openDeletionPage = 'Open deletion page';
  static const linkOpenFailed = 'Could not open the browser. Please try again.';

  // ---- report / block (SPEC §9.22 A / B)
  static const moreOptions = 'More options';
  static const reportProfile = 'Report profile';
  static const reportProfileBody = 'Why are you reporting this profile? Our team reviews every report.';
  static String reportReasonLabel(String apiValue) => switch (apiValue) {
        'fake_profile' => 'Fake profile',
        'inappropriate_photo' => 'Inappropriate photo',
        'offensive_content' => 'Offensive content',
        'scam_or_fraud' => 'Scam or fraud',
        'harassment' => 'Harassment',
        _ => 'Other',
      };
  static const reportDetailsHint = 'Anything else we should know? (optional)';
  static const submitReport = 'Submit';
  static const reportThanks = 'Thanks — our team will review this profile.';
  static const block = 'Block';
  static const blockTitle = 'Block this profile?';
  static const blockBody =
      "You won't see this profile any more, and they won't see yours. You can unblock later in More → Blocked profiles.";
  static const profileBlocked = 'Profile blocked';
  static const blockedProfiles = 'Blocked profiles';
  static const blockedProfilesSubtitle = 'Profiles you have blocked';
  static const noBlockedTitle = 'No blocked profiles';
  static const noBlockedBody = 'Profiles you block are listed here. You can unblock them any time.';
  static String blockedOn(String date) => 'Blocked on $date';
  static const unblock = 'Unblock';
  static String unblockedSnack(String label) => '$label unblocked';

  // ---- terms consent at signup (SPEC §9.22 C)
  static const termsAgreePrefix = 'I agree to the ';
  static const termsLink = 'Terms & Conditions';
  static const termsAnd = ' and ';
  static const privacyLink = 'Privacy Policy';
  static const termsRequired = 'Please agree to the Terms & Conditions and Privacy Policy to continue.';

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
