# قارئ الملفات (تطبيق Android مستقل)

تطبيق هاتف يعمل وحده بدون كمبيوتر أو خادم: ترفق ملفاً أو صورة وتسأل عنه، فيجيبك الذكاء الاصطناعي من محتوى الملف فقط مع ذكر المصدر (الصفحة أو الشريحة أو الورقة والخلية).

## ماذا يدعم
- PDF وWord (DOCX) وPowerPoint (PPTX) وExcel (XLSX) وTXT وCSV وMarkdown وصور JPG وPNG وWEBP، حتى 15 ميجابايت للملف.
- نصوص Word وPowerPoint وExcel تُستخرج على الهاتف نفسه. ملفات PDF والصور يقرؤها Gemini مباشرة (بما فيها الصور والنصوص الممسوحة).
- محادثات متعددة محفوظة على الهاتف: بحث وإعادة تسمية وحذف، وحذف ملف من محادثة، وفتح الملف الأصلي.
- إيقاف الرد أثناء الكتابة، وإعادة المحاولة، ونسخ الرد.
- عربي وإنجليزي، ووضع نهاري وليلي وتلقائي.

## الذكاء الاصطناعي
- **Gemini (موصى به):** مفتاح مجاني من https://aistudio.google.com/apikey يُلصق في الإعدادات. يقرأ كل الأنواع بما فيها PDF والصور.
- **مجاني بدون مفتاح:** يعمل فوراً، لكنه نصي فقط ولا يقرأ PDF أو الصور.
المفتاح يُحفظ على الهاتف فقط ويُرسل إلى Google مباشرة.

## هيكل المشروع
- `lib/core/extract.dart` فحص نوع الملف الحقيقي واستخراج النصوص.
- `lib/core/ai.dart` الاتصال بـ Gemini والوضع المجاني، وتعليمات «أجب من الملفات فقط».
- `lib/core/store.dart` المحادثات والملفات والإعدادات.
- `lib/ui/` الشاشات: المحادثة، بطاقات الملفات، الرسائل، الإعدادات.
- `test/` اختبارات الاستخراج والواجهة.

## التطوير والبناء
```bash
flutter pub get
flutter analyze && flutter test
flutter build apk --release
```
البناء التلقائي يتم على GitHub عند كل دفع إلى الفرع `file-chat-app`، ويضع APK غير موقّع في `dist/`.

## التوقيع (مهم للتحديثات)
يجب توقيع كل نسخة بنفس المفتاح `filechat-release.jks` حتى تُثبَّت فوق النسخة السابقة دون حذف بياناتك. المفتاح **لا يُرفع إلى GitHub أبداً**.

للتوقيع على جهازك ضع الملف `android/key.properties`:
```
storeFile=/المسار/إلى/filechat-release.jks
storePassword=كلمة المرور
keyAlias=filechat
keyPassword=كلمة المرور
```
ثم `flutter build apk --release` يُخرج APK موقّعاً مباشرة.

أو وقّع APK غير موقّع بأداة apksigner من Android SDK:
```bash
apksigner sign --ks filechat-release.jks --ks-key-alias filechat --out file-chat.apk dist/file-chat-unsigned.apk
```
لإصدار تحديث ارفع رقم `version` في `pubspec.yaml` (مثلاً `1.0.1+2`).
