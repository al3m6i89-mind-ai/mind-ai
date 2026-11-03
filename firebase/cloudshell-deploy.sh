#!/bin/bash
# Deploys the Mind Ai push-notification function and the Firestore rules to
# chat-f9edd from Google Cloud Shell (console.cloud.google.com, the >_ icon),
# using your own Google account: no service-account key needed.
# Paste this whole file into Cloud Shell and press Enter.
set -e
PROJECT=chat-f9edd
rm -rf ~/mindai-deploy && mkdir -p ~/mindai-deploy/functions ~/mindai-deploy/firebase && cd ~/mindai-deploy
gcloud config set project "$PROJECT" >/dev/null

cat > firebase.json <<'__MINDAI_CFG__'
{
  "firestore": { "rules": "firebase/firestore.rules" },
  "functions": [{ "source": "functions", "codebase": "default", "runtime": "nodejs20" }]
}
__MINDAI_CFG__

cat > functions/package.json <<'__MINDAI_PKG__'
{
  "name": "mind-ai-functions",
  "description": "Push notifications for the Mind Ai Community",
  "private": true,
  "main": "index.js",
  "engines": { "node": "20" },
  "dependencies": {
    "firebase-admin": "^13.4.0",
    "firebase-functions": "^6.4.0"
  }
}
__MINDAI_PKG__

cat > functions/index.js <<'__MINDAI_JS__'
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
__MINDAI_JS__

cat > firebase/firestore.rules <<'__MINDAI_RULES__'
rules_version = '2';

