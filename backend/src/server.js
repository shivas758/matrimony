// Mediator (matrimony agents) + Gandharva (customers) API — see docs/SPEC.md §4 and §9
// for the route contract and CLAUDE.md for the business rules (protected "on request"
// fields, community visibility, pending gating, 15-day access expiry).

import express from 'express';
import cors from 'cors';
import rateLimit from 'express-rate-limit';
import { config } from './lib/config.js';
import { pool } from './lib/db.js';
import { errorHandler, notFoundHandler } from './middleware/error.js';
import { optionalAuth, requireActive, requireAdmin, requireAuth } from './middleware/auth.js';
import { requireCustomer } from './middleware/customerAuth.js';
import { authRouter } from './routes/auth.js';
import { mastersRouter } from './routes/masters.js';
import { profilesRouter } from './routes/profiles.js';
import { parseRouter } from './routes/parse.js';
import { photosRouter } from './routes/photos.js';
import { contactRequestsRouter, expireStaleApprovals, profileContactRouter } from './routes/contactRequests.js';
import { profileShareRouter, shareTokensRouter } from './routes/share.js';
import { holdRequestsRouter, profileHoldRouter } from './routes/holdRequests.js';
import { publicRouter } from './routes/publicPage.js';
import { profileShortlistRouter, shortlistsRouter } from './routes/shortlists.js';
import { notificationsRouter } from './routes/notifications.js';
import { meRouter } from './routes/me.js';
import { adminRouter } from './routes/admin.js';
import { customerAuthRouter } from './routes/customerAuth.js';
import { customerRouter } from './routes/customerApp.js';
import { customerNotificationsRouter } from './routes/customerNotifications.js';
import { agentPushRouter, customerPushRouter, pushConfigRouter } from './routes/push.js';
import { startPushWorker } from './lib/pushWorker.js';
import { agentChangeRouter, clientsRouter, interestsRouter } from './routes/clients.js';
import { registrationRouter } from './routes/registration.js';

const app = express();
app.set('trust proxy', 1); // behind Caddy on the Oracle VM

app.use(cors());
app.use(express.json({ limit: '2mb' }));
// The public registration form posts as a classic HTML form when it has no photos.
app.use(express.urlencoded({ extended: true, limit: '2mb' }));

app.get('/api/health', async (_req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ ok: true });
  } catch {
    res.status(500).json({ ok: false, error: 'db_unreachable' });
  }
});

// ---- public ----------------------------------------------------------------
// Throttle only the credential-checking endpoints. /auth/me runs on every app
// launch and while the pending screen polls, so limiting it would lock agents out.
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 50,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'too_many_attempts', message: 'Too many attempts. Try again in a few minutes.' },
});
app.use(
  [
    '/api/auth/login', '/api/auth/signup', '/api/auth/change-password', '/api/auth/forgot-password',
    '/api/auth/otp', '/api/customer/auth/otp', '/api/customer/auth/signup',
  ],
  authLimiter,
);
app.use('/api/auth', authRouter);
app.use('/api/masters', optionalAuth, mastersRouter);
// Push notifications (SPEC §9.16): public client options; device registration
// for agents of any status (pending agents get "you were approved" pushes).
app.use('/api/push', pushConfigRouter);
app.use('/api/push', requireAuth, agentPushRouter);
// Masked share pages — no auth by design (CLAUDE.md rule 6).
app.use('/p', publicRouter);
// Agents' public registration form (SPEC §9.3): GET renders, POST creates a
// pending customer + hidden profile. Only the POST is throttled (20/hour/IP,
// inside registration.js, with an HTML 429 page) — opening the form is free,
// so one busy shared address cannot lock a whole neighbourhood out of it.
app.use('/r', registrationRouter);

// ---- customers (Gandharva app, SPEC §9.9) ----------------------------------
// customerAuthRouter handles OTP/signup/me itself; everything else needs a
// customer token (pending customers are gated per route inside customerRouter).
app.use('/api/customer/auth', customerAuthRouter);
app.use('/api/customer/notifications', requireCustomer, customerNotificationsRouter);
app.use('/api/customer/push', requireCustomer, customerPushRouter);
app.use('/api/customer', requireCustomer, customerRouter);

// ---- agents: authenticated + admin-activated -------------------------------
const active = [requireAuth, requireActive];

app.use('/api/profiles', ...active, parseRouter); // /parse must precede the /:id routes
app.use('/api/profiles', ...active, profileContactRouter);
app.use('/api/profiles', ...active, profileHoldRouter);
app.use('/api/profiles', ...active, profileShareRouter);
app.use('/api/profiles', ...active, profileShortlistRouter);
app.use('/api/profiles', ...active, profilesRouter);
app.use('/api/photos', ...active, photosRouter);
app.use('/api/contact-requests', ...active, contactRequestsRouter);
app.use('/api/hold-requests', ...active, holdRequestsRouter);
app.use('/api/share-tokens', ...active, shareTokensRouter);
app.use('/api/shortlists', ...active, shortlistsRouter);
app.use('/api/notifications', ...active, notificationsRouter);
app.use('/api/my', ...active, meRouter);
// Customers, interests and agent transfers (SPEC §9.5 / §9.4 / §9.6).
app.use('/api/clients', ...active, clientsRouter);
app.use('/api/interests', ...active, interestsRouter);
app.use('/api/agent-change-requests', ...active, agentChangeRouter);

// ---- admin only ------------------------------------------------------------
app.use('/api/admin', requireAuth, requireActive, requireAdmin, adminRouter);

app.use(notFoundHandler);
app.use(errorHandler);

// Daily tidy-up of expired approvals. Read-time checks already treat them as
// expired; this just keeps contact_requests.status honest for the logs.
const DAY_MS = 24 * 60 * 60 * 1000;
setInterval(() => {
  expireStaleApprovals().catch((e) => console.error('[expire-job]', e.message));
}, DAY_MS).unref();

app.listen(config.port, () => {
  console.log(`API listening on :${config.port} (public base ${config.publicBaseUrl}, OTP provider ${config.otp.provider})`);
  expireStaleApprovals().catch(() => {});
  startPushWorker();
  console.log(`Push provider ${config.push.provider}`);
});
