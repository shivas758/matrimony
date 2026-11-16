/// All user-facing text in one place so Telugu/Hindi can be added later
/// without touching screens (SPEC §5, v2 item).
class S {
  // ---- brand (SPEC §9.18 A): the app is "Wedbook Agent"; the wordmark reads
  // "Wedbook" with "AGENT" under it, like the logo. The customers' app is
  // "Wedbook Matrimony".
  static const brandName = 'Wedbook';
  static const appTagline = 'Agent';
  static const customerAppName = 'Wedbook Matrimony';

  // ---- auth
  static const appIntro = 'Private profile sharing for marriage bureaus';
  static const login = 'Login';
  static const signup = 'Create account';
  static const logout = 'Logout';
  static const phone = 'Mobile number';
  static const password = 'Password';
  static const fullName = 'Full name';
  static const agencyName = 'Bureau / agency name';
  static const selectCommunities = 'Which communities do you work with?';
  static const selectCommunitiesHint = 'You will only see profiles from these communities.';
  static const noAccount = "Don't have an account? Sign up";
  static const haveAccount = 'Already registered? Login';
  static const changePassword = 'Change password';
  static const currentPassword = 'Current password';
  static const newPassword = 'New password';
  static const confirmPassword = 'Confirm new password';
  static const forgotPassword = 'Forgot password?';
  static const forgotPasswordBody =
      'Enter your registered mobile number. The admin will be notified, verify it is you, '
      'and send you a temporary password on WhatsApp or by phone.';
  static const forgotPasswordSend = 'Ask admin to reset';
  static const forgotPasswordSent =
      'Request sent. The admin will contact you with a temporary password.';
  static const setNewPasswordTitle = 'Set a new password';
  static const setNewPasswordBody =
      'You signed in with a temporary password. Choose your own password to continue.';
  static const temporaryPassword = 'Temporary password';
  static const passwordUpdated = 'Password updated';

  // ---- pending
  static const pendingTitle = 'Waiting for approval';
  static const pendingBody =
      'Your account has been created. An admin needs to approve it before you can see profiles.';
  static const pendingHint = 'This usually takes a short while. Pull down to check again.';
  static const suspendedTitle = 'Account suspended';
  static const suspendedBody = 'Your account has been suspended. Please contact your admin.';
  static const checkAgain = 'Check again';

  // ---- navigation
  static const profiles = 'Profiles';
  static const myUploads = 'My uploads';
  static const requests = 'Requests';
  static const shortlists = 'Shortlists';
  static const settings = 'Settings';
  static const admin = 'Admin';

  // ---- profile list
  static const searchHint = 'Search by name or ID';
  static const filters = 'Filters';
  static const clearAll = 'Clear all';
  static const apply = 'Show results';
  static const noProfiles = 'No profiles yet';
  static const noProfilesHint = 'Add the first profile with the + button.';
  static const noMatches = 'No profiles match these filters';
  static const noMatchesHint = 'Try widening the age range or clearing a filter.';
  static const addProfile = 'Add profile';
  static const savePreset = 'Save these filters';
  static const presets = 'Saved filters';

  // ---- filter labels
  static const gender = 'Looking for';
  static const bride = 'Bride';
  static const groom = 'Groom';
  static const both = 'Both';
  static const ageRange = 'Age';
  static const heightRange = 'Height';
  static const community = 'Community';
  static const education = 'Education';
  static const profession = 'Profession';
  static const maritalStatus = 'Marital status';
  static const complexion = 'Complexion';
  static const rasi = 'Rasi (zodiac)';
  static const nakshatram = 'Nakshatram (star)';
  static const city = 'City / town';
  static const place = 'Place';
  static const placeHint = 'Work place or native city';
  static const nri = 'NRI';
  static const nriOnly = 'NRI profiles only';
  static const nriCountry = 'Country';
  static const nriPlace = 'Place abroad';
  static const anyCountry = 'Any country';
  static const sortBy = 'Sort by';
  static const onlyMine = 'Only my uploads';
  static const profileStatus = 'Profile status';

  // ---- profile detail
  static const about = 'About';
  static const familyDetails = 'Family details';
  static const basicDetails = 'Details';
  static const horoscope = 'Horoscope';
  static const contactDetails = 'Contact details';
  static const personalDetails = 'Personal details';
  static const gothram = 'Gothram';
  static const weight = 'Weight';
  static const workPlace = 'Work place';
  static const nativePlace = 'Native place';
  static const educationDetails = 'Education details';
  static const professionDetails = 'Profession details';
  static const fatherName = "Father's name";
  static const fatherPhone = "Father's phone";
  static const motherName = "Mother's name";
  static const motherPhone = "Mother's phone";
  static const requestContact = 'Request contact details';
  static const contactRequested = 'Request sent — waiting for approval';
  static const contactHidden =
      'Native place, birth place, work place, family, siblings, property and contact details are '
      'hidden until the uploader approves your request.';
  static const contactRejected = 'Your request was rejected.';
  static const contactRevoked = 'Your access was revoked.';
  static const contactExpired = 'Your access has expired. You can request again.';
  static const shareWhatsApp = 'Share on WhatsApp';
  static const downloadCard = 'Download card';
  static const shortlist = 'Shortlist';
  static const editProfile = 'Edit profile';
  static const shareNote = 'Shared links and downloads never include contact details.';
  static const height = 'Height';
  static const age = 'Age';
  static const income = 'Income';
  static const location = 'Location';
  static const starRasi = 'Star / Rasi';

