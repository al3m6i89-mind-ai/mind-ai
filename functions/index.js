// Sends a push notification to the recipient's phones whenever a notice is
// written to /notices (a like, comment, follow, message...). Device tokens
// live in /tokens, which only this server code can read.
const { setGlobalOptions } = require("firebase-functions/v2");
const { onDocumentWritten } = require("firebase-functions/v2/firestore");
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
