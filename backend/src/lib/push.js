// Push notifications through Firebase Cloud Messaging — SPEC §9.16.
//
// No Google SDK: the FCM HTTP v1 API needs an OAuth2 access token, which we
// get by signing a JWT with the service account's private key (RS256, node
// crypto) and exchanging it at Google's token endpoint. Tokens are cached
// until shortly before they expire.
//
// Providers (PUSH_PROVIDER): 'fcm' sends for real; 'log' records every push
// in memory (outbox — smoke tests, support); 'off' does nothing.
import { createSign } from 'node:crypto';
import { config } from './config.js';

const TOKEN_URL = 'https://oauth2.googleapis.com/token';
const SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';
const OUTBOX_MAX = 200;

const outbox = [];
let cachedToken = null; // { value, expiresAt }

export const pushProvider = () => config.push.provider;

/** Public Firebase client options for an app, or null when push is off for it. */
export function clientOptions(app) {
  const p = config.push;
  if (p.provider === 'log') {
    return { api_key: 'log', app_id: `1:0:android:${app}`, messaging_sender_id: '0', project_id: 'log' };
  }
  if (p.provider !== 'fcm') return null;
  const appId = app === 'gandharva' ? p.appIdGandharva : p.appIdMediator;
  if (!appId || !p.apiKey || !p.senderId || !p.projectId) return null;
  return { api_key: p.apiKey, app_id: appId, messaging_sender_id: p.senderId, project_id: p.projectId };
}

export const recordedPushes = () => [...outbox];

const b64url = (buf) => Buffer.from(buf).toString('base64url');

async function accessToken() {
  if (cachedToken && cachedToken.expiresAt > Date.now() + 60_000) return cachedToken.value;
  const sa = config.push.serviceAccount;
  if (!sa?.client_email || !sa?.private_key) throw new Error('FCM_SERVICE_ACCOUNT is missing or invalid');
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claims = b64url(
    JSON.stringify({ iss: sa.client_email, scope: SCOPE, aud: TOKEN_URL, iat: now, exp: now + 3600 }),
  );
  const signer = createSign('RSA-SHA256');
  signer.update(`${header}.${claims}`);
  const assertion = `${header}.${claims}.${b64url(signer.sign(sa.private_key))}`;
  const res = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }),
  });
  const body = await res.json().catch(() => null);
  if (!res.ok || !body?.access_token) throw new Error(`token exchange failed (${res.status})`);
  cachedToken = { value: body.access_token, expiresAt: Date.now() + (body.expires_in ?? 3600) * 1000 };
  return cachedToken.value;
}

/** FCM data values must be strings; drops null/undefined. */
function stringData(data) {
  const out = {};
  for (const [k, v] of Object.entries(data)) if (v !== null && v !== undefined) out[k] = String(v);
  return out;
}

/**
 * Sends one notification to one device. Resolves to 'sent' | 'unregistered'
 * (the token is dead — delete it) | 'failed'. Never throws.
 */
export async function sendPush(device, { title, body, data = {} }) {
  const provider = config.push.provider;
  if (provider === 'off') return 'failed';
  const payloadData = stringData({ ...data, app: device.app });
  if (provider === 'log') {
    outbox.push({
      app: device.app,
      agent_id: device.agent_id ?? undefined,
      customer_id: device.customer_id ?? undefined,
      token: device.token,
      title,
      body,
      data: payloadData,
    });
    if (outbox.length > OUTBOX_MAX) outbox.splice(0, outbox.length - OUTBOX_MAX);
    return 'sent';
  }
  try {
    const res = await fetch(`https://fcm.googleapis.com/v1/projects/${config.push.projectId}/messages:send`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${await accessToken()}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        message: {
          token: device.token,
          notification: { title, body },
          data: payloadData,
          android: { priority: 'HIGH', notification: { channel_id: 'updates' } },
        },
      }),
    });
    if (res.ok) return 'sent';
    const err = await res.json().catch(() => null);
    const code = err?.error?.details?.find((d) => d.errorCode)?.errorCode ?? err?.error?.status;
    // Only a token FCM says is gone is deleted — a payload bug must not wipe every device.
    if (res.status === 404 || code === 'UNREGISTERED') return 'unregistered';
    console.error('[push] fcm rejected:', res.status, code);
    return 'failed';
  } catch (e) {
    console.error('[push] fcm unreachable:', e.message);
    return 'failed';
  }
}
