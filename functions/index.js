const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onCall, onRequest, HttpsError } = require('firebase-functions/v2/https');
const logger = require('firebase-functions/logger');
const admin = require('firebase-admin');
const { DateTime } = require('luxon');
const Stripe = require('stripe');

admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();
const ZONE = 'Europe/Rome';

// ─── Stripe configuration ─────────────────────────────────────────────────────
// Configurazione via variabili d'ambiente (functions/.env):
//   STRIPE_SECRET_KEY=INSERISCI_STRIPE_SECRET_KEY
//   STRIPE_WEBHOOK_SECRET=INSERISCI_STRIPE_WEBHOOK_SECRET
const STRIPE_SECRET_KEY    = process.env.STRIPE_SECRET_KEY    || '';
const STRIPE_WEBHOOK_SECRET = process.env.STRIPE_WEBHOOK_SECRET || '';

const YOUDOX_URLS = {
  tokenUrl: 'https://servizi.youdox.it/fatturazione/api/GetToken.aspx',
  exchangeEndpoint: 'https://servizi.youdox.it/fatturazione/api/ExchangeService.svc',
};

async function youdoxGetToken(credentials) {
  const body = new URLSearchParams({
    username: credentials.username,
    password: credentials.password,
    client_id: credentials.clientId,
  });
  const resp = await fetch(YOUDOX_URLS.tokenUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: body.toString(),
  });
  const json = await resp.json();
  if (!resp.ok || !json.access_token) {
    throw new Error(
      `Token error: ${json.error || 'unknown'} ${json.error_message || ''}`.trim()
    );
  }
  return json.access_token;
}

function escapeXml(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

function getXmlTag(text, tag) {
  const match = text.match(new RegExp(`<(?:[^:>]+:)?${tag}[^>]*>([\\s\\S]*?)<\\/(?:[^:>]+:)?${tag}>`));
  return match ? match[1].trim() : '';
}

async function youdoxCreateDraftCore({ uid, xml, filename, credentials }) {
  if (!xml || !filename) {
    throw new HttpsError(
      'invalid-argument',
      'Parametri mancanti: xml e filename sono obbligatori.'
    );
  }
  if (!credentials?.username || !credentials?.password || !credentials?.clientId) {
    throw new HttpsError(
      'failed-precondition',
      'Credenziali YouDOX non configurate. Vai in Impostazioni > YouDOX e inserisci username, password e Client ID.'
    );
  }
  if (Buffer.byteLength(xml, 'utf8') > 10 * 1024 * 1024) {
    throw new HttpsError('invalid-argument', 'XML superiore al limite di 10MB.');
  }

  try {
    const token = await youdoxGetToken(credentials);
    const inputBytes = Buffer.from(xml, 'utf8').toString('base64');

    const soapEnvelope = `<?xml version="1.0" encoding="utf-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:tns="http://tempuri.org/">
  <soap:Body>
    <tns:Exchange_ImportXMLToSend>
      <tns:token>${escapeXml(token)}</tns:token>
      <tns:input_bytes>${inputBytes}</tns:input_bytes>
      <tns:filename>${escapeXml(filename)}</tns:filename>
      <tns:please_validate>false</tns:please_validate>
    </tns:Exchange_ImportXMLToSend>
  </soap:Body>
</soap:Envelope>`;

    const response = await fetch(YOUDOX_URLS.exchangeEndpoint, {
      method: 'POST',
      headers: {
        'Content-Type': 'text/xml; charset=utf-8',
        'SOAPAction': '"http://tempuri.org/IExchangeService/Exchange_ImportXMLToSend"',
      },
      body: soapEnvelope,
      signal: AbortSignal.timeout(30000),
    });

    const responseText = await response.text();

    if (!response.ok) {
      throw new Error(`YouDOX SOAP HTTP ${response.status}: ${responseText.slice(0, 200)}`);
    }

    const isError = getXmlTag(responseText, 'IsErrorExchange') === 'true';
    const message = getXmlTag(responseText, 'Message');
    const errorCode = getXmlTag(responseText, 'ErrorCode');
    const resultFilename = getXmlTag(responseText, 'Filename') || filename;

    if (isError) {
      throw new HttpsError(
        'internal',
        `YouDOX draft error${errorCode ? ` (${errorCode})` : ''}: ${message || 'errore sconosciuto'}`
      );
    }

    return { ok: true, filename: resultFilename, message };
  } catch (error) {
    logger.error('youdoxCreateDraft failed', {
      uid,
      filename,
      error: String(error),
    });
    if (error instanceof HttpsError) {
      throw error;
    }
    throw new HttpsError(
      'internal',
      `Errore durante creazione bozza YouDOX: ${String(error)}`
    );
  }
}

exports.youdoxCreateDraft = onCall(
  {
    region: 'europe-west1',
    memory: '256MiB',
    timeoutSeconds: 60,
    cors: true,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Autenticazione richiesta.');
    }

    const xml = String(request.data?.xml || '').trim();
    const filename = String(request.data?.filename || '').trim();
    const credentials = request.data?.credentials ?? null;
    return youdoxCreateDraftCore({ uid: request.auth.uid, xml, filename, credentials });
  }
);