  // ---- profile form
  static const newProfile = 'New profile';
  static const editProfileTitle = 'Edit profile';
  static const dob = 'Date of birth';
  static const photos = 'Photos';
  static const addPhotos = 'Add photos';
  static const makePrimary = 'Make main photo';
  static const removePhoto = 'Remove photo';
  static const contactFieldsNote =
      'Native place, parents and contact person are visible only to you until you approve a request. '
      'They are never included in shares or downloads.';
  static const contactPersonName = 'Contact person name';
  static const contactPersonPhone = 'Contact phone number';
  static const save = 'Save';
  static const saving = 'Saving…';

  // ---- subcaste + AI import
  static const subcaste = 'Subcaste';
  static const subcasteHint = 'Type to search, or add a new one';
  static const subcasteNeedsCommunity = 'Select a community first';
  static const subcasteNew = 'New — will be added to the list when you save';
  static const fillFromBiodata = 'Fill from bio-data';
  static const aiImportBody =
      'Upload a PDF or photo of the bio-data, or paste its text. The AI reads it and fills the '
      'form for you to check. The document is sent to the AI service and is not stored on the server.';
  static const aiPasteHint = 'Paste the bio-data text here';
  static const aiPickFile = 'Choose PDF or photo';
  static const aiUseText = 'Use pasted text';
  static const aiParsing = 'Reading the bio-data…';
  static const aiFilled = 'Fields filled — please check every field before saving';
  static const aiUnmatchedPrefix = 'Not matched, pick manually: ';

  // ---- birth details (horoscope)
  static const birthTime = 'Birth time';
  static const birthPlace = 'Birth place';
  static const birthDetailsHint =
      'Used for horoscope matching. Shown in shares along with star and rasi.';

  // ---- hold
  static const hold = 'Hold';
  static const onHold = 'On hold';
  static const requestHold = 'Request hold';
  static const holdRequested = 'Hold requested — waiting for the uploader';
  static const holdRequestBody =
      'Ask the uploader to put this profile on hold while your client is in talks. '
      'Once approved, other agents will not see it until the hold is released.';
  static const putOnHold = 'Put on hold';
  static const releaseHold = 'Release hold';
  static const cancelHoldRequest = 'Cancel hold request';
  static const holdRequests = 'Hold requests';
  static const contactRequests = 'Contact requests';
  static const heldByYou = 'On hold for your client';
  static const holdApprovedBody =
      'Other agents cannot see this profile until the hold is released.';
  static const holdRejected = 'Your hold request was rejected.';
  static const holdReleasedMsg = 'Hold released — the profile is visible again';
  static const holdPendingApproval = 'waiting for your approval';

  // ---- delete
  static const deleteProfile = 'Delete profile';
  static const deleteProfileBody =
      'This removes the profile, its photos, requests and share links permanently. '
      'If the match is done, marking it Engaged or Married keeps the record instead.';
  static const profileDeleted = 'Profile deleted';

  // ---- requests
  static const inbox = 'Received';
  static const sent = 'Sent';
  static const approve = 'Approve';
  static const reject = 'Reject';
  static const revoke = 'Revoke access';
  static const noInbox = 'No one has asked for your contacts yet';
  static const noSent = 'You have not requested any contacts';

  // ---- shortlists
  static const noShortlists = 'No shortlists yet';
  static const noShortlistsHint = 'Open a profile and tap Shortlist to save it for a client.';
  static const clientLabel = 'Client name / label';
  static const addToShortlist = 'Add to shortlist';

  // ---- admin
  static const pendingAgents = 'Pending agents';
  static const allAgents = 'Agents';
  static const masterTables = 'Master lists';
  static const communityRequests = 'Community requests';
  static const logs = 'Logs';
  static const shareLogs = 'Share log';
  static const contactLogs = 'Contact log';
  static const activate = 'Activate';
  static const suspend = 'Suspend';
  static const makeAdmin = 'Make admin';
  static const makeAgent = 'Make agent';
  static const passwordResets = 'Password resets';
  static const resetPassword = 'Reset password';
  static const noPasswordResets = 'No password reset requests';
  static const tempPasswordHint =
      'Tell the agent this password by phone or WhatsApp. They must change it on their next login.';

  // ---- settings
  static const myCommunities = 'My communities';
  static const requestCommunity = 'Request another community';
  static const requestSent = 'Request sent to admin';
  static const requestCommunityNote =
      'An admin has to approve this before you can see those profiles.';

  // ---- Mediator fields (religion, languages, food, siblings)
  static const religion = 'Religion';
  static const motherTongue = 'Mother tongue';
  static const knownLanguages = 'Languages known';
  static const foodHabit = 'Food habit';
  static const siblings = 'Siblings';
  static const hasSiblings = 'Has siblings?';
  static const siblingsCount = 'Number of siblings';
  static const siblingsDetails = 'About the siblings';
  static const siblingsDetailsHint =
      'Brothers / sisters, married or not, where they live — shown only inside the app, never in shares';
  static const yes = 'Yes';
  static const no = 'No';
  static const notRecorded = 'Not recorded';
  static const none = 'None';

  // ---- share sheet
  static const shareTitle = 'Share profile';
  static const shareSubtitle = 'Choose how to send it. Contact details are never included.';
  static const shareLinkTitle = 'WhatsApp message + link';
  static const shareLinkBody = 'A short summary with a private web page (photos, bio, horoscope).';
  static const sharePdfTitle = 'PDF bio-data';
  static const sharePdfBody = 'A one-page PDF with photos and details, sent as a file.';
  static const shareCardTitle = 'Photo card';
  static const shareCardBody = 'One image with the main photo and key details.';
  static const preparingPdf = 'Preparing the PDF…';
  static const preparingCard = 'Preparing the card…';

