# 口令音频来源

六个固定口令已生成并替换资源；采样率、非静音、时长及 SHA-256 校验通过。仍需真机听感验收。

模型：hexgrad/Kokoro-82M-v1.1-zh

模型版本：01e7505bd6a7a2ac4975463114c3a7650a9f7218

中文音色：zm_010，通用模型音色，不模仿指定人物。

模型声明 Apache-2.0 许可；官方模型卡说明中文训练数据由 LongMaoData 授予使用。

来源：https://huggingface.co/hexgrad/Kokoro-82M-v1.1-zh

生成脚本：tools/generate_voice.py。模型及 Python 依赖不随 App 分发，仅固定口令 WAV 入包。

0.3.4 应用户要求恢复早期女声：从 builds/legacy-system-voice 原样复制到 assets/audio/female，SHA-256 与归档一致。对应早期 macOS 系统合成原型口令，原始音色标识未被归档，不把它标成 Kokoro 或声称新的商用授权。来源与校验见 female-audio-provenance.json。原有 Kokoro 男声仍可选。

2026-09-27 节奏版：新增 `assets/audio/rhythm/`，由上述 WAV 使用 ffmpeg atempo 保音高压缩生成，包含短淡入淡出与降低音量。源音频与模型音色未变；脚本 `tools/prepare_rhythm_audio.py`，输出校验 `release/rhythm-audio-provenance.json`。新增命中音为本项目程序化滤波噪声。