exports.youdoxCreateDraftHttp = onRequest(
  {
    region: 'europe-west1',
    memory: '256MiB',
    timeoutSeconds: 60,
    invoker: 'public',
  },
  async (req, res) => {
    res.set('Access-Control-Allow-Origin', '*');
    res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
    res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }
    if (req.method !== 'POST') {
      res.status(405).json({ ok: false, error: 'Method not allowed' });
      return;
    }

    try {
      const authHeader = String(req.headers.authorization || '');
      const token = authHeader.startsWith('Bearer ')
        ? authHeader.slice('Bearer '.length).trim()
        : '';
      if (!token) {
        res.status(401).json({ ok: false, error: 'Autenticazione richiesta.' });
        return;
      }
      const decoded = await admin.auth().verifyIdToken(token);
      const payload = typeof req.body === 'object' && req.body !== null
        ? req.body
        : JSON.parse(req.rawBody?.toString('utf8') || '{}');
      const xml = String(payload.xml || '').trim();
      const filename = String(payload.filename || '').trim();
      const credentials = payload.credentials ?? null;
      const result = await youdoxCreateDraftCore({
        uid: decoded.uid,
        xml,
        filename,
        credentials,
      });
      res.status(200).json(result);
    } catch (error) {
      const message =
        error instanceof HttpsError ? error.message : `Errore: ${String(error)}`;
      res.status(500).json({ ok: false, error: message });
    }
  }
);

