// Central runtime config. Everything comes from env (see .env.example).

function required(name) {
  const v = process.env[name];
  if (!v) throw new Error(`Missing required env var ${name}`);
  return v;
}

const bool = (v, fallback) => (v === undefined || v === '' ? fallback : /^(1|true|yes|on)$/i.test(String(v)));

const otpProvider = (process.env.OTP_PROVIDER || 'mock').toLowerCase();
const paymentProvider = (process.env.PAYMENT_PROVIDER || 'mock').toLowerCase();

/** FIREBASE_<name>, falling back to the pre-v2.9 FCM_<old name> (SPEC §9.19 A). */
const firebaseEnv = (name, oldName) => process.env[`FIREBASE_${name}`] || process.env[`FCM_${oldName ?? name}`] || '';

// One Firebase project serves push (§9.16) and phone-auth OTP (§9.19 A).
const firebase = {
  projectId: firebaseEnv('PROJECT_ID'),
  apiKey: firebaseEnv('API_KEY'),
  senderId: firebaseEnv('SENDER_ID'),
  appIdAgent: firebaseEnv('APP_ID_AGENT', 'APP_ID_MEDIATOR'),
  appIdCustomer: firebaseEnv('APP_ID_CUSTOMER', 'APP_ID_GANDHARVA'),
  // Test hook only — where the ID-token signing certificates are fetched from.
  certsUrl:
    process.env.FIREBASE_CERTS_URL ||
    'https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com',
};

/** FIREBASE_SERVICE_ACCOUNT (old name FCM_SERVICE_ACCOUNT): the JSON, base64-encoded (or raw). */
function serviceAccount() {
  const raw = firebaseEnv('SERVICE_ACCOUNT');
  if (!raw) return null;
  try {
    return JSON.parse(raw.trim().startsWith('{') ? raw : Buffer.from(raw, 'base64').toString('utf8'));
  } catch {
    console.error('[config] FIREBASE_SERVICE_ACCOUNT is not valid JSON / base64 JSON — push is off');
    return null;
  }
}
const fcmServiceAccount = serviceAccount();
const fcmReady = Boolean(firebase.projectId && fcmServiceAccount);
const pushProvider = (process.env.PUSH_PROVIDER || (fcmReady ? 'fcm' : 'off')).toLowerCase();

