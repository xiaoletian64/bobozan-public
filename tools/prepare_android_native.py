from pathlib import Path
import shutil
root = Path(__file__).resolve().parents[1]
build = root / "android/build"
source = build / "src/com/godot/game"
shutil.copy2(root / "native/android/BoboBle.java", source / "BoboBle.java")
p = source / "GodotApp.java"
s = p.read_text()
if "private BoboBle boboBle" not in s:
    s = s.replace("public class GodotApp extends GodotActivity {", "public class GodotApp extends GodotActivity {\n\tprivate BoboBle boboBle;")
    s = s.replace("\t\tsuper.onCreate(savedInstanceState);", "\t\tboboBle = new BoboBle(this);\n\t\tboboBle.start();\n\t\tsuper.onCreate(savedInstanceState);")
    at = s.rfind("}")
    s = s[:at] + """
    @Override public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] results) {
        super.onRequestPermissionsResult(requestCode, permissions, results);
        if (boboBle != null) boboBle.permissionResult(requestCode);
    }
    @Override public void onDestroy() {
        if (boboBle != null) boboBle.destroy();
        super.onDestroy();
    }
""" + s[at:]
    p.write_text(s)
p = build / "AndroidManifest.xml"
s = p.read_text()
if "android.permission.BLUETOOTH_SCAN" not in s:
    s = s.replace("    <supports-screens", """    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />
    <uses-feature android:name="android.hardware.bluetooth_le" android:required="false" />
    <supports-screens""")
    p.write_text(s)
print("Android native bridge installed")

# Native OTA UI is exposed through the existing authenticated localhost bridge.
for name in ["BoboUpdate.java", "OtaSignature.java", "BoboUpdateProvider.java"]:
    shutil.copy2(root / "native/android" / name, source / name)
p = source / "GodotApp.java"
s = p.read_text()
if "boboBle.updater.onResume()" not in s:
    at = s.rfind("}")
    s = s[:at] + """
    @Override public void onResume() {
        super.onResume();
        if (boboBle != null) boboBle.updater.onResume();
    }
""" + s[at:]
    s = s.replace("if (boboBle != null) boboBle.destroy();", "if (boboBle != null) { boboBle.updater.cancel(); boboBle.destroy(); }")
    p.write_text(s)
p = build / "AndroidManifest.xml"
s = p.read_text()
if "android.permission.REQUEST_INSTALL_PACKAGES" not in s:
    s = s.replace("    <supports-screens", '    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />\n    <supports-screens')
if "@xml/bobo_network_security" not in s:
    s = s.replace("    <application", '    <application android:networkSecurityConfig="@xml/bobo_network_security"')
if '${applicationId}.ota' not in s:
    s = s.replace("    </application>", """
        <provider android:name="com.godot.game.BoboUpdateProvider"
            android:authorities="${applicationId}.ota" android:exported="false" android:grantUriPermissions="true">
            <meta-data android:name="android.support.FILE_PROVIDER_PATHS" android:resource="@xml/bobo_ota_paths" />
        </provider>
    </application>""")
s = s.replace('android:name="androidx.core.content.FileProvider"', 'android:name="com.godot.game.BoboUpdateProvider"')
p.write_text(s)
xml = build / "res/xml"
xml.mkdir(exist_ok=True)
(xml / "bobo_ota_paths.xml").write_text('<paths xmlns:android="http://schemas.android.com/apk/res/android"><cache-path name="ota" path="ota/" /></paths>')
(xml / "bobo_network_security.xml").write_text('<network-security-config><base-config cleartextTrafficPermitted="false"/><domain-config cleartextTrafficPermitted="true"><domain>updates.example.invalid</domain></domain-config></network-security-config>')
print("Android OTA installed with scoped download provider and signed HTTP manifest")

# Keep the compiled trust anchor synchronized with the publisher's public key.
p = source / "BoboUpdate.java"
import re
s = p.read_text()
s = re.sub(r'(static final String PUBLIC_KEY = ")[^"]+(";)', lambda m: m.group(1)+(root / "native/android/ota-public-key.txt").read_text().strip()+m.group(2), s)
p.write_text(s)
