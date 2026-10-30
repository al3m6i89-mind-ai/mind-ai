package com.zuhair.filechat;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.ClipData;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.Uri;
import android.os.Bundle;
import android.webkit.JavascriptInterface;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

/**
 * Thin Android shell around the web app. The AI and the files stay on the server running on the
 * user's computer; this activity only shows it in a WebView and handles file picking.
 */
public class MainActivity extends Activity {
    private static final String SETUP_URL = "file:///android_asset/setup.html";
    private static final String PREFS = "filechat";
    private static final String KEY_SERVER = "server";
    private static final int FILE_REQUEST = 1001;

    private WebView web;
    private ValueCallback<Uri[]> filePathCallback;
    private String lastError = "";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        web = new WebView(this);
        setContentView(web);

        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setAllowFileAccess(false);
        s.setAllowContentAccess(true);

        web.addJavascriptInterface(new Bridge(), "AndroidApp");
        web.setWebViewClient(new ShellClient());
        web.setWebChromeClient(new FileChooserClient());
        web.setDownloadListener((url, userAgent, contentDisposition, mimeType, length) -> openExternally(url));

        String server = prefs().getString(KEY_SERVER, "");
        web.loadUrl(server.isEmpty() ? SETUP_URL : server);
    }

    private SharedPreferences prefs() {
        return getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    private void openExternally(String url) {
        try {
            startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url)));
        } catch (ActivityNotFoundException ignored) {
            // No app can open it; nothing else to do.
        }
    }

    private boolean isServerUrl(Uri uri) {
        String server = prefs().getString(KEY_SERVER, "");
        return !server.isEmpty() && uri.toString().startsWith(server);
    }

    private class ShellClient extends WebViewClient {
        @Override
        public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
            Uri uri = request.getUrl();
            if ("file".equals(uri.getScheme())) return false;
            // Attachments (PDF, Word...) open in an external app; WebView cannot display them.
            if (isServerUrl(uri) && !uri.getPath().startsWith("/api/attachments/")) return false;
            openExternally(uri.toString());
            return true;
        }

        @Override
        public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
            if (request.isForMainFrame() && !"file".equals(request.getUrl().getScheme())) {
                lastError = String.valueOf(error.getDescription());
                view.loadUrl(SETUP_URL);
            }
        }
    }

    private class FileChooserClient extends WebChromeClient {
        @Override
        public boolean onShowFileChooser(WebView view, ValueCallback<Uri[]> callback, FileChooserParams params) {
            if (filePathCallback != null) filePathCallback.onReceiveValue(null);
            filePathCallback = callback;

            boolean imagesOnly = true;
            for (String type : params.getAcceptTypes()) {
                for (String t : type.split(",")) {
                    String v = t.trim().toLowerCase();
                    if (v.isEmpty()) continue;
                    boolean image = v.startsWith("image/") || v.equals(".jpg") || v.equals(".jpeg")
                            || v.equals(".png") || v.equals(".webp");
                    if (!image) imagesOnly = false;
                }
            }
            Intent intent = new Intent(Intent.ACTION_GET_CONTENT);
            intent.addCategory(Intent.CATEGORY_OPENABLE);
            intent.setType(imagesOnly ? "image/*" : "*/*");
            intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, params.getMode() == FileChooserParams.MODE_OPEN_MULTIPLE);
            try {
                startActivityForResult(Intent.createChooser(intent, null), FILE_REQUEST);
            } catch (ActivityNotFoundException e) {
                filePathCallback = null;
                return false;
            }
            return true;
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != FILE_REQUEST || filePathCallback == null) return;
        Uri[] result = null;
        if (resultCode == RESULT_OK && data != null) {
            ClipData clip = data.getClipData();
            if (clip != null) {
                result = new Uri[clip.getItemCount()];
                for (int i = 0; i < clip.getItemCount(); i++) result[i] = clip.getItemAt(i).getUri();
            } else if (data.getData() != null) {
                result = new Uri[]{data.getData()};
            }
        }
        filePathCallback.onReceiveValue(result);
        filePathCallback = null;
    }

    @Override
    public void onBackPressed() {
        if (web.canGoBack()) {
            web.goBack();
        } else {
            super.onBackPressed();
        }
    }

    /** Called from setup.html. */
    private class Bridge {
        @JavascriptInterface
        public String getServer() {
            return prefs().getString(KEY_SERVER, "");
        }

        @JavascriptInterface
        public String getLastError() {
            String e = lastError;
            lastError = "";
            return e;
        }

        @JavascriptInterface
        public void connect(String url) {
            String clean = url.trim();
            while (clean.endsWith("/")) clean = clean.substring(0, clean.length() - 1);
            final String target = clean;
            prefs().edit().putString(KEY_SERVER, target).apply();
            runOnUiThread(() -> web.loadUrl(target));
        }
    }
}
