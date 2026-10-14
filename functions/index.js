const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
admin.initializeApp();
const db = admin.firestore();

const BASE_URL = process.env.BASE_URL || "https://YOUR-PROJECT.web.app";
const MIN_PER_PARTY = 10; // average minutes each party ahead adds

// MSG91 flow SMS. Needs a DLT-approved template. Set MSG91_KEY and MSG91_TEMPLATE in functions/.env
async function sms(phone, vars) {
  if (!process.env.MSG91_KEY) return console.log("SMS skipped (no key):", phone, vars);
  await fetch("https://control.msg91.com/api/v5/flow", {
    method: "POST",
    headers: { authkey: process.env.MSG91_KEY, "content-type": "application/json" },
    body: JSON.stringify({
      template_id: process.env.MSG91_TEMPLATE,
      recipients: [{ mobiles: "91" + phone, ...vars }],
    }),
  });
}

// Recompute positions + ETA, publish public status docs, send SMS on key events
exports.onQueueWrite = onDocumentWritten("restaurants/{rid}/queue/{qid}", async (e) => {
  const { rid, qid } = e.params;
  const before = e.data.before.exists ? e.data.before.data() : null;
  const after = e.data.after.exists ? e.data.after.data() : null;
  const day = (after || before).day;
  const rest = (await db.doc(`restaurants/${rid}`).get()).data() || {};
  const snap = await db.collection(`restaurants/${rid}/queue`).where("day", "==", day).get();
  const docs = snap.docs.map((d) => ({ id: d.id, rid, ...d.data() }));
  const waiting = docs.filter((x) => x.status === "waiting").sort((a, b) => a.token - b.token);

  const batch = db.batch();
  for (const x of docs) {
    const idx = waiting.findIndex((w) => w.id === x.id);
    batch.set(db.doc(`status/${x.id}`), {
      rid,
      restaurant: rest.name || "Restaurant",
      token: x.token,
      name: x.name,
      pax: x.pax,
      status: x.status,
      position: idx >= 0 ? idx + 1 : 0,
      etaMin: idx >= 0 ? (idx + 1) * MIN_PER_PARTY + (x.extraMin || 0) : 0,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();

  if (!after) return;
  const link = `${BASE_URL}/q/${qid}`;
  const vars = { name: after.name, token: "T" + after.token, restaurant: rest.name || "Restaurant", link };
  if (!before) await sms(after.phone, { ...vars, type: "joined" });
  else if (before.status !== "notified" && after.status === "notified") await sms(after.phone, { ...vars, type: "ready" });
  else if ((before.extraMin || 0) < (after.extraMin || 0)) await sms(after.phone, { ...vars, type: "delay" });
});

// Customer taps "Cancel my spot" on the status page
exports.customerCancel = onCall(async (req) => {
  const id = req.data && req.data.id;
  if (typeof id !== "string" || id.length !== 16) throw new HttpsError("invalid-argument", "bad id");
  const s = (await db.doc(`status/${id}`).get()).data();
  if (!s) throw new HttpsError("not-found", "unknown");
  const ref = db.doc(`restaurants/${s.rid}/queue/${id}`);
  if ((await ref.get()).get("status") === "waiting") await ref.update({ status: "cancelled" });
  return { ok: true };
});
