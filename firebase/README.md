# ربط مجتمع Mind Ai بـ Firebase (خطوة بخطوة)

بعد هذه الخطوات يصير «مجتمع» شبكة حقيقية: كل شخص يسجّل ببريده، يأخذ ID واحد ثابت، ويرى ريلز وصور ومنشورات الآخرين من أي جوال.
كل الخطوات تتم من متصفح الجوال على https://console.firebase.google.com (افتحه بوضع «موقع سطح المكتب» إذا ظهرت الصفحة ناقصة).

## 1) أنشئ المشروع
1. ادخل بحساب Google ← **Create a project** (أو **Add project**).
2. الاسم: `mind-ai` ← وافق على الشروط ← **Continue**.
3. Google Analytics: أطفئه (غير مطلوب) ← **Create project** ← انتظر ← **Continue**.

## 2) أضف تطبيق أندرويد
1. في صفحة المشروع اضغط أيقونة **Android**.
2. **Android package name** اكتب بالضبط: `com.zuhair.chat`
3. App nickname: `Mind Ai` ← **Register app**.
4. اضغط **Download google-services.json** واحفظه (ستحتاج محتواه في الخطوة 6). بعدها اضغط **Next** ثم **Next** ثم **Continue to console** (لا تحتاج تعديل ملفات Gradle، التطبيق يتصل بدونها).

## 3) فعّل تسجيل الدخول
1. القائمة ← **Build** ← **Authentication** ← **Get started**.
2. تبويب **Sign-in method** ← **Email/Password** ← فعّل الخيار الأول **Enable** ← **Save**.

## 4) أنشئ قاعدة البيانات (Firestore)
1. **Build** ← **Firestore Database** ← **Create database**.
2. Edition: **Standard**. الموقع: اختر الأقرب لمستخدميك (مثل `me-central2 (Dammam)` للسعودية والخليج) ← **Next**.
   الموقع لا يمكن تغييره لاحقاً.
3. اختر **Start in production mode** ← **Create**.
4. افتح تبويب **Rules**، احذف كل ما فيه، والصق محتوى الملف [`firestore.rules`](firestore.rules) كاملاً ← **Publish**.

## 5) فعّل رفع الصور والفيديو (Storage)
Google تطلب الآن خطة **Blaze** لتفعيل Storage. تحتاج إضافة بطاقة، لكن الاستخدام الصغير يبقى ضمن الحصة المجانية (حوالي 5 GB تخزين). ضع **حد ميزانية** (Budget alert) حتى لا تُفاجأ.
1. **Build** ← **Storage** ← **Upgrade project** ← اختر **Blaze** وأضف وسيلة الدفع، وضع تنبيه ميزانية (مثلاً 5$).
2. **Get started** ← **Start in production mode** ← اختر نفس الموقع أو `US` ← **Done**.
3. تبويب **Rules** ← الصق محتوى [`storage.rules`](storage.rules) كاملاً ← **Publish**.

بدون هذه الخطوة يعمل كل شيء (حسابات، منشورات نصية، تعليقات، متابعة، رسائل) ما عدا رفع الصور والفيديو.

## 6) أعطِ التطبيق بيانات مشروعك
افتح `google-services.json` الذي حمّلته وانسخ منه هذه القيم إلى `lib/services/social/firebase_config.dart`:

| في firebase_config.dart | من google-services.json |
|---|---|
| `apiKey` | `client` ← `api_key` ← `current_key` |
| `appId` | `client` ← `client_info` ← `mobilesdk_app_id` |
| `messagingSenderId` | `project_info` ← `project_number` |
| `projectId` | `project_info` ← `project_id` |
| `storageBucket` | `project_info` ← `storage_bucket` |

هذه القيم ليست أسراراً (قواعد الحماية هي التي تحمي البيانات)، فيمكنك إرسالها لمساعدك ليضعها مكانك.
بعد الدفع إلى GitHub يُبنى APK جديد يتصل بخادمك.

## 7) جرّب
1. ثبّت الـ APK على جوالين (أو جوال ومحاكي).
2. في كل واحد: تبويب **مجتمع** ← **إنشاء حساب جديد** ببريد وكلمة مرور ← اختر المعرّف ← خذ الـ ID.
3. من الجوال الأول ابحث عن ID الثاني ← تابِعه ← راسله ← أعجب بمنشوره. ستظهر عنده المتابعة والإشعار والرسالة مباشرة.
4. في Firebase ← Firestore ← Data سترى المجموعات: `users` و`posts` و`comments` و`stories` و`notices` و`chats` و`messages` و`handles` و`uids`.

## كيف تعمل الحماية
- تسجيل الدخول (Firebase Auth) مربوط بـ ID واحد عبر `uids/{uid}`، ولا يمكن نقله لـ ID آخر.
- المعرّف `@handle` محجوز في `handles/{handle}` داخل معاملة واحدة، فلا يأخذه شخصان.
- على منشورات وحسابات غيرك لا تستطيع إلا إضافة أو إزالة الـ ID الخاص بك (إعجاب، حفظ، متابعة، مشاهدة مرة واحدة).
- الإشعارات يقرأها صاحبها فقط، والرسائل يقرأها طرفا المحادثة فقط.

## 8) إشعارات الدفع (تصل والتطبيق مغلق)
الإشعار يُرسَل من كود صغير على خوادم Firebase (`functions/index.js`). يراقب كل إشعار جديد ويرسله لجوال صاحبه. نشر الكود يتم من GitHub تلقائياً، بدون كمبيوتر.

1. **خطة Blaze**: الدوال (Cloud Functions) تحتاجها. الاستخدام الصغير مجاني (مليونا تشغيل شهرياً). إن لم تكن رقّيت: ⚙️ ← **Usage and billing** ← **Modify plan** ← Blaze، وضع تنبيه ميزانية.
2. **مفتاح حساب الخدمة**: ⚙️ **Project settings** ← **Service accounts** ← **Generate new private key** ← **Generate key**. يُحمَّل ملف JSON. **هذا الملف سرّي**: لا ترسله لأحد ولا ترفعه للمستودع.
3. **صلاحية النشر**: افتح https://console.cloud.google.com/iam-admin/iam?project=chat-f9edd
   ابحث عن الحساب الذي يبدأ بـ `firebase-adminsdk-` ← ✏️ ← **Add another role** ← **Owner** ← **Save**.
4. **أعطِ المفتاح لـ GitHub**: المستودع ← **Settings** ← **Secrets and variables** ← **Actions** ← **New repository secret**
   - Name: `FIREBASE_SERVICE_ACCOUNT`
   - Secret: الصق محتوى ملف JSON كاملاً ← **Add secret**.
5. **انشر**: المستودع ← **Actions** ← **Deploy Firebase (push notifications + rules)** ← **Run workflow** ← اختر الفرع ← **Run workflow**.
   ينشر الدالة وقواعد Firestore معاً (بما فيها قاعدة `tokens` الجديدة). أول مرة تأخذ 3–5 دقائق.
6. ثبّت الـ APK الجديد ← افتح «مجتمع» ← اسمح بالإشعارات.

**التجربة**: من حساب على جوال آخر تابِع حسابك أو راسله وتطبيقك مغلق، فيصل الإشعار خلال ثوانٍ. الضغط عليه يفتح المحادثة أو قائمة الإشعارات.