exports.sendDailyBriefAt8 = onSchedule(
  {
    schedule: '0 8 * * *',
    timeZone: ZONE,
    region: 'europe-west1',
    retryCount: 1,
    memory: '256MiB',
  },
  async () => {
    const now = DateTime.now().setZone(ZONE);
    const dayStart = now.startOf('day');
    const dayEnd = dayStart.plus({ days: 1 });
    const dayKey = dayStart.toFormat('yyyy-MM-dd');

    logger.info('Daily brief start', { dayKey, zone: ZONE });

    const usersSnap = await db.collection('users').get();
    let sentUsers = 0;
    let skippedUsers = 0;

    for (const userDoc of usersSnap.docs) {
      const userId = userDoc.id;
      const lockRef = userDoc.ref
        .collection('notificationLogs')
        .doc(`daily-brief-${dayKey}`);

      const lockAcquired = await db.runTransaction(async (tx) => {
        const lock = await tx.get(lockRef);
        if (lock.exists) {
          return false;
        }
        tx.set(lockRef, {
          type: 'dailyBrief',
          dayKey,
          status: 'pending',
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return true;
      });

      if (!lockAcquired) {
        skippedUsers += 1;
        continue;
      }

      try {
        const tokensSnap = await userDoc.ref.collection('pushTokens').get();
        const tokens = tokensSnap.docs
          .map((doc) => String(doc.get('token') || '').trim())
          .filter((token) => token.length > 0);

        if (tokens.length === 0) {
          await lockRef.set(
            {
              status: 'no_tokens',
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true }
          );
          continue;
        }

        const slotsSnap = await userDoc.ref
          .collection('timelineSlots')
          .where('date', '>=', dayStart.toJSDate())
          .where('date', '<', dayEnd.toJSDate())
          .get();

        const slots = slotsSnap.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
        const totalHours = slots.reduce(
          (sum, slot) => sum + Number(slot.plannedHours || 0),
          0
        );

        const taskIds = [...new Set(slots.map((slot) => String(slot.taskId || '').trim()).filter(Boolean))];
        const taskNamesById = new Map();
        if (taskIds.length > 0) {
          const taskRefs = taskIds.map((taskId) => userDoc.ref.collection('tasks').doc(taskId));
          const taskDocs = await db.getAll(...taskRefs);
          for (const taskDoc of taskDocs) {
            if (!taskDoc.exists) {
              continue;
            }
            const name = String(taskDoc.get('name') || '').trim();
            if (name) {
              taskNamesById.set(taskDoc.id, name);
            }
          }
        }

        const focus = [];
        for (const slot of slots) {
          const taskId = String(slot.taskId || '').trim();
          const name = taskNamesById.get(taskId);
          if (!name || focus.includes(name)) {
            continue;
          }
          focus.push(name);
          if (focus.length >= 3) {
            break;
          }
        }

        const title = 'Brief giornaliero';
        const body = slots.length === 0
          ? 'Nessuna attività pianificata per oggi.'
          : `${slots.length} attività, ${totalHours.toFixed(1)}h. ${focus.length ? `Focus: ${focus.join(', ')}` : ''}`.trim();

        const multicast = {
          tokens,
          notification: { title, body },
          data: {
            type: 'daily_brief',
            dayKey,
            click_action: 'FLUTTER_NOTIFICATION_CLICK',
          },
          apns: {
            payload: {
              aps: {
                sound: 'default',
                badge: 1,
              },
            },
          },
        };

        const resp = await messaging.sendEachForMulticast(multicast);

        const invalidTokens = [];
        resp.responses.forEach((r, index) => {
          if (r.success) {
            return;
          }
          const code = String(r.error?.code || '');
          if (
            code.includes('registration-token-not-registered') ||
            code.includes('invalid-registration-token') ||
            code.includes('invalid-argument')
          ) {
            invalidTokens.push(tokens[index]);
          }
        });

        if (invalidTokens.length > 0) {
          const batch = db.batch();
          for (const bad of invalidTokens) {
            batch.delete(userDoc.ref.collection('pushTokens').doc(bad));
          }
          await batch.commit();
        }

        await lockRef.set(
          {
            status: 'sent',
            sentAt: admin.firestore.FieldValue.serverTimestamp(),
            slotsCount: slots.length,
            totalHours: Number(totalHours.toFixed(2)),
            successCount: resp.successCount,
            failureCount: resp.failureCount,
          },
          { merge: true }
        );

        sentUsers += 1;
      } catch (error) {
        logger.error('Daily brief failed for user', { userId, error });
        await lockRef.set(
          {
            status: 'error',
            error: String(error),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
      }
    }

    logger.info('Daily brief completed', {
      dayKey,
      users: usersSnap.size,
      sentUsers,
      skippedUsers,
    });
  }
);

// ─── Stripe Webhook ───────────────────────────────────────────────────────────
// Endpoint: POST /stripeWebhook
// Configura in Stripe Dashboard → Webhooks → Add endpoint:
//   URL: https://REGION-PROJECT.cloudfunctions.net/stripeWebhook (oppure Cloud Run URL)
//   Events: customer.subscription.created, .updated, .deleted, invoice.payment_succeeded, invoice.payment_failed

exports.stripeWebhook = onRequest(
  {
    region: 'europe-west1',
    memory: '256MiB',
    timeoutSeconds: 60, // più lungo per checkout.session.completed (crea account + invia email)
    invoker: 'public',
  },
  async (req, res) => {
    if (req.method !== 'POST') {
      res.status(405).send('Method Not Allowed');
      return;
    }

    if (!STRIPE_SECRET_KEY || !STRIPE_WEBHOOK_SECRET) {
      logger.error('Stripe keys not configured');
      res.status(500).json({ error: 'Stripe not configured' });
      return;
    }

    const stripe = new Stripe(STRIPE_SECRET_KEY, { apiVersion: '2024-04-10' });

    let event;
    try {
      const sig = req.headers['stripe-signature'];
      const rawBody = req.rawBody;
      event = stripe.webhooks.constructEvent(rawBody, sig, STRIPE_WEBHOOK_SECRET);
    } catch (err) {
      logger.warn('Stripe signature verification failed', { error: String(err) });
      res.status(400).json({ error: `Webhook Error: ${err.message}` });
      return;
    }

    try {
      await handleStripeEvent(event);
      res.status(200).json({ received: true });
    } catch (err) {
      logger.error('Stripe webhook handler failed', { event: event.type, error: String(err) });
      res.status(500).json({ error: String(err) });
    }
  }
);

/**
 * Mappa l'evento Stripe al documento Firestore del team.
 * Il metadata.teamId del piano/subscription deve essere impostato in Stripe.
 */
async function handleStripeEvent(event) {
  const object = event.data.object;
  const stripe = new Stripe(STRIPE_SECRET_KEY, { apiVersion: '2024-04-10' });

  switch (event.type) {

    // ── Primo acquisto via Payment Link ───────────────────────────────────────
    case 'checkout.session.completed': {
      if (object.payment_status !== 'paid' && object.mode !== 'subscription') {
        break;
      }

      const customerEmail = object.customer_details?.email || object.customer_email;
      const customerName  = object.customer_details?.name  || '';
      const subscriptionId = object.subscription;
      const stripeCustomerId = object.customer;

      if (!customerEmail) {
        logger.error('checkout.session.completed: no customer email', { session: object.id });
        break;
      }

      // Recupera la subscription Stripe per avere il price ID e lo stato
      let subData = null;
      let planId = 'base';
      let currentPeriodEnd = null;
      if (subscriptionId) {
        try {
          subData = await stripe.subscriptions.retrieve(subscriptionId);
          planId  = _stripePriceToLocalPlan(subData.items?.data?.[0]?.price?.id);
          currentPeriodEnd = subData.current_period_end
            ? new Date(subData.current_period_end * 1000) : null;
        } catch (e) {
          logger.warn('Could not retrieve subscription', { subscriptionId, error: String(e) });
        }
      }

      // ── Crea account Firebase se non esiste ──────────────────────────────
      let uid;
      let isNewUser = false;
      let resetLink;

      try {
        const existing = await admin.auth().getUserByEmail(customerEmail);
        uid = existing.uid;
        logger.info('User already exists', { email: customerEmail, uid });
      } catch (_) {
        // Utente non esiste → crealo
        const tmpPassword = _generatePassword();
        const newUser = await admin.auth().createUser({
          email: customerEmail,
          password: tmpPassword,
          displayName: customerName || customerEmail.split('@')[0],
          emailVerified: true,
        });
        uid = newUser.uid;
        isNewUser = true;
        logger.info('Firebase user created', { email: customerEmail, uid });
      }

      // Genera link reset password per l'utente
      try {
        resetLink = await admin.auth().generatePasswordResetLink(customerEmail, {
          url: 'https://business.gweb.agency/nexora/app/',
        });
      } catch (e) {
        logger.warn('Could not generate password reset link', { error: String(e) });
        resetLink = 'https://business.gweb.agency/nexora/app/';
      }

      // ── Crea/aggiorna team in Firestore ──────────────────────────────────
      const teamId = `team-${uid.substring(0, 8)}-${Date.now().toString(36)}`;

      // Cerca se l'utente ha già un team
      const userDoc = await db.collection('users').doc(uid).get();
      const existingTeamId = userDoc.exists ? userDoc.data()?.teamId : null;
      const effectiveTeamId = existingTeamId || teamId;

      const subPayload = {
        planId,
        status: 'active',
        stripeCustomerId,
        stripeSubscriptionId: subscriptionId || null,
        cancelAtPeriodEnd: false,
        currentPeriodEnd: currentPeriodEnd
          ? admin.firestore.Timestamp.fromDate(currentPeriodEnd)
          : null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      if (!existingTeamId) {
        // Crea nuovo team
        await db.collection('teams').doc(effectiveTeamId).set({
          name: customerName || customerEmail.split('@')[0],
          ownerId: uid,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          subscription: subPayload,
        });

        // Aggiunge il proprietario come membro
        await db.collection('teams').doc(effectiveTeamId)
          .collection('members').doc(uid).set({
            userId: uid,
            email: customerEmail,
            displayName: customerName || '',
            role: 'Owner',
            status: 'active',
            joinedAt: admin.firestore.FieldValue.serverTimestamp(),
          });

        // Profilo utente
        await db.collection('users').doc(uid).set({
          teamId: effectiveTeamId,
          email: customerEmail,
          displayName: customerName || '',
          role: 'Owner',
        }, { merge: true });

      } else {
        // Team già esistente → aggiorna solo la subscription
        await db.collection('teams').doc(effectiveTeamId).set(
          { subscription: subPayload },
          { merge: true }
        );
      }

      // ── Invia email con credenziali ────────────────────────────────────
      if (isNewUser) {
        await _sendWelcomeEmail({ email: customerEmail, name: customerName, resetLink, planId });
      } else {
        await _sendSubscriptionReactivatedEmail({ email: customerEmail, name: customerName, planId });
      }

      logger.info('checkout.session.completed handled', {
        email: customerEmail, uid, teamId: effectiveTeamId, planId, isNewUser,
      });
      break;
    }

    // ── Aggiornamento subscription (cambio piano, rinnovo) ────────────────
    case 'customer.subscription.created':
    case 'customer.subscription.updated': {
      const teamId = await _findTeamByStripeCustomer(object.customer);
      if (!teamId) {
        logger.warn('No team found for customer', { customerId: object.customer });
        break;
      }

      const planId = _stripePriceToLocalPlan(object.items?.data?.[0]?.price?.id);
      const status = _stripeStatusToLocal(object.status);
      const currentPeriodEnd = object.current_period_end
        ? new Date(object.current_period_end * 1000) : null;

      await db.collection('teams').doc(teamId).set({
        subscription: {
          planId, status,
          stripeCustomerId:     object.customer,
          stripeSubscriptionId: object.id,
          cancelAtPeriodEnd: object.cancel_at_period_end || false,
          currentPeriodEnd: currentPeriodEnd
            ? admin.firestore.Timestamp.fromDate(currentPeriodEnd)
            : null,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
      }, { merge: true });

      logger.info('Subscription updated', { teamId, status, planId });
      break;
    }

    // ── Cancellazione subscription ────────────────────────────────────────
    case 'customer.subscription.deleted': {
      const teamId = await _findTeamByStripeCustomer(object.customer);
      if (!teamId) break;
      await db.collection('teams').doc(teamId).set({
        subscription: {
          status: 'cancelled',
          cancelAtPeriodEnd: false,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
      }, { merge: true });
      logger.info('Subscription cancelled', { teamId });
      break;
    }

    // ── Pagamento riuscito (rinnovo) ──────────────────────────────────────
    case 'invoice.payment_succeeded': {
      if (object.billing_reason === 'subscription_cycle') {
        const teamId = await _findTeamByStripeCustomer(object.customer);
        if (!teamId) break;
        await db.collection('teams').doc(teamId).set({
          subscription: { status: 'active', updatedAt: admin.firestore.FieldValue.serverTimestamp() },
        }, { merge: true });
      }
      break;
    }

    // ── Pagamento fallito ─────────────────────────────────────────────────
    case 'invoice.payment_failed': {
      const teamId = await _findTeamByStripeCustomer(object.customer);
      if (!teamId) break;
      await db.collection('teams').doc(teamId).set({
        subscription: { status: 'past_due', updatedAt: admin.firestore.FieldValue.serverTimestamp() },
      }, { merge: true });
      logger.warn('Payment failed', { customerId: object.customer });
      break;
    }

    default:
      logger.info('Unhandled Stripe event', { type: event.type });
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────────

/** Trova il teamId dal customerId Stripe cercando nei team di Firestore. */
async function _findTeamByStripeCustomer(stripeCustomerId) {
  if (!stripeCustomerId) return null;
  const snap = await db.collection('teams')
    .where('subscription.stripeCustomerId', '==', stripeCustomerId)
    .limit(1)
    .get();
  if (snap.empty) return null;
  return snap.docs[0].id;
}

/** Genera una password casuale sicura (12 caratteri). */
function _generatePassword() {
  const chars = 'ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789!@#';
  return Array.from({ length: 12 }, () => chars[Math.floor(Math.random() * chars.length)]).join('');
}

/** Invia email di benvenuto con link per impostare la password. */
async function _sendWelcomeEmail({ email, name, resetLink, planId }) {
  const planLabels = { base: 'Base', pro: 'Pro', enterprise: 'Enterprise' };
  const planLabel = planLabels[planId] || 'Base';
  const displayName = name || email.split('@')[0];

  const body = `Ciao ${displayName},

benvenuto su G-Flux! 🎉

Il tuo abbonamento al piano ${planLabel} è stato attivato con successo.

Per accedere alla piattaforma, imposta la tua password cliccando sul link qui sotto:

${resetLink}

Il link è valido per 24 ore. Dopo aver impostato la password, potrai accedere con la tua email (${email}).

━━━━━━━━━━━━━━━━━━━━━━━━
🔗 Accedi alla piattaforma: https://business.gweb.agency/nexora/app/
━━━━━━━━━━━━━━━━━━━━━━━━

Hai bisogno di aiuto? Rispondi a questa email.

Il team G-Flux`;

  try {
    await fetch('https://business.gweb.agency/archivio/api/send_ticket.php', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        to: email,
        subject: `Benvenuto su G-Flux — Imposta la tua password`,
        body,
        attachments: [],
        signatureHtml: '',
      }),
    });
    logger.info('Welcome email sent', { email });
  } catch (e) {
    logger.error('Failed to send welcome email', { email, error: String(e) });
  }
}

/** Email per utenti già esistenti che rinnovano/riattivano. */
async function _sendSubscriptionReactivatedEmail({ email, name, planId }) {
  const planLabels = { base: 'Base', pro: 'Pro', enterprise: 'Enterprise' };
  const planLabel = planLabels[planId] || 'Base';
  const displayName = name || email.split('@')[0];

  const body = `Ciao ${displayName},

il tuo abbonamento G-Flux al piano ${planLabel} è stato attivato! ✅

Puoi accedere subito alla piattaforma con le tue credenziali:
https://business.gweb.agency/nexora/app/

Il team G-Flux`;

  try {
    await fetch('https://business.gweb.agency/archivio/api/send_ticket.php', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        to: email,
        subject: `Abbonamento G-Flux attivato — Piano ${planLabel}`,
        body,
        attachments: [],
        signatureHtml: '',
      }),
    });
  } catch (e) {
    logger.error('Failed to send reactivation email', { email, error: String(e) });
  }
}

// Mappa l'ID price Stripe al piano locale.
function _stripePriceToLocalPlan(priceId) {
  const priceMap = {
    // Hardcoded + override da .env
    'price_1TQURIB5LyNpr8Vp4M5HMCUR': 'base',
    'price_1TQURZB5LyNpr8Vpq6No1pY0': 'pro',
    'price_1TQURuB5LyNpr8VpfZVw5g6e': 'enterprise',
    // Override da variabili d'ambiente (ha priorità)
    ...(process.env.STRIPE_PRICE_BASE       ? { [process.env.STRIPE_PRICE_BASE]:       'base' }       : {}),
    ...(process.env.STRIPE_PRICE_PRO        ? { [process.env.STRIPE_PRICE_PRO]:        'pro' }        : {}),
    ...(process.env.STRIPE_PRICE_ENTERPRISE ? { [process.env.STRIPE_PRICE_ENTERPRISE]: 'enterprise' } : {}),
  };
  return priceMap[priceId] || 'base';
}

function _stripeStatusToLocal(stripeStatus) {
  switch (stripeStatus) {
    case 'active':    return 'active';
    case 'trialing':  return 'trialing';
    case 'past_due':  return 'pastDue';
    case 'canceled':
    case 'cancelled': return 'cancelled';
    default:          return 'none';
  }
}