// Security rules for the Mind Ai Community.
// Paste into Firebase console → Firestore Database → Rules → Publish.
//
// One login (Firebase Auth) = one unified ID (MA-XXXX-XXXX-X), linked in /uids.
// Everyone signed in can read the public data; each person can only write
// their own things, and on other people's documents can only add or remove
// their own ID (a like, a follow, a view), never anything else.
service cloud.firestore {
  match /databases/{database}/documents {

    function signedIn() {
      return request.auth != null;
    }

    // The unified ID of the person making the request.
    function myId() {
      return get(/databases/$(database)/documents/uids/$(request.auth.uid)).data.id;
    }

    function changed() {
      return request.resource.data.diff(resource.data).affectedKeys();
    }

    // An array changed only by adding or removing the requester's own ID.
    function onlyMe(field) {
      let before = resource.data.get(field, []).toSet();
      let after = request.resource.data.get(field, []).toSet();
      let me = [myId()].toSet();
      return after == before.union(me) || after == before.difference(me);
    }

    function onlyMeRemoved(field) {
      return request.resource.data.get(field, []).toSet()
        == resource.data.get(field, []).toSet().difference([myId()].toSet());
    }

    // ---------------------------------------------------------------- identity

    match /uids/{uid} {
      allow read: if signedIn() && request.auth.uid == uid;
      // Linked once, never moved to another ID.
      allow create: if signedIn() && request.auth.uid == uid
        && request.resource.data.keys().hasOnly(['id']);
    }

    match /handles/{handle} {
      allow read: if signedIn();
      allow create: if signedIn()
        && request.resource.data.id == getAfter(/databases/$(database)/documents/uids/$(request.auth.uid)).data.id;
      allow update: if signedIn() && resource.data.id == myId() && request.resource.data.id == myId();
      allow delete: if signedIn() && resource.data.id == myId();
    }

    match /users/{id} {
      allow read: if signedIn();
      allow create: if signedIn()
        && request.resource.data.id == id
        && request.resource.data.authUid == request.auth.uid
        && request.resource.data.verified == false
        && getAfter(/databases/$(database)/documents/uids/$(request.auth.uid)).data.id == id
        && getAfter(/databases/$(database)/documents/handles/$(request.resource.data.handle)).data.id == id;
      allow update: if signedIn() && (
        // The owner edits their profile; the ID, login link and badge stay fixed,
        // and a new @handle must already be claimed by them.
        (resource.data.authUid == request.auth.uid
          && !changed().hasAny(['id', 'authUid', 'verified', 'joined', 'local'])
          && (!changed().hasAny(['handle'])
            || getAfter(/databases/$(database)/documents/handles/$(request.resource.data.handle)).data.id == id))
        // Someone else follows / unfollows: only their own ID in "followers".
        || (changed().hasOnly(['followers']) && onlyMe('followers'))
        // Someone blocks them: removes only their own ID from "following".
        || (changed().hasOnly(['following']) && onlyMeRemoved('following'))
      );
      allow delete: if false;
    }

    // ---------------------------------------------------------------- content

    match /posts/{pid} {
      allow read: if signedIn();
      allow create: if signedIn()
        && request.resource.data.id == pid
        && request.resource.data.authorId == myId()
        && request.resource.data.kind in ['reel', 'photo', 'post']
        && request.resource.data.text.size() <= 2200
        && (request.resource.data.kind != 'post' || request.resource.data.text.size() <= 280)
        && request.resource.data.likes.size() == 0
        && request.resource.data.saves.size() == 0
        && request.resource.data.viewers.size() == 0
        && request.resource.data.views == 0
        && request.resource.data.shares == 0;
      allow update: if signedIn() && (
        (resource.data.authorId == myId() && changed().hasOnly(['text', 'commentsOff']))
        || (changed().hasOnly(['likes']) && onlyMe('likes'))
        || (changed().hasOnly(['saves']) && onlyMe('saves'))
        // A view counts once per person.
        || (changed().hasOnly(['viewers', 'views'])
          && !(myId() in resource.data.viewers)
          && request.resource.data.viewers.toSet() == resource.data.viewers.toSet().union([myId()].toSet())
          && request.resource.data.views == resource.data.views + 1)
        || (changed().hasOnly(['shares']) && request.resource.data.shares == resource.data.shares + 1)
      );
      allow delete: if signedIn() && resource.data.authorId == myId();
    }

    match /comments/{cid} {
      allow read: if signedIn();
      allow create: if signedIn()
        && request.resource.data.id == cid
        && request.resource.data.authorId == myId()
        && request.resource.data.text.size() <= 500
        && request.resource.data.likes.size() == 0
        && get(/databases/$(database)/documents/posts/$(request.resource.data.postId)).data.get('commentsOff', false) == false;
      allow update: if signedIn() && changed().hasOnly(['likes']) && onlyMe('likes');
      // The writer, or the owner of the post.
      allow delete: if signedIn() && (resource.data.authorId == myId()
        || get(/databases/$(database)/documents/posts/$(resource.data.postId)).data.authorId == myId());
    }

    match /stories/{sid} {
      allow read: if signedIn();
      allow create: if signedIn() && request.resource.data.authorId == myId()
        && request.resource.data.seenBy.size() == 0 && request.resource.data.likes.size() == 0;
      allow update: if signedIn() && (
        (changed().hasOnly(['seenBy']) && onlyMe('seenBy'))
        || (changed().hasOnly(['likes']) && onlyMe('likes'))
      );
      allow delete: if signedIn() && resource.data.authorId == myId();
    }

    // ---------------------------------------------------------------- push notifications

    // A phone's push token, so the server can reach it. Only the server reads these.
    match /tokens/{token} {
      allow read: if false;
      allow create, update: if signedIn()
        && request.resource.data.authUid == request.auth.uid
        && request.resource.data.id == myId();
      allow delete: if signedIn() && resource.data.authUid == request.auth.uid;
    }

    // ---------------------------------------------------------------- notifications & messages

    match /notices/{nid} {
      allow read: if signedIn() && resource.data.toId == myId();
      allow create: if signedIn() && request.resource.data.fromId == myId() && request.resource.data.toId != myId();
      allow update: if signedIn() && (
        (resource.data.fromId == myId() && request.resource.data.fromId == myId()
          && request.resource.data.toId == resource.data.toId)
        || (resource.data.toId == myId() && changed().hasOnly(['read']))
      );
      allow delete: if signedIn() && (resource.data.toId == myId() || resource.data.fromId == myId());
    }

    match /chats/{key} {
      allow read: if signedIn() && myId() in resource.data.members;
      allow create: if signedIn() && myId() in request.resource.data.members
        && request.resource.data.members.size() == 2;
      // Each person only moves their own "read up to" mark.
      allow update: if signedIn() && myId() in resource.data.members
        && changed().hasOnly(['readAt'])
        && request.resource.data.readAt.diff(resource.data.get('readAt', {})).affectedKeys().hasOnly([myId()]);
    }

    match /messages/{mid} {
      allow read: if signedIn() && myId() in resource.data.members;
      allow create: if signedIn()
        && request.resource.data.fromId == myId()
        && myId() in request.resource.data.members
        && request.resource.data.members.size() == 2
        && request.resource.data.text.size() <= 1000;
      allow update, delete: if false;
    }
  }
}
__MINDAI_RULES__

# The function must run where the database lives.
LOC=$(gcloud firestore databases describe --database='(default)' --format='value(locationId)' 2>/dev/null || true)
case "$LOC" in
  nam5|"") REGION=us-central1 ;;
  nam7) REGION=us-east4 ;;
  eur3) REGION=europe-west1 ;;
  *) REGION=$LOC ;;
esac
echo "FN_REGION=$REGION" > functions/.env
echo ">> Firestore: ${LOC:-?}  ->  function region: $REGION"

(cd functions && npm install --omit=dev --no-audit --no-fund --loglevel=error)
npx --yes firebase-tools@14 deploy --only functions,firestore:rules --project "$PROJECT" --force
echo ">> DONE: push notifications are live."
