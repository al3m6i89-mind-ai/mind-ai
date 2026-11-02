// Public pages: the privacy policy and how to delete an account. Google Play
// and sign-in providers (Facebook, Snapchat) need them at a public address.

const CONTACT = '5azuy2@gmail.com';
const UPDATED = '2026-11-02';

const page = (title, body) => `<!doctype html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title}</title>
<style>
  :root { --bg: #f7f7f5; --fg: #1d1d1b; --muted: #5f6360; --card: #fff; --line: #e3e3df; --accent: #357a72; }
  @media (prefers-color-scheme: dark) {
    :root { --bg: #151716; --fg: #ececea; --muted: #a3a8a5; --card: #1e2120; --line: #2e3230; --accent: #6cb8ad; }
  }
  * { box-sizing: border-box; }
  body { margin: 0; background: var(--bg); color: var(--fg); font: 16px/1.75 system-ui, -apple-system, "Segoe UI", Tahoma, sans-serif; }
  main { max-width: 760px; margin: 0 auto; padding: 28px 16px 56px; }
  h1 { font-size: 1.6rem; margin: 0 0 4px; }
  h2 { font-size: 1.12rem; margin: 26px 0 6px; color: var(--accent); }
  .meta { color: var(--muted); font-size: .9rem; margin-bottom: 18px; }
  section { background: var(--card); border: 1px solid var(--line); border-radius: 16px; padding: 6px 20px 18px; margin-bottom: 22px; }
  section[lang=en] { direction: ltr; text-align: left; }
  ul, ol { padding-inline-start: 22px; margin: 6px 0; }
  li { margin: 4px 0; }
  a { color: var(--accent); }
  nav { display: flex; gap: 14px; flex-wrap: wrap; margin-bottom: 18px; font-size: .95rem; }
</style>
</head>
<body><main>
<nav><a href="/privacy">سياسة الخصوصية · Privacy</a><a href="/delete">حذف الحساب · Delete account</a></nav>
${body}
</main></body></html>`;

const privacy = page('سياسة الخصوصية — قارئ الملفات', `
<section lang="ar">
<h1>سياسة الخصوصية — قارئ الملفات</h1>
<div class="meta">آخر تحديث: ${UPDATED}</div>
<p>تطبيق «قارئ الملفات» (File Chat) يجيب عن أسئلتك من الملفات والصور التي ترفعها. توضح هذه الصفحة ما نجمعه ولماذا.</p>
<h2>ما يبقى على هاتفك فقط</h2>
<ul>
<li>الملفات والصور التي ترفعها، والمحادثات وأسئلتك والإجابات. لا نحفظها على خوادمنا.</li>
</ul>
<h2>ما يُرسل عند السؤال</h2>
<ul>
<li>عند طرح سؤال يُرسل محتوى الملفات المرفقة ونص السؤال بشكل مشفّر (HTTPS) عبر خادمنا إلى خدمة ذكاء اصطناعي (Google Gemini أو Groq أو خدمة بديلة عند تعطلها) لقراءتها والإجابة. خادمنا يمرر الطلب ولا يحفظ محتواه.</li>
<li>عند استخدام السؤال بالصوت يُرسل التسجيل الصوتي بنفس الطريقة إلى Groq لتحويله إلى نص، ولا نحفظه.</li>
<li>هذه الخدمات تعالج البيانات حسب سياساتها الخاصة.</li>
</ul>
<h2>الحساب</h2>
<ul>
<li>تسجيل الدخول عبر Google Firebase بحساب Google أو البريد الإلكتروني. نحصل على معرّف حسابك وبريدك واسمك وصورتك إن وُجدت.</li>
</ul>
<h2>حساب الأسئلة المجانية</h2>
<ul>
<li>يحفظ خادمنا معرّف حسابك ومعرّف الجهاز وعدد أسئلتك في اليوم فقط (بدون محتوى الأسئلة)، وتُحذف هذه السجلات تلقائيًا بعد 3 أيام.</li>
</ul>
<h2>الاشتراك</h2>
<ul>
<li>الدفع يتم عبر Google Play، ولا نرى بيانات بطاقتك. نحفظ رمز الاشتراك وتاريخ انتهائه مع معرّف حسابك للتحقق منه لدى Google.</li>
</ul>
<h2>تقارير الأعطال</h2>
<ul>
<li>عند حدوث عطل يُرسل تقرير تقني إلى Firebase Crashlytics (نوع الجهاز، إصدار أندرويد والتطبيق، وتفاصيل الخطأ) لإصلاحه. لا يتضمن ملفاتك أو محادثاتك.</li>
</ul>
<h2>فحص مانع الإعلانات</h2>
<ul>
<li>يفحص التطبيق على هاتفك إن كان هناك مانع إعلانات مفعّل (DNS خاص أو VPN). نتيجة الفحص لا تُرسل لأي جهة.</li>
</ul>
<h2>ما لا نفعله</h2>
<ul>
<li>لا نبيع بياناتك ولا نشاركها للإعلانات، ولا نستخدم ملفاتك لتدريب أي نموذج.</li>
</ul>
<h2>حذف بياناتك</h2>
<ul>
<li>من التطبيق: الإعدادات ← الحساب ← حذف الحساب. يُحذف حسابك وسجل اشتراكك فورًا، وسجلات العدد خلال 3 أيام. وحذف التطبيق يحذف ملفاتك ومحادثاتك من هاتفك. التفاصيل في <a href="/delete">صفحة حذف الحساب</a>.</li>
</ul>
<h2>الأطفال</h2>
<ul><li>التطبيق غير موجّه للأطفال دون 13 عامًا.</li></ul>
<h2>التواصل</h2>
<p>لأي سؤال: <a href="mailto:${CONTACT}">${CONTACT}</a></p>
</section>

<section lang="en">
<h1>Privacy Policy — File Chat</h1>
<div class="meta">Last updated: ${UPDATED}</div>
<p>File Chat answers your questions from the files and images you upload. This page explains what we collect and why.</p>
<h2>Kept only on your phone</h2>
<ul><li>Your files, images, chats, questions and answers. We do not store them on our servers.</li></ul>
<h2>Sent when you ask</h2>
<ul>
<li>When you ask a question, the attached files' content and your question are sent encrypted (HTTPS) through our server to an AI service (Google Gemini, Groq, or a fallback service when those are down) that reads them and answers. Our server passes the request on and does not store its content.</li>
<li>Voice questions: the recording is sent the same way to Groq to be turned into text, and is not stored by us.</li>
<li>These services process data under their own policies.</li>
</ul>
<h2>Account</h2>
<ul><li>Sign-in uses Google Firebase with a Google account or email. We receive your account ID, email, and name and photo if any.</li></ul>
<h2>Counting free questions</h2>
<ul><li>Our server keeps only your account ID, a device ID and how many questions you asked each day (not their content). These records are deleted automatically after 3 days.</li></ul>
<h2>Subscription</h2>
<ul><li>Payment is handled by Google Play; we never see your card. We keep the purchase token and its expiry with your account ID to verify it with Google.</li></ul>
<h2>Crash reports</h2>
<ul><li>When the app crashes, a technical report (device model, Android and app version, error details) is sent to Firebase Crashlytics so we can fix it. It never includes your files or chats.</li></ul>
<h2>Ad-blocker check</h2>
<ul><li>The app checks on your phone whether an ad blocker (Private DNS or VPN) is on. The result is not sent anywhere.</li></ul>
<h2>What we don't do</h2>
<ul><li>We don't sell your data, share it for advertising, or use your files to train any model.</li></ul>
<h2>Deleting your data</h2>
<ul><li>In the app: Settings → Account → Delete account. Your account and subscription record are deleted right away; question counts within 3 days. Uninstalling the app removes your files and chats from your phone. See <a href="/delete">Delete account</a>.</li></ul>
<h2>Children</h2>
<ul><li>The app is not directed at children under 13.</li></ul>
<h2>Contact</h2>
<p><a href="mailto:${CONTACT}">${CONTACT}</a></p>
</section>`);

