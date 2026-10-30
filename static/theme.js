// Runs before paint so the saved theme applies without a flash.
(function () {
  var t = null;
  try { t = localStorage.getItem("theme"); } catch (e) {}
  if (t === "light" || t === "dark") document.documentElement.setAttribute("data-theme", t);
  var l = null;
  try { l = localStorage.getItem("lang"); } catch (e) {}
  if (l === "en") { document.documentElement.lang = "en"; document.documentElement.dir = "ltr"; }
})();
