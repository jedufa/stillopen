package com.stillopen.fixture;

import android.app.Activity;
import android.content.ClipData;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.util.Log;

import androidx.core.content.FileProvider;

import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;

public final class ShareSenderActivity extends Activity {
    private static final String TAG = "StillOpenShareFixture";
    private static final String TARGET_PACKAGE = "com.stillopen.app";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        try {
            String scenario = getIntent().getStringExtra("scenario");
            if (scenario == null || scenario.isEmpty()) scenario = "text";
            boolean duplicate = getIntent().getBooleanExtra("duplicate", false);
            boolean expire = getIntent().getBooleanExtra("expire", false);
            sendScenario(scenario, expire);
            if (duplicate) sendScenario(scenario, expire);
            Log.i(TAG, "sent scenario=" + scenario + " duplicate=" + duplicate + " expire=" + expire);
        } catch (Exception error) {
            Log.e(TAG, "share fixture failed: " + error.getClass().getSimpleName(), error);
            setResult(RESULT_CANCELED);
        } finally {
            finish();
        }
    }

    private void sendScenario(String scenario, boolean expire) throws Exception {
        switch (scenario) {
            case "url":
                sendText("https://example.com/stillopen-rc", true);
                break;
            case "text":
                sendText("Plain shared text from Android emulator RC", false);
                break;
            case "image":
                sendSingleFile("rc-image.png", "image/png", "fake image bytes".getBytes(StandardCharsets.UTF_8), false);
                break;
            case "pdf":
                sendSingleFile("rc-invoice.pdf", "application/pdf", "%PDF-1.4\nrc\n".getBytes(StandardCharsets.UTF_8), false);
                break;
            case "generic":
                sendSingleFile("rc-generic.bin", "application/octet-stream", "generic bytes".getBytes(StandardCharsets.UTF_8), false);
                break;
            case "multiple":
                sendMultipleFiles();
                break;
            case "mixed_text_image":
                sendSingleFile("rc-mixed-image.png", "image/png", "mixed image".getBytes(StandardCharsets.UTF_8), true);
                break;
            case "mixed_url_pdf":
                sendSingleFile("rc-mixed-invoice.pdf", "application/pdf", "%PDF-1.4\nmixed\n".getBytes(StandardCharsets.UTF_8), true);
                break;
            case "expired_pdf":
                sendSingleFile("rc-expired.pdf", "application/pdf", "%PDF-1.4\nexpired\n".getBytes(StandardCharsets.UTF_8), false, true);
                break;
            default:
                throw new IllegalArgumentException("Unknown scenario " + scenario);
        }
        if (expire) deleteSharedFiles();
    }

    private void sendText(String text, boolean url) {
        Intent intent = new Intent(Intent.ACTION_SEND);
        intent.setPackage(TARGET_PACKAGE);
        intent.setType("text/plain");
        intent.putExtra(Intent.EXTRA_TEXT, text);
        if (url) intent.putExtra(Intent.EXTRA_TITLE, "StillOpen RC URL");
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        startActivity(intent);
    }

    private void sendSingleFile(String name, String mimeType, byte[] bytes, boolean mixedText) throws Exception {
        sendSingleFile(name, mimeType, bytes, mixedText, false);
    }

    private void sendSingleFile(String name, String mimeType, byte[] bytes, boolean mixedText, boolean deleteBeforeSend) throws Exception {
        Uri uri = createContentUri(name, bytes);
        if (deleteBeforeSend) new File(sharedDir(), name).delete();
        Intent intent = new Intent(Intent.ACTION_SEND);
        intent.setPackage(TARGET_PACKAGE);
        intent.setType(mimeType);
        intent.putExtra(Intent.EXTRA_STREAM, uri);
        if (mixedText) {
            intent.putExtra(
                Intent.EXTRA_TEXT,
                mimeType.equals("application/pdf")
                    ? "https://example.com/rc-mixed-pdf"
                    : "Mixed shared text from emulator RC"
            );
        }
        grant(intent, uri);
        startActivity(intent);
    }

    private void sendMultipleFiles() throws Exception {
        ArrayList<Uri> uris = new ArrayList<>();
        uris.add(createContentUri("rc-multiple-image.png", "image one".getBytes(StandardCharsets.UTF_8)));
        uris.add(createContentUri("rc-multiple-file.pdf", "%PDF-1.4\nmulti\n".getBytes(StandardCharsets.UTF_8)));
        Intent intent = new Intent(Intent.ACTION_SEND_MULTIPLE);
        intent.setPackage(TARGET_PACKAGE);
        intent.setType("*/*");
        intent.putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris);
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        intent.setClipData(ClipData.newUri(getContentResolver(), "StillOpen RC files", uris.get(0)));
        for (Uri uri : uris) grantUriPermission(TARGET_PACKAGE, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION);
        startActivity(intent);
    }

    private void grant(Intent intent, Uri uri) {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        intent.setClipData(ClipData.newUri(getContentResolver(), "StillOpen RC file", uri));
        grantUriPermission(TARGET_PACKAGE, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION);
    }

    private Uri createContentUri(String name, byte[] bytes) throws Exception {
        File file = new File(sharedDir(), name);
        try (FileOutputStream output = new FileOutputStream(file)) {
            output.write(bytes);
        }
        return FileProvider.getUriForFile(this, "com.stillopen.fixture.fileprovider", file);
    }

    private File sharedDir() {
        File dir = new File(getCacheDir(), "shared");
        if (!dir.exists() && !dir.mkdirs()) {
            throw new IllegalStateException("Could not create share fixture cache");
        }
        return dir;
    }

    private void deleteSharedFiles() {
        File[] files = sharedDir().listFiles();
        if (files == null) return;
        for (File file : files) file.delete();
    }
}