const del = page('حذف الحساب — قارئ الملفات', `
<section lang="ar">
<h1>حذف حسابك وبياناتك — قارئ الملفات</h1>
<div class="meta">آخر تحديث: ${UPDATED}</div>
<h2>من داخل التطبيق (فوري)</h2>
<ol>
<li>افتح التطبيق وسجّل الدخول.</li>
<li>اذهب إلى الإعدادات ← الحساب.</li>
<li>اضغط «حذف الحساب» وأكّد.</li>
</ol>
<p>إذا طلب منك التطبيق تسجيل الدخول من جديد، سجّل خروجك ثم ادخل وكرر الخطوات.</p>
<h2>بدون التطبيق</h2>
<p>أرسل رسالة إلى <a href="mailto:${CONTACT}?subject=Delete%20my%20File%20Chat%20account">${CONTACT}</a> من نفس البريد المسجّل، بعنوان «حذف حسابي»، وسنحذفه خلال 7 أيام.</p>
<h2>ما يُحذف</h2>
<ul>
<li>حسابك (البريد، الاسم، الصورة، معرّف الحساب).</li>
<li>سجل الاشتراك على خادمنا فورًا، وسجلات عدد الأسئلة ومعرّف الجهاز تلقائيًا خلال 3 أيام.</li>
<li>الملفات والمحادثات محفوظة على هاتفك فقط، وتُحذف بحذف التطبيق أو من قائمة المحادثات.</li>
</ul>
<h2>ما قد يبقى</h2>
<ul>
<li>سجلات الدفع لدى Google Play حسب سياسة Google. الاشتراك لا يُلغى بحذف الحساب، ألغِه من Google Play ← الاشتراكات.</li>
<li>تقارير الأعطال التقنية (بدون بيانات شخصية) تُحذف تلقائيًا من Firebase بعد 90 يومًا.</li>
</ul>
</section>

<section lang="en">
<h1>Delete your account and data — File Chat</h1>
<div class="meta">Last updated: ${UPDATED}</div>
<h2>In the app (immediate)</h2>
<ol>
<li>Open the app and sign in.</li>
<li>Go to Settings → Account.</li>
<li>Tap "Delete account" and confirm.</li>
</ol>
<p>If the app asks you to sign in again, sign out, sign back in and repeat.</p>
<h2>Without the app</h2>
<p>Email <a href="mailto:${CONTACT}?subject=Delete%20my%20File%20Chat%20account">${CONTACT}</a> from the address you signed up with, subject "Delete my account". We delete it within 7 days.</p>
<h2>What is deleted</h2>
<ul>
<li>Your account (email, name, photo, account ID).</li>
<li>The subscription record on our server right away; question counts and device ID automatically within 3 days.</li>
<li>Files and chats live only on your phone; uninstalling the app or deleting chats removes them.</li>
</ul>
<h2>What may remain</h2>
<ul>
<li>Payment records kept by Google Play under Google's policy. Deleting the account does not cancel the subscription; cancel it in Google Play → Subscriptions.</li>
<li>Technical crash reports (no personal data) are deleted automatically by Firebase after 90 days.</li>
</ul>
</section>`);

export const PAGES = { '/privacy': privacy, '/delete': del, '/': privacy };
