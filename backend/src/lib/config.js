// Central runtime config. Everything comes from env (see .env.example).

function required(name) {
  const v = process.env[name];
  if (!v) throw new Error(`Missing required env var ${name}`);
  return v;
}

const bool = (v, fallback) => (v === undefined || v === '' ? fallback : /^(1|true|yes|on)$/i.test(String(v)));

const otpProvider = (process.env.OTP_PROVIDER || 'mock').toLowerCase();
const paymentProvider = (process.env.PAYMENT_PROVIDER || 'mock').toLowerCase();

/** FCM_SERVICE_ACCOUNT: the service-account JSON, base64-encoded (or raw JSON). */
function serviceAccount() {
  const raw = process.env.FCM_SERVICE_ACCOUNT || '';
  if (!raw) return null;
  try {
    return JSON.parse(raw.trim().startsWith('{') ? raw : Buffer.from(raw, 'base64').toString('utf8'));
  } catch {
    console.error('[config] FCM_SERVICE_ACCOUNT is not valid JSON / base64 JSON — push is off');
    return null;
  }
}
const fcmServiceAccount = serviceAccount();
const fcmReady = Boolean(process.env.FCM_PROJECT_ID && fcmServiceAccount);
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

  // ---- OTP (SPEC §9.1). 'mock' sends nothing and accepts OTP_MOCK_CODE; 'msg91'
  // sends our generated code through MSG91. Switching provider needs no code change.
  otp: {
    provider: otpProvider === 'msg91' ? 'msg91' : 'mock',
    mockCode: process.env.OTP_MOCK_CODE || '123456',
    // Echo the mock code in the send response so the apps can show
    // "Test mode — enter 123456". Forced off for a real provider.
    mockEcho: otpProvider === 'mock' && bool(process.env.OTP_MOCK_ECHO, true),
    ttlSeconds: Number(process.env.OTP_TTL_SECONDS || 300),
    resendSeconds: Number(process.env.OTP_RESEND_SECONDS || 30),
    maxAttempts: Number(process.env.OTP_MAX_ATTEMPTS || 5),
    maxSendsPerHour: Number(process.env.OTP_MAX_SENDS_PER_HOUR || 5),
    verificationTokenTtl: process.env.OTP_VERIFICATION_TOKEN_TTL || '15m',
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
    projectId: process.env.FCM_PROJECT_ID || '',
    apiKey: process.env.FCM_API_KEY || '',
    senderId: process.env.FCM_SENDER_ID || '',
    appIdMediator: process.env.FCM_APP_ID_MEDIATOR || '',
    appIdGandharva: process.env.FCM_APP_ID_GANDHARVA || '',
    serviceAccount: fcmServiceAccount,
    intervalMs: Number(process.env.PUSH_INTERVAL_MS || 60_000),
  },

  // ---- Gandharva registration fee (SPEC §9.12). 'mock' charges nothing and
  // confirms any checkout; 'razorpay' creates real orders and checks the
  // checkout signature. Switching provider needs no backend code change.
  payments: {
    provider: paymentProvider === 'razorpay' ? 'razorpay' : 'mock',
    profileFeeInr: Number(process.env.PROFILE_FEE_INR || 150),
    maxCustomerProfiles: Number(process.env.MAX_CUSTOMER_PROFILES || 5),
    razorpay: {
      keyId: process.env.RAZORPAY_KEY_ID || '',
      keySecret: process.env.RAZORPAY_KEY_SECRET || '',
    },
  },
};