  // ---- generic
  static const retry = 'Retry';
  static const cancel = 'Cancel';
  static const close = 'Close';
  static const delete = 'Delete';
  static const confirm = 'Confirm';
  static const loading = 'Loading…';
  static const somethingWrong = 'Something went wrong';

  // ---- v2.1 registration-form fields
  static const nationality = 'Nationality';
  static const occupationType = 'Occupation type';
  static const worksIn = 'Works in';
  static const workCountry = 'Work country';
  static const workCountryHint = 'The country only — the exact place is shown after approval';
  static const otherIncome = 'Other income';
  static const otherIncomeHint = 'e.g. rent, farm, family business';
  static const educationLevels = 'Education by level';
  static const educationLevelsHint =
      'Fill in the levels that apply. Leave the rest empty.';
  static const educationLevelDetailsHint = 'School / college, year';
  static const country = 'Country';
  static const anyOccupationType = 'Any occupation type';
  static const anyWorkCountry = 'Any country';
  static const birthState = 'Birth state';
  static const birthCountry = 'Birth country';
  static const fatherOccupation = "Father's occupation";
  static const motherOccupation = "Mother's occupation";
  static const siblingsBreakdown = 'Brothers and sisters';
  static const elderSisters = 'Elder sisters';
  static const youngerSisters = 'Younger sisters';
  static const elderBrothers = 'Elder brothers';
  static const youngerBrothers = 'Younger brothers';
  static const property = 'Property';
  static const propertyShare = 'Property share';
  static const propertyShareHint = "e.g. Equal share with brother, 5 acres in the person's name";
  static const propertyDetails = 'Property details';
  static const propertyDetailsHint = 'House, land, other assets';
  static const noPersonalDetails = 'No personal or contact details were saved for this profile.';
  static const workPlaceHint = 'Town / city where they work or live now';

  // ---- v2.1 OTP signup (SPEC §9.1)
  static const otpStepTitle = 'Verify your mobile number';
  static const otpStepBody =
      'This number becomes your login ID. We send a one-time code by SMS to confirm it is yours.';
  static const detailsStepTitle = 'Your details';
  static const stepOf = 'Step'; // "Step 1 of 2"
  static const sendOtp = 'Send OTP';
  static const otpCode = 'OTP code';
  static const otpSentTo = 'Enter the 6-digit code sent to';
  static const otpInvalidLength = 'Enter the 6-digit code';
  static const verifyOtp = 'Verify';
  static const resendOtp = 'Resend OTP';
  static const resendIn = 'Resend in';
  static const testModeHint = 'Test mode — enter';
  static const changeNumber = 'Change number';
  static const phoneVerified = 'Mobile number verified';
  static const selectOneCommunity = 'Select at least one community';

  // ---- v2.1 clients (SPEC §9.5 / §9.11)
  static const clients = 'Clients';
  static const interests = 'Interests';
  static const transfers = 'Transfers';
  static const registrationForm = 'Registration form';
  static const registrationFormBody =
      'Send this link to a new client on WhatsApp. They fill in the registration form on their '
      'phone and appear here for your approval.';
  static const copyLink = 'Copy link';
  static const linkCopied = 'Link copied';
  static const rotateLink = 'Rotate link';
  static const rotateLinkBody =
      'The old link stops working immediately. Anyone you already sent it to will need the new one.';
  static const linkRotated = 'New link created — the old one no longer works';
  static const searchClients = 'Search by name, phone or ID';
  static const noClients = 'No clients yet';
  static const noClientsHint =
      'Share your registration form, or ask clients to sign up in the $customerAppName app '
      'with your mobile number or agent code.';
  static const noClientMatches = 'No clients match your search';
  static const noInterests = 'No interests yet';
  static const noInterestsHint =
      'When a client is interested in one of your profiles, it appears here for your decision.';
  static const noTransfers = 'No transfer requests';
  static const noTransfersHint =
      'Clients asking to move to another agent, and clients moving to you, appear here.';
  static const noProfileYet = 'No profile yet';
  static const noProfileYetBody = 'No profile yet — the client fills it in $customerAppName';
  static const profilePrefix = 'Profile: ';
  static const sourceApp = 'App';
  static const sourceForm = 'Form';
  static const registeredVia = 'Registered via';
  static const clientSince = 'Client since';
  static const approvedOn = 'Approved on';
  static const lastLogin = 'Last login';
  static const rejectClientBody =
      'will not be able to use $customerAppName with you. Only an admin can undo this.';
  static const suspendClientBody =
      'They keep their account but cannot browse or mark interests until you activate them again.';
  static const clientApproved = 'Client approved — they can now browse profiles';
  static const clientRejected = 'Client rejected';
  static const clientSuspended = 'Client suspended';
  static const clientActivated = 'Client activated';
  static const rejectedNote = 'Rejected — an admin can re-activate this client.';
  static const call = 'Call';
  static const whatsApp = 'WhatsApp';
  static const cannotCall = 'Could not open the phone app';
  static const accept = 'Accept';
  static const decline = 'Decline';
  static const revokeShort = 'Revoke';
  static const isInterestedIn = 'is interested in';
  static const interestedIn = 'Interested in';
  static const theirProfile = 'Their profile';
  static const theirAgent = 'Their agent';
  static const uploadedBy = 'Profile uploaded by';
  static const interestAccepted = 'Accepted — the client and their agent see the details for 15 days';
  static const interestDeclined = 'Interest declined';
  static const interestRevoked = 'Access revoked';
  static const revokeInterestBody =
      'The client and their agent lose access to the on-request details immediately.';
  static const wantsToMoveTo = 'wants to move to';
  static const joiningYouFrom = 'joining you from';
  static const movedTo = 'moved to';
  static const needsYourDecision = 'Needs your decision';
  static const movingToYou = 'Moving to you';
  static const approveTransferBody =
      'The client and their profile move to the other agent. You will no longer see them.';
  static const transferApproved = 'Transfer approved — the client has moved';
  static const transferRejected = 'Transfer rejected';
  static const agentChange = 'Agent change';
  static const noClientInterests = 'This client has not marked any interests yet.';
  static const clientProfile = 'Profile';

