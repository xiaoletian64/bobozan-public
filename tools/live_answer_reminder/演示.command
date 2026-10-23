#!/bin/zsh
cd -- "${0:A:h}" || exit 1
python3 reminder.py replay --config config.demo.json --input demo.jsonl
printf '\n离线演示结束：重复响应不会反复提醒；未调用真实直播接口或音箱。\n'
read -k 1 '?按任意键关闭'
