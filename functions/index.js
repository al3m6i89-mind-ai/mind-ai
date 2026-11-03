// Sends a push notification to the recipient's phones whenever a notice is
// written to /notices (a like, comment, follow, message...). Device tokens
// live in /tokens, which only this server code can read.
const { setGlobalOptions } = require("firebase-functions/v2");
const { onDocumentWritten, onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

// Must match the Firestore location; the deploy workflow writes it to .env.
setGlobalOptions({ region: process.env.FN_REGION || "us-central1", maxInstances: 10 });

const db = getFirestore();

function describe(type, kind, text) {
  const k = { reel: "الريل", photo: "صورتك", post: "منشورك" }[kind] || "منشورك";
  const t = (text || "").slice(0, 120);
  switch (type) {
    case "like": return `أعجبه ${k}`;
    case "comment": return `علّق: ${t}`;
    case "reply": return `ردّ عليك: ${t}`;
    case "follow": return "بدأ بمتابعتك";
    case "repost": return `أعاد نشر ${k}`;
    case "quote": return `اقتبس منشورك: ${t}`;
    case "mention": return `أشار إليك: ${t}`;
    case "save": return `حفظ ${k}`;
    case "storyLike": return "أعجبته قصتك";
    case "message": return t || "أرسل لك رسالة";
    default: return "تفاعل جديد";
  }
}

exports.pushNotice = onDocumentWritten("notices/{noticeId}", async (event) => {
  const before = event.data.before.exists ? event.data.before.data() : null;
  const after = event.data.after.exists ? event.data.after.data() : null;
  if (!after) return; // deleted
  // Marking as read (or any rewrite of the same notice) must not ring again.
  if (before && before.createdAt === after.createdAt) return;
  if (after.read) return;

  const [toSnap, fromSnap, tokenSnap] = await Promise.all([
    db.collection("users").doc(after.toId).get(),
    db.collection("users").doc(after.fromId).get(),
    db.collection("tokens").where("id", "==", after.toId).get(),
  ]);
  if (tokenSnap.empty || !fromSnap.exists) return;
  const to = toSnap.data() || {};
  if ((to.blocked || []).includes(after.fromId)) return;

  let kind = "";
  if (after.postId) {
    const post = await db.collection("posts").doc(after.postId).get();
    kind = post.exists ? post.data().kind : "";
  }
  const from = fromSnap.data();
  const tokens = tokenSnap.docs.map((d) => d.id);
  const res = await getMessaging().sendEachForMulticast({
    tokens,
    notification: {
      title: `${from.name} (@${from.handle})`,
      body: describe(after.type, kind, after.text),
    },
    data: {
      type: String(after.type || ""),
      fromId: String(after.fromId || ""),
      postId: String(after.postId || ""),
    },
    android: {
      priority: "high",
      // Repeated likes on one post replace each other instead of piling up.
      notification: { tag: event.params.noticeId, sound: "default" },
    },
  });

  // Forget phones that uninstalled the app or signed out.
  const dead = [];
  res.responses.forEach((r, i) => {
    const code = r.error && r.error.code;
    if (code === "messaging/registration-token-not-registered" || code === "messaging/invalid-registration-token") {
      dead.push(db.collection("tokens").doc(tokens[i]).delete());
    }
  });
  await Promise.all(dead);
});

// ---------------------------------------------------------------- reports

const AUTO_HIDE_AT = 3;
const REASONS = {
  spam: "سبام", nudity: "محتوى جنسي", violence: "عنف", harassment: "تنمّر",
  hate: "كراهية", falseInfo: "تضليل", scam: "احتيال", selfHarm: "إيذاء النفس",
  copyright: "حقوق ملكية", impersonation: "انتحال", other: "سبب آخر",
};

// A new report: hide the item once enough different people report it, and
// tell the moderators.
exports.onReport = onDocumentCreated("reports/{reportId}", async (event) => {
  const r = event.data && event.data.data();
  if (!r) return;

  const open = await db.collection("reports")
    .where("targetId", "==", r.targetId)
    .where("status", "==", "open")
    .get();
  const count = open.docs.filter((d) => d.data().targetType === r.targetType).length;

  let hidden = false;
  if (count >= AUTO_HIDE_AT && (r.targetType === "post" || r.targetType === "comment")) {
    const ref = db.collection(r.targetType === "post" ? "posts" : "comments").doc(r.targetId);
    const doc = await ref.get();
    if (doc.exists && !doc.data().hidden) {
      await ref.update({ hidden: true });
      hidden = true;
    }
  }

  const admins = await db.collection("admins").get();
  const uids = admins.docs.map((d) => d.id).slice(0, 30);
  if (!uids.length) return;
  const tokenSnap = await db.collection("tokens").where("authUid", "in", uids).get();
  const tokens = tokenSnap.docs.map((d) => d.id);
  if (!tokens.length) return;
  const kind = { post: "منشور", comment: "تعليق", story: "قصة", user: "حساب" }[r.targetType] || "محتوى";
  await getMessaging().sendEachForMulticast({
    tokens,
    notification: {
      title: hidden ? `🚩 أُخفي ${kind} تلقائياً (${count} بلاغات)` : `🚩 بلاغ جديد عن ${kind}`,
      body: `${REASONS[r.reason] || r.reason}${r.note ? ": " + String(r.note).slice(0, 100) : ""}`,
    },
    data: { type: "report", targetType: String(r.targetType), targetId: String(r.targetId) },
    android: { priority: "high", notification: { tag: `report_${r.targetType}_${r.targetId}` } },
  });
});