  // ---- v2.1 admin customers
  static const customers = 'Customers';
  static const customersSubtitle = '$customerAppName accounts across all agents';
  static const reassignAgent = 'Reassign agent';
  static const reassignAgentBody = 'The customer and their profile move to the chosen agent.';
  static const searchAgents = 'Search by name, agency, phone or code';
  static const noCustomers = 'No customers in this list';
  static const noActiveAgents = 'No other active agents';
  static const agentLabel = 'Agent';
  static const customerMoved = 'Customer moved to';

  // ---- v2.1 settings: agent directory (SPEC §9.6)
  static const agentDirectory = 'Agent directory';
  static const myCity = 'My city';
  static const myCityHint = 'City / town where your bureau is';
  static const agentDirectoryNote =
      'Customers see your name, agency, city and phone when choosing an agent.';
  static const notSet = 'Not set';
  static const accountUpdated = 'Account updated';

  // ---- v2.2 guest mode, registration fee, several profiles (SPEC §9.12)
  static const clientProfiles = 'Profiles';
  static const feePaid = 'Paid';
  static const feeNotPaid = 'Fee not paid';
  static const feePending = 'Fee pending';
  static const unpaidApproveNote =
      'Their profile goes live only after they pay the registration fee in $customerAppName.';
  static const paymentRequired =
      "This customer hasn't paid the registration fee for this profile yet — it stays hidden "
      'until they pay in $customerAppName.';
  static const onBehalfOf = 'On behalf of';
  static const noAgentYet = 'No agent yet';
  static const guestCustomers = 'Guests (no agent)';
  static const paidRegistrations = 'Paid registrations';
  static const guestReassignNote =
      'Guest — signed up in $customerAppName without an agent. Reassigning gives them that agent '
      '(they become pending).';
  static String profilesCount(int n) => n == 1 ? '1 profile' : '$n profiles';

  // ---- v2.3 cash payments and delete requests (SPEC §9.13)
  static const markPaidCash = 'Mark paid (cash)';
  static const markPaidTitle = 'Paid in cash?';
  static String markPaidBody(String name) =>
      'Record the registration fee as received in cash for $name?';
  static const markPaidNoteHint = 'Note (optional), e.g. receipt no.';
  static const markPaidConfirm = 'Record payment';
  static const markedPaid = 'Payment recorded — the fee is marked paid';
  static const wantsToDelete = 'Wants to delete';
  static const deleteRequestChip = 'Delete request';
  static const deleteRequests = 'Delete requests';
  static const deletesTab = 'Deletes';
  static const approveDelete = 'Approve delete';
  static String approveDeleteBody(String name) =>
      'This permanently deletes $name and its photos. It cannot be undone.';
  static const asksToDelete = 'asks to delete';
  static const deleteRejected = 'Delete request rejected — the profile stays';
  static const noDeleteRequests = 'No delete requests';
  static const noDeleteRequestsHint =
      'When a client asks to delete a profile they paid for, it appears here for your decision.';

  // ---- v2.4 notifications screen (SPEC §9.14)
  static const notifications = 'Notifications';
  static const needsYourAction = 'Needs your action';
  static const updates = 'Updates';
  static const noNotifications = 'No notifications';
  static const noNotificationsHint =
      'Requests, new clients and decisions on your requests appear here.';
  static const justNow = 'Just now';
  static String minutesAgo(int n) => '$n min ago';
  static String hoursAgo(int n) => n == 1 ? '1 hour ago' : '$n hours ago';
  static const yesterday = 'Yesterday';
  static String daysAgo(int n) => '$n days ago';

  // ---- v2.5 push notifications (SPEC §9.16)
  static const newNotification = 'New notification';
  static const view = 'View';

  // ---- photo editor + camera (SPEC §9.17)
  static const takePhoto = 'Take photo';
  static const takePhotoHint = 'Use the camera now';
  static const chooseFromGallery = 'Choose from gallery';
  static String chooseFromGalleryHint(int n) => n == 1 ? 'Pick 1 more photo' : 'Pick up to $n photos';
  static const photoEditHint = 'Each photo opens the editor next — crop and rotate it so it shows the way you want.';
  static const editPhoto = 'Edit photo';
  static const viewFullPhoto = 'View full photo';

  // ---- v3.0 agent state and agent code (SPEC §9.18 B)
  static const state = 'State';
  static const stateHelper = 'Decides your agent code — it cannot be changed later';
  static const stateRequired = 'Select your state';
  static const chooseStateTitle = 'Choose your State';
  static const chooseStateBody =
      'Every agent now has a permanent agent code that starts with the letters of their '
      'state. Choose the state your bureau is in — you are asked only once.';
  static const continueLabel = 'Continue';
  static String confirmStateTitle(String stateName) => 'Register in $stateName?';

