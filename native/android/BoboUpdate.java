package com.godot.game;

import android.app.*;
import android.content.*;
import android.content.pm.*;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;
import android.util.Base64;
import androidx.core.content.FileProvider;
import java.io.*;
import java.net.*;
import java.security.*;
import java.security.spec.X509EncodedKeySpec;
import java.util.*;
import org.json.JSONObject;

/** User-initiated, signed-manifest APK updates. Never silently installs. */
public final class BoboUpdate {
    static final String BASE = "http://updates.example.invalid/bobozan/ota/";
    static final String PUBLIC_KEY = "MIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEAv72d784C3kEY3gqWftDjBVxAv/e47ztUqmPe5cfU29De0Ni215ImxWQkcNaLLn1tO9ZAF27OXJEDscqUSdkrFGj7PE82USeLwvUnXfwLTozmJpIvBgsKE+nb/T6iQVGwgTXoTdrDtYN17CWQ2rN4WTuoX08R3eYVQNWjgCwkPsPPFJv1Vwn6iEWcDFC09kWJY4nDzK31mMBzPozO2qiN2KQb8uE0N39Snf0CeGAgpSifhxGzi4h37cWpVJ/KsRH9yjsCBK2ZyF1Elz5/Fbz5m5MHkzi+LMKObRxwfMwXUkg/5uxOjEB6qKT9cIoCrephBRrIzjw5j9TrQsV7/vm2pIGywVTjUy4I6SCO9BPaPb4pIawIyE/RS+aV7R4zqdTX656GHLjOqHxPOVecDNSixDqo3ASjmMXRhuhRJoQ03ByEcagecP6cwJTuQnuQNMJeaulJqjD9vd1BDpNWougrM7T9rlnfAfXqNLY94wZleCDbS3Qu3XMtAmKNawnMCazDAgMBAAE=";
    static final long MAX_APK = 300L * 1024 * 1024;
    final Activity activity;
    volatile int generation;
    volatile HttpURLConnection connection;
    AlertDialog dialog;
    File pending;
    JSONObject pendingManifest;
    boolean waitingPermission;
    public BoboUpdate(Activity activity) { this.activity = activity; }
    void ui(int ticket, Runnable action) {
        activity.runOnUiThread(() -> { if(ticket == generation && !activity.isFinishing() && !activity.isDestroyed()) action.run(); });
    }
    public void cancel() {
        generation++;
        waitingPermission = false;
        HttpURLConnection c = connection;
        if(c != null) c.disconnect();
        if(dialog != null) { dialog.dismiss(); dialog = null; }
    }
    void message(String title, String text) {
        if(dialog != null) dialog.dismiss();
        dialog = new AlertDialog.Builder(activity).setTitle(title).setMessage(text).setPositiveButton("知道了",null).create();
        dialog.show();
    }
    AlertDialog progress(String title) {
        AlertDialog d = new AlertDialog.Builder(activity).setTitle(title).setMessage("请稍候…")
            .setNegativeButton("取消",(x,y) -> cancel()).create();
        d.setOnCancelListener(x -> cancel()); d.setCanceledOnTouchOutside(false); d.show();
        return d;
    }
    HttpURLConnection open(String url) throws Exception {
        if(!url.startsWith(BASE)) throw new IOException("更新地址不匹配");
        HttpURLConnection c = (HttpURLConnection)new URL(url).openConnection();
        c.setInstanceFollowRedirects(false); c.setConnectTimeout(12000); c.setReadTimeout(20000);
        c.setUseCaches(false); c.setRequestProperty("Accept-Encoding","identity");
        connection = c;
        if(c.getResponseCode() != 200) { c.disconnect(); throw new IOException("更新服务暂不可用"); }
        return c;
    }
    long code(PackageInfo info) { return Build.VERSION.SDK_INT >= 28 ? info.getLongVersionCode() : info.versionCode; }
    PackageInfo installed() throws Exception { return activity.getPackageManager().getPackageInfo(activity.getPackageName(),PackageManager.GET_SIGNATURES); }
    public void check() {
        cancel();
        final int ticket = generation;
        dialog = progress("正在检查更新");
        new Thread(() -> {
            try {
                HttpURLConnection c = open(BASE+"latest.json");
                byte[] data;
                try(InputStream input = c.getInputStream(); ByteArrayOutputStream output = new ByteArrayOutputStream()) {
                    byte[] buffer = new byte[4096]; int n;
                    while((n=input.read(buffer)) != -1) {
                        if(ticket != generation) return;
                        if(output.size()+n > 65536) throw new IOException("更新清单过大");
                        output.write(buffer,0,n);
                    }
                    data = output.toByteArray();
                } finally { c.disconnect(); }
                JSONObject envelope = new JSONObject(new String(data,java.nio.charset.StandardCharsets.UTF_8));
                byte[] payload = Base64.decode(envelope.getString("payload"),Base64.NO_WRAP);
                byte[] signature = Base64.decode(envelope.getString("signature"),Base64.NO_WRAP);
                if(!OtaSignature.verify(payload,signature,Base64.decode(PUBLIC_KEY,Base64.NO_WRAP))) throw new IOException("更新清单签名无效");
                JSONObject manifest = new JSONObject(new String(payload,java.nio.charset.StandardCharsets.UTF_8));
                String file = manifest.getString("file");
                long size = manifest.getLong("size"), version = manifest.getLong("version_code");
                if(!activity.getPackageName().equals(manifest.getString("package")) || !file.matches("bobozan-[A-Za-z0-9.-]+\\.apk")
                    || size <= 0 || size > MAX_APK || version <= 0 || !manifest.getString("sha256").matches("[0-9a-f]{64}")) throw new IOException("更新清单格式无效");
                PackageInfo current = installed();
                if(version <= code(current)) {
                    ui(ticket,() -> message("已是最新版本","当前版本："+current.versionName)); return;
                }
                if(manifest.getInt("min_sdk") > Build.VERSION.SDK_INT) {
                    ui(ticket,() -> message("暂不能安装","新版需要更高版本的 Android，当前游戏仍可继续使用。")); return;
                }
                ui(ticket,() -> {
                    if(dialog != null) dialog.dismiss();
                    dialog = new AlertDialog.Builder(activity).setTitle("发现新版 "+manifest.optString("version_name"))
                        .setMessage(String.format(Locale.ROOT,"下载大小：%.1f MB\n\n%s\n\n下载后由系统确认安装，保留游戏存档。",size/1048576.0,manifest.optString("notes").substring(0,Math.min(1200,manifest.optString("notes").length()))))
                        .setPositiveButton("下载更新",(x,y) -> download(manifest)).setNegativeButton("稍后",null).create();
                    dialog.show();
                });
            } catch(Exception e) { ui(ticket,() -> message("检查失败","无法获取可信的更新，请稍后重试。单机游戏不受影响。")); }
        },"BoboUpdateCheck").start();
    }
    void download(JSONObject manifest) {
        cancel(); final int ticket = generation;
        dialog = progress("下载更新");
        new Thread(() -> {
            File partial = null;
            try {
                File directory = new File(activity.getCacheDir(),"ota");
                if(!directory.isDirectory() && !directory.mkdirs()) throw new IOException("空间不足");
                long expected = manifest.getLong("size");
                if(directory.getUsableSpace() < expected+20L*1024*1024) throw new IOException("空间不足");
                partial = new File(directory,"download-"+ticket+".part");
                MessageDigest digest = MessageDigest.getInstance("SHA-256");
                HttpURLConnection c = open(BASE+manifest.getString("file"));
                try(InputStream input = c.getInputStream(); FileOutputStream output = new FileOutputStream(partial)) {
                    long received=0; int last=-1, n; byte[] buffer=new byte[65536];
                    while((n=input.read(buffer)) != -1) {
                        if(ticket != generation) return;
                        received += n; if(received > expected) throw new IOException("大小不符");
                        digest.update(buffer,0,n); output.write(buffer,0,n);
                        int percent=(int)(received*100/expected);
                        if(percent != last) { last=percent; ui(ticket,() -> { if(dialog != null) dialog.setMessage("已下载 "+percent+"% · 可取消"); }); }
                    }
                    output.getFD().sync();
                    if(received != expected || !hex(digest.digest()).equals(manifest.getString("sha256"))) throw new IOException("完整性校验失败");
                } finally { c.disconnect(); }
                validateApk(partial,manifest);
                if(ticket != generation) return;
                File ready = new File(directory,"update.apk");
                if(ready.exists() && !ready.delete()) throw new IOException("文件占用");
                if(!partial.renameTo(ready)) throw new IOException("无法保存");
                pending=ready; pendingManifest=manifest;
                ui(ticket,() -> { if(dialog != null) dialog.dismiss(); requestInstall(); });
            } catch(Exception e) { ui(ticket,() -> message("下载或校验失败","请检查网络与存储空间后重试。未通过完整性、包名、版本或签名校验的文件不会安装。")); }
            finally { if(partial != null && partial.exists()) partial.delete(); }
        },"BoboUpdateDownload").start();
    }
    static String hex(byte[] bytes) { StringBuilder s=new StringBuilder(); for(byte b:bytes)s.append(String.format(Locale.ROOT,"%02x",b&255));return s.toString(); }
    void validateApk(File file, JSONObject manifest) throws Exception {
        PackageManager pm=activity.getPackageManager();
        PackageInfo apk=pm.getPackageArchiveInfo(file.getPath(),PackageManager.GET_SIGNATURES), current=installed();
        if(apk == null || !activity.getPackageName().equals(apk.packageName) || code(apk) != manifest.getLong("version_code") || code(apk) <= code(current)) throw new IOException("版本或包名不符");
        if(apk.signatures == null || current.signatures == null || apk.signatures.length != current.signatures.length) throw new IOException("签名不符");
        Set<String> a=new HashSet<>(), b=new HashSet<>();
        for(android.content.pm.Signature sig:apk.signatures)a.add(sig.toCharsString());
        for(android.content.pm.Signature sig:current.signatures)b.add(sig.toCharsString());
        if(!a.equals(b)) throw new IOException("签名不符");
    }
    void requestInstall() {
        if(pending == null || !pending.exists()) { message("更新文件已清理","请重新下载更新。"); return; }
        if(Build.VERSION.SDK_INT >= 26 && !activity.getPackageManager().canRequestPackageInstalls()) {
            dialog = new AlertDialog.Builder(activity).setTitle("允许安装应用更新")
                .setMessage("请在系统设置中允许“波波赞”安装应用。返回后仍需你确认安装，不会自动替换应用。")
                .setPositiveButton("前往设置",(x,y) -> {
                    try { waitingPermission=true; activity.startActivity(new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,Uri.parse("package:"+activity.getPackageName()))); }
                    catch(Exception e) { waitingPermission=false; message("无法打开设置","请在系统设置中为波波赞允许安装未知应用，再重新检查更新。"); }
                }).setNegativeButton("取消",null).create();
            dialog.show(); return;
        }
        try {
            validateApk(pending,pendingManifest);
            Uri uri=FileProvider.getUriForFile(activity,activity.getPackageName()+".ota",pending);
            Intent install=new Intent(Intent.ACTION_VIEW).setDataAndType(uri,"application/vnd.android.package-archive").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            activity.startActivity(install);
        } catch(Exception e) { message("无法开始安装","请稍后重试，当前版本仍可正常使用。"); }
    }
    public void onResume() {
        if(waitingPermission) { waitingPermission=false; requestInstall(); }
    }
}
