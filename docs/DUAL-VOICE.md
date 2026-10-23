# 双音色 · Android 0.3.4

默认使用初版女声，保留原男声。首页「声音与设置」可切换音色、试听「波波攒」、切换音效和查看隐私说明。

女声来自 `builds/legacy-system-voice` 的早期原型 WAV，原样恢复到 `assets/audio/female`，不压缩、不升调。四个单字口令约 0.17–0.23 秒，可直接容纳在最快 0.34 秒拍长内。男声继续使用原有保音高速度档，按单字实际长度选择可容纳的版本。来源和校验分别见 `release/female-audio-provenance.json` 与原有男声来源记录。

设置保存到 `user://settings.cfg` 的 audio.voice（female / male）与 audio.enabled，升级无 voice 字段时默认女声，原静音设置保留。保存前读取已有配置，不覆盖其他设置。试听在离开页面、切换声音、静音或切后台时取消。蓝牙对局仍只有房主设备播放口令，音色是设备本地偏好，不改变协议或规则。

两套音频与选择逻辑属于共用 Godot 层；本次产物为 Android 开发 APK，未重新导出 iOS 包。

验证：`tests/test_voice.gd` 覆盖默认女声、原始资源路径、两套音色长度、音色/静音保存、保留其他设置、高速档选择、取消试听及重启恢复；节奏、单机与双场景联机流程回归通过。桌面引擎截图为 `docs/voice-settings.png`，原女声慢/快节奏试听为 `docs/female-voice-preview.wav`。