  /// "KA — Karnataka. Your agent code will start with KA and cannot be changed later."
  static String confirmStateBody(String code, String stateName) =>
      '$code — $stateName. Your agent code will start with $code and cannot be changed later.';
  static const yourAgentCode = 'Your agent code';
  static const agentCode = 'Agent code';
  static const agentCodeCopied = 'Agent code copied';
  static const agentCodeHint =
      'Clients can link to you in $customerAppName with this code. Tap to copy.';
  static String agentCodeIssued(String code) => 'Your agent code is $code';
  static const agentCodeIssuedBody =
      'It is permanent and yours alone. Share it with your clients — they can choose you '
      'in $customerAppName with it.';
  static const tapToCopy = 'Tap to copy';
  static const statesNotLoaded = 'The list of states could not be loaded.';
  static const searchAgentsAdmin = 'Search name, phone or agent code';
  static const noAgentsFound = 'No agents match your search';

  // ---- v3.0 profile / customer IDs (SPEC §9.18 C)
  static String idLabel(String code) => 'ID $code';
  static const idCopied = 'ID copied';

  // ---- v3.0 details hidden by the family (SPEC §9.18 D)
  static const maskedNote =
      'Some details are hidden by the family — they are shared when your contact request '
      'is approved.';
  static const hiddenByFamily = 'Hidden by the family';

  // ---- v3.0 four-step profile form (SPEC §9.18 F)
  static const stepPersonal = 'Personal details';
  static const stepProfessional = 'Professional details';
  static const stepHoroscope = 'Horoscope';
  static const stepFamily = 'Family & contact';
  // The same, broken for the narrow step header.
  static const stepPersonalShort = 'Personal\ndetails';
  static const stepProfessionalShort = 'Professional\ndetails';
  static const stepHoroscopeShort = 'Horoscope';
  static const stepFamilyShort = 'Family &\ncontact';
  static const stepCompleted = 'completed';
  static const back = 'Back';
  static const next = 'Next';
  static const dobRequired = 'Select the date of birth';
  static const communityRequired = 'Select a community';
  static const fullNameRequired = 'Enter the full name';
  static const checkHighlighted = 'Please check the highlighted fields';
  static const discardChangesTitle = 'Discard changes?';
  static const discardChangesBody =
      'This profile has not been saved. If you leave now, what you entered is lost.';
  static const discard = 'Discard';
  static const keepEditing = 'Keep editing';
  static const onRequestTitle = 'Visible only after approval';
  static const onRequestWorkNote =
      'The exact work place and place abroad are shown only after you approve a request — '
      'never in shares. The country above is public.';
  static const onRequestBirthNote =
      'Birth place, state and country are shown only after you approve a request — never '
      'in shares. Star, rasi and birth time are public.';
  static const onRequestFamilyNote =
      'Everything on this step — parents, siblings, family, property, native place and the '
      'contact person — is visible only to you until you approve a request. It is never '
      'included in shares or downloads.';
  static const highestQualification = 'Highest qualification';
  static const otherEducationDetails = 'Other education details';
  static const nativeState = 'Native state';
  static const contactPerson = 'Contact person';
  static const parents = 'Parents';
  static const aiCheckSteps = 'Could not match everything — please check: ';

  // ---- v3.0 privacy card (SPEC §9.18 D / E)
  static const privacy = 'Privacy';
  static const privacyBody =
      'Decide for the family what others see before a request is approved. A switched-off '
      'detail is shared only after approval and never appears in shares.';
  static const alwaysShown = 'Always shown';
  static const shownToEveryone = 'Shown to everyone';
  static const onlyAfterApproval = 'Only after approval';
  static const hiddenWithCommunity = 'Hidden with the community';
  static const showProfileTo = 'Show this profile to';
  static const audienceOwn = 'Own community only';
  static const audienceOwnHint = 'Agents who work with this community';
  static const audienceSelected = 'Selected communities';
  static const audienceSelectedHint = 'Its own community, and the ones you pick';
  static const audienceAll = 'All communities';
  static const audienceAllHint = 'Every agent can see it';
  static const audiencePick = 'Pick the additional communities';
  static const audienceNoOthers = 'There are no other communities to pick.';

  // ---- v3.1 OTP through Firebase phone auth (SPEC §9.19 A)
  static const otpSendFailed = 'Could not send the code — please try again.';
  static const verifyingAutomatically = 'Verifying automatically…';
  static const phoneAuthWrongCode = 'Incorrect code — check the SMS and try again.';
  static const phoneAuthCodeExpired = 'This code has expired — tap Resend OTP to get a new one.';
  static const phoneAuthTooManyAttempts =
      'Too many attempts from this phone — please try again later.';
  static const phoneAuthQuotaExceeded =
      'The SMS limit for today has been reached — please try again later.';
  static const phoneAuthInvalidNumber = 'Enter a valid 10-digit mobile number.';
  static const phoneAuthNetwork = 'Cannot reach the network. Check your internet connection.';
  static const phoneAuthNotSetUp =
      'Phone verification is not set up yet — please contact the admin.';
  static const phoneAuthFailed = 'Could not verify the number — try again.';

  // ---- v3.2 paid extra communities, direct UPI payments (SPEC §9.20)
  static String rupees(int amount) => '₹$amount';

