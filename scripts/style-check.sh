#!/usr/bin/env bash
# style-check.sh — 文体规则机器闸门（llm-wiki fork）
# 检查 wiki 知识库页面的文体违规：
#   ERROR = 指路式尾巴 / 导航元叙述（"见[[X]]、详见、本体见、承载这部分、收在…一节"等禁式）
#         + 框架名词当链接显示文字（"|完整界定]]""|完整论述]]"这类空框架词，属"为挂链接而生的句子"）
#         + 判断页链接当显示文字（"|当日判断]]""|同日判断]]"这类页名；source 目录豁免）
#   WARN  = [[wiki/…]] 路径前缀链接（可能存在合法消歧用例，如 _index、与素材原文同名的裸名歧义）
# 用法: bash style-check.sh [vault 根目录]    默认取参数 1；不传则用 $PWD
#   传 vault 根目录时自动扫描「根/index.md + 根/wiki/**」；传子目录时只扫该目录。
# 退出码: 0 = 无 ERROR（WARN 允许存在，由人确认）; 1 = 有 ERROR 或参数错误
# 规则来源: SKILL.md「知识库格式规则（本 fork 定制）」细化 4/6。
# 只报告不修改：AI 审阅报告后修复，或对合法例外说明保留理由。

set -u
ROOT="${1:-$(pwd)}"
[ -d "$ROOT" ] || { echo "目录不存在: $ROOT" >&2; exit 1; }

# 构造扫描范围
if [ -d "$ROOT/wiki" ] && [ -f "$ROOT/index.md" ]; then
  SCAN_PATHS=("$ROOT/index.md" "$ROOT/wiki")
  EXCLUDE_DIR=(--exclude-dir='.git' --exclude-dir='raw' --exclude-dir='.wiki-tmp')
  EXCLUDE_FILE=(--exclude='log.md')
else
  SCAN_PATHS=("$ROOT")
  EXCLUDE_DIR=()
  EXCLUDE_FILE=()
fi

# ERROR 级：指路尾巴 / 导航元叙述 —— 合并为单一正则
default_ifs="$IFS"; IFS='|'
ERROR_PAT="见 \[\[|详见|参见 \[\[|本体见|详见上文|详见下文|承载这部分|承载了这部分|承载该部分|承载此部分|收在 \[\[|里接在|记录于 \[\[|完整机制收在|归于 ?\[\[|记在 ?\[\[|记于 ?\[\[|\[\[[^]]*[|]完整(的)?(界定|论述|表述|分析|推演|机制|展开|脉络|对照|说明|解释|介绍|梳理|总结)"
IFS="$default_ifs"

# ERROR 级（二）：判断页链接当显示文字——「|当日判断]]」「|同日的形势判断]]」这类页名不承载内容，
# 与「|完整论述]]」同类。只认目标页以「经济形势判断」开头的链接，避免误伤
# [[中美博弈|当日的结论]] 这类非判断页链接。source 页「…归 [[X|当日判断]]」是本职导航，按目录豁免。
# 覆盖族：当日/同日/当天 + 形势/市场 + 判断/结论 + 可选的「条目」；以及显示文字直接照抄页名。
JUDGE_LABEL_PAT='\[\[经济形势判断[^]|]*\|((当|同)(日|天)的?(形势|市场)?(判断|结论)(条目)?|经济形势判断(-20[0-9]{2}Q[1-4])?)\]\]'
JUDGE_LABEL_EXCLUDE=(--exclude-dir='.git' --exclude-dir='raw' --exclude-dir='.wiki-tmp' --exclude-dir='sources')

# WARN 级：wiki/ 路径前缀链接
WARN_PAT='\[\[wiki/'

err=0; warn=0

# 使用 grep -r 一次性扫描全部文件（避免逐文件 spawn grep 的进程开销）
for pat in "$ERROR_PAT"; do
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    # grep -r 输出格式: 文件路径:行号:匹配内容
    f=${line%%:*}
    rest=${line#*:}
    ln=${rest%%:*}
    txt=${rest#*:}
    [ -z "$txt" ] && continue
    printf 'ERROR  %s:%s  %s\n' "${f#"$ROOT"/}" "$ln" "$(echo "$txt" | sed 's/^[[:space:]]*//' | cut -c1-110)"
    err=$((err+1))
  done < <(grep -r -n -E --include='*.md' "${EXCLUDE_DIR[@]}" "${EXCLUDE_FILE[@]}" "$pat" "${SCAN_PATHS[@]}" 2>/dev/null)
done

# 判断页链接当显示文字（source 目录豁免：那里的「归 [[X|当日判断]]」是本职导航）
while IFS= read -r line; do
  [ -z "$line" ] && continue
  f=${line%%:*}
  rest=${line#*:}
  ln=${rest%%:*}
  txt=${rest#*:}
  [ -z "$txt" ] && continue
  printf 'ERROR  %s:%s  %s\n' "${f#"$ROOT"/}" "$ln" "$(echo "$txt" | sed 's/^[[:space:]]*//' | cut -c1-110)"
  err=$((err+1))
done < <(grep -r -n -E --include='*.md' "${JUDGE_LABEL_EXCLUDE[@]}" "${EXCLUDE_FILE[@]}" "$JUDGE_LABEL_PAT" "${SCAN_PATHS[@]}" 2>/dev/null)

for pat in "$WARN_PAT"; do
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    f=${line%%:*}
    rest=${line#*:}
    ln=${rest%%:*}
    txt=${rest#*:}
    [ -z "$txt" ] && continue
    printf 'WARN   %s:%s  %s\n' "${f#"$ROOT"/}" "$ln" "$(echo "$txt" | sed 's/^[[:space:]]*//' | cut -c1-110)"
    warn=$((warn+1))
  done < <(grep -r -n -E --include='*.md' "${EXCLUDE_DIR[@]}" "${EXCLUDE_FILE[@]}" "$pat" "${SCAN_PATHS[@]}" 2>/dev/null)
done

echo "----"
echo "style-check 完成: ERROR=$err  WARN=$warn"
if [ "$err" -gt 0 ]; then
  echo "存在 ERROR 级文体违规（指路尾巴/元叙述），先修复再交付。WARN 需人工确认是否为合法消歧。"
  exit 1
fi
echo "ERROR 级清零。WARN 为 [[wiki/ 前缀链接，逐一确认合法例外或织入化。"
exit 0
