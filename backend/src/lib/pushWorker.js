// The push sender — SPEC §9.16. Every PUSH_INTERVAL_MS it rebuilds each
// registered owner's notification feed (the same functions behind the in-app
// Notifications screens) and pushes the items that appeared since the
// device's cursor. No per-route hooks: whatever the feed shows, push shows.
import { many, query } from './db.js';
import { config } from './config.js';
import { sendPush } from './push.js';
import { agentFeed } from '../routes/notifications.js';
import { customerFeed } from '../routes/customerNotifications.js';

const MAX_PER_PASS = 5;
// State reminders are shown in the app but never pushed (they would repeat).
const NEVER_PUSH = new Set(['payment_due', 'interest_expiring']);

let running = false;

const dataOf = (item) => ({
  type: item.type,
  id: item.id,
  profile_id: item.profile_id,
  customer_id: item.customer_id,
  my_profile_id: item.my_profile_id,
  interest_id: item.interest_id,
});

async function feedFor(device, cache) {
  const key = device.agent_id ? `a${device.agent_id}` : `c${device.customer_id}`;
  if (!cache.has(key)) {
    let items = [];
    if (device.agent_id) {
      if (device.agent_status !== 'suspended') {
        items = (await agentFeed({ id: device.agent_id, is_admin: device.agent_role === 'admin' })).items;
      }
    } else {
      items = (await customerFeed(device.customer_id)).items;
    }
    cache.set(key, items);
  }
  return cache.get(key);
}

/** One pass over every device. Returns {devices, sent}. Never throws. */
export async function runPushPass() {
  if (config.push.provider === 'off' || running) return { devices: 0, sent: 0 };
  running = true;
  let sent = 0;
  try {
    const devices = await many(
      `SELECT d.id, d.token, d.app, d.agent_id, d.customer_id, d.cursor_at, a.role AS agent_role, a.status AS agent_status
         FROM push_devices d LEFT JOIN agents a ON a.id = d.agent_id`,
    );
    const passStart = new Date();
    const cache = new Map();
    for (const device of devices) {
      try {
        const items = (await feedFor(device, cache)).filter((i) => {
          if (NEVER_PUSH.has(i.type) || !i.at) return false;
          const at = new Date(i.at);
          return at > device.cursor_at && at <= passStart;
        });
        const batch =
          items.length > MAX_PER_PASS
            ? [{ title: 'Mediator', body: `${items.length} new notifications`, data: { type: 'summary' } }]
            : items.map((i) => ({ title: i.title, body: i.body, data: dataOf(i) }));
        if (device.app === 'gandharva' && batch[0]?.data?.type === 'summary') batch[0].title = 'Gandharva';
        let dead = false;
        for (const msg of batch) {
          const r = await sendPush(device, msg);
          if (r === 'sent') sent++;
          if (r === 'unregistered') {
            dead = true;
            break;
          }
        }
        if (dead) await query('DELETE FROM push_devices WHERE id = $1', [device.id]);
        else await query('UPDATE push_devices SET cursor_at = $2 WHERE id = $1', [device.id, passStart]);
      } catch (e) {
        console.error('[push] device', device.id, e.message);
      }
    }
    return { devices: devices.length, sent };
  } catch (e) {
    console.error('[push] pass failed:', e.message);
    return { devices: 0, sent };
  } finally {
    running = false;
  }
}

export function startPushWorker() {
  if (config.push.provider === 'off') return;
  setInterval(() => {
    runPushPass();
  }, config.push.intervalMs).unref();
}