  /// "Up to 3 now — you can add more later (₹1000 each)"
  static String signupCommunitiesLimit(int limit, int fee) =>
      'Up to $limit now — you can add more later (₹$fee each)';

  /// "Choose up to 3 communities — you can add more later (₹1000 each)"
  static String tooManyCommunities(int limit, int fee) =>
      'Choose up to $limit communities — you can add more later (₹$fee each)';

  /// "1st", "2nd", "3rd", "4th", … "11th", "12th", "13th", "21st".
  static String ordinal(int n) {
    final mod100 = n % 100;
    if (mod100 >= 11 && mod100 <= 13) return '${n}th';
    return switch (n % 10) { 1 => '${n}st', 2 => '${n}nd', 3 => '${n}rd', _ => '${n}th' };
  }

  /// "This is your 4th community: one-time fee ₹1000"
  static String extraCommunityFee(int number, int fee) =>
      'This is your ${ordinal(number)} community: one-time fee ₹$fee';
  static String extraCommunityFeeBody(int freeLimit) =>
      'Your first $freeLimit communities are free. After you send the request, pay by UPI '
      'and enter the UPI reference (UTR) — an admin checks the payment and adds the community.';
  static const continueToPay = 'Continue';
  static String communityFeeFor(String community) => 'One-time fee for $community';
  static const payCommunityFee = 'Pay the community fee';
  static String payAmount(int amount) => 'Pay ₹$amount';
  static String payWithUpiApp(int amount) => 'Pay ₹$amount with UPI app';
  static const upiScanHint = 'Or scan this QR code with any UPI app — from another phone too';
  static const upiId = 'UPI ID';
  static const upiPayeeName = 'Name';
  static const upiIdCopied = 'UPI ID copied';
  static const copy = 'Copy';
  static const upiNoApp =
      'No UPI app opened. Scan the QR code from another phone, or pay to the UPI ID.';
  static const upiReference = 'Reference';
  static const utrLabel = 'UPI reference / UTR (12 digits)';
  static const utrHint = 'After paying, find the 12-digit UTR / reference number in your UPI app.';
  static const utrInvalid = 'Enter the 12-digit UTR';
  static const submitForVerification = 'Submit for verification';
  static const paymentUnderVerification = 'Payment under verification';
  static const paymentUnderVerificationBody =
      'An admin checks the payment, usually within a few hours. The community is added '
      'once it is verified.';
  static String paymentNotVerified(String? reason) =>
      reason == null || reason.isEmpty ? 'Payment not verified' : 'Payment not verified: $reason';
  static const submitAgain = 'Submit again';
  static const paymentSubmitted = 'Submitted — an admin will verify the payment';
  static const awaitingPayment = 'Awaiting payment';
  static const notPaidYet = 'not paid yet — pay to send it to the admin';
  static const paidWaitingApproval = 'Paid — waiting for admin approval';
  static const waitingAdminApproval = 'Waiting for admin approval';
  static const refundDue = 'refund due';
  static String feeLabel(int fee) => 'Fee ₹$fee';
  static String utrValue(String utr) => 'UTR $utr';
  static const done = 'Done';
  static const pendingRequests = 'Pending requests';
  static const pastRequests = 'Past requests';
  static String freeCommunitiesNote(int freeLimit, int fee) =>
      'The first $freeLimit communities are free; each one after that is a one-time ₹$fee.';

  // ---- v3.2 admin: payments to verify (SPEC §9.20 D)
  static const paymentsToVerify = 'Payments to verify';
  static const paymentsToVerifySubtitle = 'UPI payments waiting for your check';
  static const paymentsCheckHint =
      'Check this UTR and amount in your bank / UPI app before approving';
  static const filterToVerify = 'To verify';
  static const filterPaid = 'Paid';
  static const filterRejected = 'Rejected';
  static const filterAll = 'All';
  static const noPaymentsToVerify = 'No payments to verify';
  static const noPayments = 'No payments in this list';
  static const purposeRegistration = 'Registration fee';
  static const purposeExtraCommunity = 'Extra community';
  static const utr = 'UTR';
  static const utrCopied = 'UTR copied';
  static const paidBy = 'Paid by';
  static const forCommunity = 'Community';
  static const submittedOn = 'Submitted';
  static const verifiedOn = 'Verified';
  static const rejectReason = 'Reason';
  static const approvePaymentTitle = 'Approve this payment?';
  static String approvePaymentBody(int amount, String? utr) =>
      'Approve only if ₹$amount${utr == null ? '' : ' with UTR $utr'} has arrived in your bank / '
      'UPI app.';
  static const rejectPaymentTitle = 'Reject this payment?';
  static const rejectPaymentBody = 'The payer sees this reason and can submit a corrected UTR.';
  static const rejectReasonLabel = 'Reason';
  static const rejectReasonHint = 'e.g. No payment with this UTR found';
  static const rejectReasonInvalid = 'Write 3 to 200 characters';
  static const paymentApproved = 'Payment approved';
  static const paymentRejected = 'Payment rejected';
  static String paymentsToVerifyCount(int n) =>
      n == 1 ? '1 payment to verify' : '$n payments to verify';
  static const statusToVerify = 'to verify';
  static const statusPaid = 'paid';
  static const statusRejected = 'rejected';
  static const statusRefundDue = 'refund due';
  static const statusAwaitingPayment = 'awaiting payment';