export const config = {
  port: Number(process.env.PORT || 3000),
  databaseUrl: required('DATABASE_URL'),
  jwtSecret: required('JWT_SECRET'),
  jwtExpiresIn: process.env.JWT_EXPIRES_IN || '30d',
  publicBaseUrl: (process.env.PUBLIC_BASE_URL || 'http://localhost:3000').replace(/\/+$/, ''),
  uploadsDir: process.env.UPLOADS_DIR || 'uploads',
  bcryptRounds: Number(process.env.BCRYPT_ROUNDS || 10),
  // Contact approvals last this many days (SPEC §2 / CLAUDE.md rule 4). Accepted
  // customer interests (SPEC §9.4) use the same window.
  contactAccessDays: Number(process.env.CONTACT_ACCESS_DAYS || 15),
  // AI import (POST /profiles/parse). Optional — the endpoint returns 503 when unset
  // and the app hides the button, so nothing else depends on it.
  anthropicApiKey: process.env.ANTHROPIC_API_KEY || '',
  claudeModel: process.env.CLAUDE_MODEL || 'claude-opus-5',

  // Firebase project settings shared by push and OTP (see above).
  firebase,

  // ---- Public website (SPEC §9.19 E): who runs the service. Empty values are
  // simply left out of the pages.
  site: {
    businessName: process.env.SITE_BUSINESS_NAME || 'Wedbook',
    address: process.env.SITE_ADDRESS || '',
    email: process.env.SITE_EMAIL || '',
    phone: process.env.SITE_PHONE || '',
  },

  // ---- OTP (SPEC §9.1 / §9.19). 'mock' sends nothing and accepts OTP_MOCK_CODE;
  // 'fast2sms' / 'msg91' send our generated code by SMS; 'firebase' lets the phone
  // do the SMS through Firebase Authentication and verifies the resulting ID token.
  // Switching provider needs no code change.
  otp: {
    provider: ['startmessaging', 'fast2sms', 'msg91', 'firebase'].includes(otpProvider) ? otpProvider : 'mock',
    mockCode: process.env.OTP_MOCK_CODE || '123456',
    // Echo the mock code in the send response so the apps can show
    // "Test mode — enter 123456". Forced off for a real provider.
    mockEcho: otpProvider === 'mock' && bool(process.env.OTP_MOCK_ECHO, true),
    ttlSeconds: Number(process.env.OTP_TTL_SECONDS || 300),
    resendSeconds: Number(process.env.OTP_RESEND_SECONDS || 30),
    maxAttempts: Number(process.env.OTP_MAX_ATTEMPTS || 5),
    maxSendsPerHour: Number(process.env.OTP_MAX_SENDS_PER_HOUR || 5),
    verificationTokenTtl: process.env.OTP_VERIFICATION_TOKEN_TTL || '15m',
    // Payment-gateway / store reviewers (SPEC §9.19 F): this one customer number
    // gets this fixed code and never an SMS. Both must be set to take effect.
    review: {
      phone: /^[6-9]\d{9}$/.test(process.env.OTP_REVIEW_PHONE || '') ? process.env.OTP_REVIEW_PHONE : '',
      code: /^\d{6}$/.test(process.env.OTP_REVIEW_CODE || '') ? process.env.OTP_REVIEW_CODE : '',
    },
    // The owner's choice (SPEC §9.19 C2): no DLT of our own, ₹0.25 per SMS.
    startmessaging: {
      apiKey: process.env.STARTMESSAGING_API_KEY || '',
      templateId: process.env.STARTMESSAGING_TEMPLATE_ID || '',
      appName: process.env.STARTMESSAGING_APP_NAME || 'Wedbook',
      // Test hook only (backend/test/providers.mjs points it at a local fake).
      url: process.env.STARTMESSAGING_API_URL || 'https://api.startmessaging.com/otp/send',
    },
    fast2sms: {
      apiKey: process.env.FAST2SMS_API_KEY || '',
      // Test hook only (backend/test/providers.mjs points it at a local fake).
      url: process.env.FAST2SMS_API_URL || 'https://www.fast2sms.com/dev/bulkV2',
    },
    msg91: {
      authKey: process.env.MSG91_AUTH_KEY || '',
      templateId: process.env.MSG91_TEMPLATE_ID || '',
      sender: process.env.MSG91_SENDER || '',
    },
  },

  // ---- Push notifications (SPEC §9.16). 'fcm' needs the FCM_* keys; 'log' records
  // pushes in memory (tests); 'off' disables the sender and tells the apps so.
  push: {
    provider: pushProvider === 'log' ? 'log' : pushProvider === 'fcm' && fcmReady ? 'fcm' : 'off',
    projectId: firebase.projectId,
    apiKey: firebase.apiKey,
    senderId: firebase.senderId,
    appIdMediator: firebase.appIdAgent,
    appIdGandharva: firebase.appIdCustomer,
    serviceAccount: fcmServiceAccount,
    intervalMs: Number(process.env.PUSH_INTERVAL_MS || 60_000),
  },

  // ---- MILI registration fee (SPEC §9.12). 'mock' charges nothing and
  // confirms any checkout; 'razorpay' creates real orders and checks the
  // checkout signature. Switching provider needs no backend code change.
  payments: {
    provider: paymentProvider === 'razorpay' ? 'razorpay' : 'mock',
    profileFeeInr: Number(process.env.PROFILE_FEE_INR || 150),
    // One profile per customer (SPEC §9.17) — also enforced by the database
    // (uq_profiles_one_per_customer, migration 009), so this is not an env knob.
    maxCustomerProfiles: 1,
    razorpay: {
      keyId: process.env.RAZORPAY_KEY_ID || '',
      keySecret: process.env.RAZORPAY_KEY_SECRET || '',
      // Dashboard → Webhooks secret (SPEC §9.19 B). Optional; the webhook answers 503 without it.
      webhookSecret: process.env.RAZORPAY_WEBHOOK_SECRET || '',
      // Test hook only (backend/test/providers.mjs points it at a local fake).
      apiBase: (process.env.RAZORPAY_API_BASE || 'https://api.razorpay.com/v1').replace(/\/+$/, ''),
    },
  },
};
