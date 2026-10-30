// End-to-end UI test in a real Chromium. Usage: node tests/e2e_ui.js <baseUrl> <fixturesDir> <shotsDir>
const { chromium } = require("playwright");
const path = require("path");
const fs = require("fs");
// Pass files as buffers so non-ASCII (Arabic) names survive.
const fileArg = (name, mimeType) => ({ name, mimeType, buffer: fs.readFileSync(path.join(fx, name)) });
const [base, fx, shots] = process.argv.slice(2);
const results = [];
const check = (name, ok, extra) => { results.push({ name, ok }); console.log((ok ? "PASS " : "FAIL ") + name + (extra ? " — " + extra : "")); };

(async () => {
  const browser = await chromium.launch();
  const errors = [];
  for (const [label, viewport, scheme] of [["desktop-light", { width: 1280, height: 820 }, "light"], ["mobile-dark", { width: 390, height: 844 }, "dark"]]) {
    const ctx = await browser.newContext({ viewport, colorScheme: scheme, deviceScaleFactor: 2 });
    const page = await ctx.newPage();
    page.on("console", m => { if (m.type() === "error") errors.push(label + ": " + m.text()); });
    page.on("pageerror", e => errors.push(label + ": " + e.message));
    await page.goto(base);
    await page.waitForSelector(".ai-status.ok", { timeout: 5000 }).catch(() => {});
    check(label + " RTL by default", await page.evaluate(() => document.documentElement.dir) === "rtl");
    check(label + " placeholder", await page.getAttribute("#input", "placeholder") === "اسأل عن ملفاتك...");
    await page.screenshot({ path: path.join(shots, label + "-1-empty.png") });

    // send button is outside the input box and on the left in RTL
    const sb = await page.locator("#send").boundingBox(), ib = await page.locator(".input-box").boundingBox();
    check(label + " send button left of input box", sb.x + sb.width <= ib.x + 1);
    const fb = await page.locator("#attachFile").boundingBox();
    check(label + " attach buttons inside input box", fb.x >= ib.x && fb.x + fb.width <= ib.x + ib.width);
    check(label + " send disabled when empty", await page.isDisabled("#send"));

    // attach a file and an image
    await page.setInputFiles("#fileInput", fileArg("عقد العمل.pdf", "application/pdf"));
    await page.setInputFiles("#imageInput", fileArg("فاتورة.png", "image/png"));
    await page.waitForFunction(() => document.querySelectorAll("#pending .att-status.uploaded").length === 2, null, { timeout: 5000 });
    check(label + " two pending attachments uploaded", true);
    // unsupported type shows a clear error
    await page.setInputFiles("#fileInput", fileArg("tool.exe", "application/octet-stream"));
    const toastText = await page.locator(".toast.error").first().textContent();
    check(label + " unsupported file rejected with message", toastText.includes("غير مدعوم"), toastText);

    await page.fill("#input", "ما اسم الشركة في العقد؟ What is the total?");
    await page.screenshot({ path: path.join(shots, label + "-2-attachments.png") });
    await page.click("#send");
    await page.waitForSelector(".typing, .cursor", { timeout: 3000 }).catch(() => {});
    check(label + " stop button shown while streaming", await page.locator("#send.stop").count() === 1);
    await page.waitForFunction(() => !document.querySelector("#send.stop"), null, { timeout: 15000 });
    const reply = await page.locator(".msg.assistant .bubble").last().innerText();
    check(label + " streamed reply rendered", reply.includes("رد تجريبي"), reply.slice(0, 60));
    check(label + " markdown list rendered", await page.locator(".msg.assistant .bubble li").count() >= 2);
    check(label + " attachments shown in message", await page.locator(".msg.user .att-card").count() === 2);
    const title = await page.textContent("#convTitle");
    check(label + " auto title from first message", title.startsWith("ما اسم الشركة"), title);
    await page.screenshot({ path: path.join(shots, label + "-3-chat.png") });

    // persistence after reload
    await page.reload();
    await page.waitForSelector(".msg.assistant");
    check(label + " conversation persists after reload", await page.locator(".msg").count() === 2);

    if (label === "desktop-light") {
      // rename via dialog
      await page.click("#renameCurrent");
      await page.fill("#dialogInput", "تحليل عقد العمل");
      await page.click("#dialogOk");
      await page.waitForFunction(() => document.querySelector("#convTitle").textContent === "تحليل عقد العمل");
      check("rename conversation", true);
      // new chat + search
      await page.click("#newChat");
      check("new chat shows empty state", await page.locator(".empty").count() === 1);
      await page.fill("#search", "عقد");
      await page.waitForTimeout(400);
      check("search finds conversation", (await page.locator(".conv-item").count()) === 1);
      await page.fill("#search", "zzzz");
      await page.waitForTimeout(400);
      check("search shows no results", (await page.locator(".conv-empty").textContent()).includes("لا توجد"));
      await page.fill("#search", "");
      await page.waitForTimeout(400);
      // switch language
      await page.click("#langToggle");
      check("switch to English LTR", await page.evaluate(() => document.documentElement.dir) === "ltr" &&
        (await page.getAttribute("#input", "placeholder")) === "Ask about your files...");
      await page.locator(".conv-open").first().click();
      await page.waitForSelector(".msg.assistant");
      await page.screenshot({ path: path.join(shots, "desktop-light-4-english.png") });
      await page.click("#langToggle");
      // delete a file from a sent message
      await page.locator(".msg.user .att-actions button").first().click();
      await page.click("#dialogOk");
      await page.waitForFunction(() => document.querySelectorAll(".msg.user .att-card").length === 1);
      check("delete attached file", true);
      // theme toggle cycles
      await page.click("#themeToggle"); await page.click("#themeToggle");
      check("theme toggle to dark", await page.evaluate(() => document.documentElement.getAttribute("data-theme")) === "dark");
      await page.click("#themeToggle");
      // delete conversation
      await page.locator(".conv-item.active .conv-actions button").nth(1).click();
      await page.click("#dialogOk");
      await page.waitForSelector(".empty");
      check("delete conversation", (await page.locator(".conv-item").count()) === 0);
    } else {
      await page.click("#openSidebar");
      await page.waitForTimeout(300);
      await page.screenshot({ path: path.join(shots, label + "-4-sidebar.png") });
      check(label + " sidebar opens", await page.locator("#sidebar.open").count() === 1);
      const overflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
      check(label + " no horizontal scroll", !overflow);
    }
    await ctx.close();
  }
  check("no console errors", errors.length === 0, errors.join(" | "));
  await browser.close();
  const failed = results.filter(r => !r.ok).length;
  console.log(`\n${results.length - failed}/${results.length} checks passed`);
  process.exit(failed ? 1 : 0);
})();