  /// "Fee ₹1000 · payment submitted (UTR 123456789012)" etc.
  static String feeState(int fee, String? paymentStatus, String? utr) {
    final u = utr == null || utr.isEmpty ? '' : ' (UTR $utr)';
    final state = switch (paymentStatus) {
      'submitted' => 'payment submitted$u',
      'paid' => 'paid$u',
      'failed' => 'payment not verified$u',
      'refund_due' => 'refund due$u',
      _ => 'awaiting payment',
    };
    return 'Fee ₹$fee · $state';
  }

  // ---- v3.2 Play Store build: no non-Google payment (SPEC §9.20 G)
  static const playNoExtraCommunityPayment =
      "Extra communities can't be paid in this version yet — the admin can add them for you.";
  static const onlinePaymentUnavailable = "Online payment isn't available in this version yet";
  static String playSignupCommunitiesLimit(int limit) =>
      'Up to $limit now — the admin can add more later';
  static String playTooManyCommunities(int limit) =>
      'Choose up to $limit communities — the admin can add more later';
  static String playFreeCommunitiesNote(int freeLimit) =>
      'The first $freeLimit communities are free; the admin can add more for you.';
  static const ok = 'OK';

  // ---- v3.2 delete my account (SPEC §9.20 F)
  static const deleteMyAccount = 'Delete my account';
  static const deleteMyAccountSubtitle = 'Ask us to delete your account and data';
  static const deleteMyAccountBody =
      "We'll open our account deletion page. After we confirm with you on your registered "
      'number, your account and personal details are deleted within 7 days.';
  static const openDeletionPage = 'Open deletion page';
  static const cannotOpenBrowser = 'Could not open the browser';

  // ---- v3.2 admin: account deletion requests (SPEC §9.20 F)
  static const deletionRequests = 'Account deletion requests';
  static const deletionRequestsSubtitle = 'People asking to delete their account';
  static String deletionRequestsCount(int n) =>
      n == 1 ? '1 deletion request' : '$n deletion requests';
  static const deletionVerifyHint =
      'Call or WhatsApp this number to confirm before deleting — the request is not verified.';
  static const filterPending = 'Pending';
  static const filterDone = 'Done';
  static const noDeletionRequests = 'No account deletion requests';
  static const noDeletionRequestsInList = 'No requests in this list';
  static const appCustomer = customerAppName;
  static const appAgent = 'Wedbook Agent';
  static const accountFound = 'Account found';
  static const noAccountWithNumber = 'No account with this number';
  static const deleteAccount = 'Delete account';
  static const deleteAccountTitle = 'Delete this account?';
  static String deleteAccountConfirmBody(String phone) =>
      'The account registered with +91 $phone and its personal details are deleted. '
      'This cannot be undone.';
  static const accountDeleted = 'Account deleted';
  static const agentHasDataTitle = 'This agent still has data';
  static const rejectDeletionTitle = 'Reject this request?';
  static const rejectDeletionBody = 'Say why — for example, the person did not confirm it.';
  static const noteLabel = 'Note';
  static const rejectDeletionHint = 'e.g. Could not confirm with the person';
  static const deletionRejected = 'Request rejected';
  static const requestedOn = 'Requested';
  static const handledOn = 'Handled';
  static const statusDone = 'done';
  static const statusPending = 'pending';
  static const noReasonGiven = 'No reason given';

  // ---- v3.3 report, block, terms (SPEC §9.22)
  static const reportProfile = 'Report profile';
  static const reportProfileBody = 'Why are you reporting this profile? The admins review every report.';
  static const reportDetailsLabel = 'Details (optional)';
  static const reportDetailsHint = 'Anything that helps the admins check it';
  static const sendReport = 'Send report';
  static const reportSent = 'Thanks — the admins will review this profile.';
  static const block = 'Block';
  static const blockProfileTitle = 'Block this profile?';
  static const blockProfileBody =
      'This profile will be hidden from you. Unblock any time in Settings → Blocked profiles.';
  static const profileBlocked = 'Profile blocked';
  static const blockedProfiles = 'Blocked profiles';
  static const blockedProfilesSubtitle = 'Profiles you have hidden from yourself';
  static const noBlockedProfiles = 'No blocked profiles';
  static const noBlockedProfilesHint =
      'Profiles you block from their ⋮ menu are listed here, so you can unblock them.';
  static const unblock = 'Unblock';
  static String unblocked(String label) => '$label unblocked';
  static String blockedOn(String date) => 'Blocked on $date';

  // terms consent at signup
  static const termsAgreePrefix = 'I agree to the ';
  static const termsLink = 'Terms & Conditions';
  static const termsAnd = ' and ';
  static const privacyLink = 'Privacy Policy';
  static const termsRequired = 'Tick the box to agree to the Terms & Conditions and Privacy Policy';

