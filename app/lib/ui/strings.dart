/// All user-facing text in one place so Telugu/Hindi can be added later
/// without touching screens (SPEC §5, v2 item).
class S {
  // ---- auth
  static const appTagline = 'Matrimony Partners';
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
  static const searchHint = 'Search by name';
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
  static const birthPlaceProtectedHint =
      'Birth place is shown only after approval — never in shares';
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
  static const personalDetailsTitle = 'Personal details — visible only after approval';
  static const personalDetailsNote =
      'Native place, birth place, work place, parents, contact person, siblings, property and '
      'family details are visible only to you until you approve a request. '
      'They are never included in shares or downloads.';
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
  static const searchClients = 'Search by name or phone';
  static const noClients = 'No clients yet';
  static const noClientsHint =
      'Share your registration form, or ask clients to sign up in the MILI app with your '
      'mobile number.';
  static const noClientMatches = 'No clients match your search';
  static const noInterests = 'No interests yet';
  static const noInterestsHint =
      'When a client is interested in one of your profiles, it appears here for your decision.';
  static const noTransfers = 'No transfer requests';
  static const noTransfersHint =
      'Clients asking to move to another agent, and clients moving to you, appear here.';
  static const noProfileYet = 'No profile yet';
  static const noProfileYetBody = 'No profile yet — the client fills it in MILI';
  static const profilePrefix = 'Profile: ';
  static const sourceApp = 'App';
  static const sourceForm = 'Form';
  static const registeredVia = 'Registered via';
  static const clientSince = 'Client since';
  static const approvedOn = 'Approved on';
  static const lastLogin = 'Last login';
  static const rejectClientBody =
      'will not be able to use MILI with you. Only an admin can undo this.';
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
  static const customersSubtitle = 'MILI accounts across all agents';
  static const reassignAgent = 'Reassign agent';
  static const reassignAgentBody = 'The customer and their profile move to the chosen agent.';
  static const searchAgents = 'Search by name, agency or phone';
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
      'Their profile goes live only after they pay the registration fee in MILI.';
  static const paymentRequired =
      "This customer hasn't paid the registration fee for this profile yet — it stays hidden "
      'until they pay in MILI.';
  static const onBehalfOf = 'On behalf of';
  static const noAgentYet = 'No agent yet';
  static const guestCustomers = 'Guests (no agent)';
  static const paidRegistrations = 'Paid registrations';
  static const guestReassignNote =
      'Guest — signed up in MILI without an agent. Reassigning gives them that agent '
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
}
