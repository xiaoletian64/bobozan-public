"""Reapply after each Godot iOS export; does not choose a signing identity."""
from pathlib import Path
import plistlib, shutil, subprocess
root = Path(__file__).resolve().parents[1]
build = root / 'builds/ios'
app = build / 'Bobozan'
shutil.copy2(root / 'native/ios/BoboBle.swift', app / 'BoboBle.swift')
p = app / 'dummy.cpp'
s = p.read_text()
if 'bobo_ble_initialize' not in s:
    s = 'extern "C" void bobo_ble_initialize();\nextern "C" void bobo_ble_deinitialize();\n' + s
    s = s.replace('void godot_ios_plugins_initialize() {', 'void godot_ios_plugins_initialize() {\n bobo_ble_initialize();')
    s = s.replace('void godot_ios_plugins_deinitialize() {', 'void godot_ios_plugins_deinitialize() {\n bobo_ble_deinitialize();')
    p.write_text(s)
p = build / 'Bobozan.xcodeproj/project.pbxproj'
s = p.read_text()
if 'BoboBle.swift in Sources' not in s:
    s = s.replace('/* Begin PBXBuildFile section */', '''/* Begin PBXBuildFile section */
        B0B000000000000000000001 /* BoboBle.swift in Sources */ = {isa = PBXBuildFile; fileRef = B0B000000000000000000002; };''')
    s = s.replace('/* Begin PBXFileReference section */', '''/* Begin PBXFileReference section */
        B0B000000000000000000002 /* BoboBle.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = BoboBle.swift; sourceTree = "<group>"; };''')
    s = s.replace('1FF8DBB01FBA9DE1009DE660 /* dummy.cpp */,', '1FF8DBB01FBA9DE1009DE660 /* dummy.cpp */,\n B0B000000000000000000002 /* BoboBle.swift */,')
    s = s.replace('1FF8DBB11FBA9DE1009DE660 /* dummy.cpp in Sources */,', '1FF8DBB11FBA9DE1009DE660 /* dummy.cpp in Sources */,\n B0B000000000000000000001 /* BoboBle.swift in Sources */,')
    s = s.replace('buildSettings = {', 'buildSettings = {\n SWIFT_VERSION = 5.0;\n ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES = YES;')
    p.write_text(s)
# MetalFX is unavailable in the simulator SDK and the simulator engine slice
# does not reference it. Keep the weak link for physical iOS devices only.
s = p.read_text()
s = s.replace('\t\t\t\t054F8BE62D38852F00B81423 /* MetalFX.framework in Frameworks */,', '')
if 'OTHER_LDFLAGS[sdk=iphoneos*]' not in s:
    s = s.replace('buildSettings = {', 'buildSettings = {\n "OTHER_LDFLAGS[sdk=iphoneos*]" = "$(inherited) -weak_framework MetalFX";')
p.write_text(s)
p = app / 'Bobozan-Info.plist'
with p.open('rb') as f: data = plistlib.load(f)
data['NSBluetoothAlwaysUsageDescription'] = '用于发现附近玩家，并通过蓝牙进行双人对战。仅在您创建或加入房间时使用。'
data.setdefault('NSBluetoothPeripheralUsageDescription', data['NSBluetoothAlwaysUsageDescription'])
data['CFBundleDisplayName'] = '波波赞'
data['ITSAppUsesNonExemptEncryption'] = False
data['UISupportedInterfaceOrientations'] = ['UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight']
data['UISupportedInterfaceOrientations~ipad'] = data['UISupportedInterfaceOrientations']
for key in ('NSCameraUsageDescription','NSMicrophoneUsageDescription','NSPhotoLibraryUsageDescription'):
    if not data.get(key): data.pop(key,None)
with p.open('wb') as f: plistlib.dump(data,f)
print('iOS native bridge installed; signing configuration unchanged')

# Optional locally built Apple Silicon simulator slice. Device engine stays official.
local_sim = root / 'builds/godot-4.4.1-stable/bin/libgodot.ios.template_debug.arm64.simulator.a'
sim = build / 'Bobozan.xcframework/ios-arm64_x86_64-simulator/libgodot.a'
if local_sim.exists():
    arches = subprocess.check_output(['xcrun','lipo','-archs',str(sim)],text=True).split()
    if 'arm64' not in arches:
        merged = sim.with_suffix('.merged.a')
        subprocess.run(['xcrun','lipo','-create',str(sim),str(local_sim),'-output',str(merged)],check=True)
        merged.replace(sim)
        print('Added locally built arm64 simulator slice; official device slice unchanged')