  // admin: reports
  static const reports = 'Reports';
  static const reportsSubtitle = 'Profiles reported by agents and families';
  static String reportsCount(int n) => n == 1 ? '1 open report' : '$n open reports';
  static const filterOpen = 'Open';
  static const filterActioned = 'Actioned';
  static const filterDismissed = 'Dismissed';
  static const noOpenReports = 'No open reports';
  static const noReportsInList = 'No reports in this list';
  static const reportedBy = 'Reported by';
  static const reporterFamily = 'Family';
  static const reporterAgent = 'Agent';
  static const familyLabel = 'Family';
  static const uploadedByLabel = 'Uploaded by';
  static String reportsOnProfile(int n) =>
      n == 1 ? '1 report on this profile' : '$n reports on this profile';
  static const profileDeletedLabel = 'Profile deleted';
  static const dismiss = 'Dismiss';
  static const hideProfile = 'Hide profile';
  static const suspendAccount = 'Suspend account';
  static const dismissReportTitle = 'Dismiss this report?';
  static const dismissReportBody = 'Nothing changes for the profile. The report is closed.';
  static const hideProfileTitle = 'Hide this profile?';
  static const hideProfileBody =
      'The profile is hidden from everyone but its owners, and every open report on it is closed.';
  static const suspendAccountTitle = 'Suspend the account?';
  static const suspendAccountBody =
      "Suspends the family's account (or the uploading agent if there is no family account) and "
      'hides the profile.';
  static const noteOptionalLabel = 'Note (optional)';
  static const reportDismissed = 'Report dismissed';
  static const profileHidden = 'Profile hidden';
  static const accountSuspended = 'Account suspended';
  static const actionProfileHidden = 'profile hidden';
  static const actionAccountSuspended = 'account suspended';
  static const statusOpen = 'open';
  static const statusActioned = 'actioned';
  static const statusDismissed = 'dismissed';

  // ---- v3.4 approved agents, gift codes (SPEC §9.23 A / B)
  static const notApprovedTitle = 'Not approved yet';

  /// "3 of 10 clients live. Until you have 10, …"
  static String notApprovedBody(int live, int needed) =>
      '$live of $needed clients live. Until you have $needed, you see only your own profiles '
      "and clients, and families can't find you in the agents list. Give your free gift codes "
      'to families to get started.';
  static const giftCodes = 'Gift codes';
  static const giftCodesIntro =
      'Give a code to a family: they enter it when they publish their profile in '
      '$customerAppName — no registration fee, and they become your client at once.';
  static const giftCodesMoreHint = 'Need more codes? Ask the admin.';
  static const unusedCodes = 'Unused';
  static const usedCodes = 'Used';
  static String unusedCount(int n) => n == 1 ? '1 unused' : '$n unused';
  static String giftCodesLeft(int n) => n == 1 ? '1 gift code left' : '$n gift codes left';
  static const noGiftCodes = 'No gift codes yet';
  static const noGiftCodesHint = 'Pull down to check again, or ask the admin for codes.';
  static const allCodesUsed = 'All your codes are used — ask the admin for more.';
  static const giftCodeCopied = 'Gift code copied';
  static const share = 'Share';
  static String usedBy(String name) => 'Used by $name';
  static const usedByUnknown = 'Used';
  static String createdOn(String date) => 'Given $date';
  static String usedOn(String date) => 'on $date';
  static const cannotOpenWhatsApp = 'Could not open WhatsApp';

  // client detail: spend a gift code on an unpaid profile
  static const useGiftCode = 'Use a gift code';
  static String useGiftCodeConfirm(int left) =>
      'Use one of your free gift codes ($left left)? The profile goes live now.';
  static const useGiftCodeConfirmAdmin =
      "Use one of this client's agent's gift codes? The profile goes live now.";
  static const useGiftCodeConfirmLabel = 'Use gift code';
  static const giftCodeApplied = 'Gift code used — the profile is live';
  static const noGiftCodesLeft = 'You have no gift codes left — ask the admin for more';

  /// "Paid · gift code" — how a client's fee was settled.
  static String paidVia(String? via) => switch (via) {
        'gift' => 'Paid · gift code',
        'cash' => 'Paid · cash',
        'upi' => 'Paid · UPI',
        'mock' || 'razorpay' => 'Paid · in app',
        'waived' => 'Fee waived',
        _ => feePaid,
      };

  // settings
  static const approvedAgent = 'Approved agent ✓';
  static String clientsProgress(int live, int needed) => '$live / $needed clients';
  static const approvedAgentHint =
      'Families find you in the agents list, and you see every profile of your communities.';
  static String approvalProgressHint(int needed) =>
      'At $needed live clients you are approved: you see every profile of your communities, and '
      'families can find you in the agents list.';

  // admin → agents
  static const approved = 'Approved';
  static const notApproved = 'Not approved';

  /// "3/10 clients" — an admin row's progress pill.
  static String clientsShort(int live, int needed) => '$live/$needed clients';
  static const approveNow = 'Approve now';
  static String approveAgentTitle(String name) => 'Approve $name now?';
  static String approveAgentBody(int needed) =>
      'They see every profile of their communities at once, and families can find them in the '
      'agents list — without waiting for $needed live clients.';
  static String agentApproved(String name) => '$name approved';
  static const addGiftCodes = 'Add gift codes';
  static String addGiftCodesTitle(String name) => 'Gift codes for $name';
  static const addGiftCodesBody = 'How many codes to add (1–50)?';
  static const giftCodesCountLabel = 'Number of codes';
  static const giftCodesCountInvalid = 'Enter a number from 1 to 50';
  static String giftCodesAdded(int n, String name) =>
      n == 1 ? '1 gift code added for $name' : '$n gift codes added for $name';
  static const add = 'Add';
  static const notApprovedAgents = 'Not approved agents';
  static const notApprovedAgentsSubtitle = 'Agents below 10 live clients — approve by hand';

  // notifications (SPEC §9.23 A) — the server sends the text; these are
  // the fallbacks for an item without a title.
  static const agentApprovedTitle = 'You are approved';
  static const giftCodeUsedTitle = 'Gift code used';

  // ---- v3.4 searchable lists (SPEC §9.23 E)
  static String searchIn(String what) =>
      what.isEmpty ? 'Search' : 'Search ${what.toLowerCase()}';
  static const noListMatches = 'Nothing matches your search';
  static const pickNone = 'None';
}
