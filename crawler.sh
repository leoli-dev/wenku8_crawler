#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
用法: ./crawler.sh [选项] <目录网址1> [目录网址2 ...]

选项:
  -o, --output DIR   指定根输出目录（默认 downloaded）
  -d, --delay SEC    每次请求的基础等待秒数（默认 10）
  -h, --help         显示本说明
EOF
}

OUTPUT_ROOT="downloaded"
DELAY=10
URLS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output)
      if [[ $# -lt 2 ]]; then
        echo "缺少 --output 的参数" >&2
        usage
        exit 1
      fi
      OUTPUT_ROOT="$2"
      shift 2
      ;;
    -d|--delay)
      if [[ $# -lt 2 ]]; then
        echo "缺少 --delay 的参数" >&2
        usage
        exit 1
      fi
      DELAY="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "未知选项: $1" >&2
      usage
      exit 1
      ;;
    *)
      URLS+=("$1")
      shift
      ;;
  esac
done

if [[ ${#URLS[@]} -eq 0 ]]; then
  usage
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
declare -a curl_base=()

sleep_with_jitter() {
  local base="$1"
  local duration
  duration=$(python3 - "$base" <<'PY'
import random
import sys

base = max(0.5, float(sys.argv[1]))
low = max(0.5, base * 0.8)
high = base * 1.4
print(f"{random.uniform(low, high):.2f}")
PY
)
  sleep "$duration"
}

fetch_page() {
  local url="$1"
  local referer="${2:-}"
  local output="$3"
  local attempt=1
  local max_attempts=5
  local raw="$output.raw"
  local last_error=0
  local -a headers=()
  if [[ -n "$referer" ]]; then
    headers+=(-H "Referer: $referer")
  fi
  while (( attempt <= max_attempts )); do
    if "${curl_base[@]}" "${headers[@]}" "$url" >"$raw"; then
      if ! iconv -f gbk -t utf-8 "$raw" >"$output" 2>/dev/null; then
        python3 - "$raw" "$output" <<'PY'
import pathlib
import sys

raw_path = pathlib.Path(sys.argv[1])
out_path = pathlib.Path(sys.argv[2])
data = raw_path.read_bytes()
text = data.decode("gbk", errors="ignore")
out_path.write_text(text, encoding="utf-8")
PY
      fi
      rm -f "$raw"
      sleep_with_jitter "$DELAY"
      return 0
    else
      last_error=$?
    fi
    if [[ "$url" == https://* ]]; then
      local fallback="http://${url#https://}"
      if "${curl_base[@]}" "${headers[@]}" "$fallback" >"$raw"; then
        if ! iconv -f gbk -t utf-8 "$raw" >"$output" 2>/dev/null; then
          python3 - "$raw" "$output" <<'PY'
import pathlib
import sys

raw_path = pathlib.Path(sys.argv[1])
out_path = pathlib.Path(sys.argv[2])
data = raw_path.read_bytes()
text = data.decode("gbk", errors="ignore")
out_path.write_text(text, encoding="utf-8")
PY
        fi
        rm -f "$raw"
        sleep_with_jitter "$DELAY"
        return 0
      else
        last_error=$?
      fi
    fi
    rm -f "$raw"
    if (( attempt == max_attempts )); then
      echo "下载失败：$url (已尝试 $attempt 次, 最后错误码 $last_error)" >&2
      return 1
    fi
    local wait_seconds
    wait_seconds=$(python3 - "$DELAY" <<'PY'
import sys
delay = float(sys.argv[1])
base = max(delay, 10.0)
print(f"{base:.2f}")
PY
)
    echo "请求失败（尝试 $attempt/$max_attempts，错误码 $last_error）：$url。将等待 ${wait_seconds}s 后重试" >&2
    sleep "$wait_seconds"
    ((attempt++))
  done
}

process_catalog() {
  local CATALOG_URL="$1"
  local TMP_DIR
  TMP_DIR=$(mktemp -d)
  local COOKIE_JAR="$TMP_DIR/cookies.txt"
  local CATALOG_HTML="$TMP_DIR/catalog.html"
  local CATALOG_DATA="$TMP_DIR/catalog.tsv"
  local -A volume_counters=()
  UA="curl/7.81.0"
  curl_base=(curl -fsSL --compressed --retry 3 --retry-delay 2 -A "$UA" -b "$COOKIE_JAR" -c "$COOKIE_JAR")

  fetch_page "$CATALOG_URL" "https://www.wenku8.net/index.php" "$CATALOG_HTML"
  python3 "$SCRIPT_DIR/scripts/parse_catalog.py" "$CATALOG_HTML" "$CATALOG_URL" >"$CATALOG_DATA"

  novel_title=""
  novel_safe=""
  novel_dir=""
  chapter_count=0

  while IFS=$'\t' read -r kind col1 col2 col3 col4; do
    case "$kind" in
      TITLE)
        novel_title="$col1"
        novel_safe="$col2"
        novel_dir="$OUTPUT_ROOT/$novel_safe"
        mkdir -p "$novel_dir"
        echo "小说：$novel_title -> $novel_dir"
        ;;
      VOLUME)
        volume_raw="$col1"
        volume_safe="$col2"
        mkdir -p "$novel_dir/$volume_safe"
        echo "  卷：$volume_raw"
        ;;
      CHAPTER)
        volume_safe="$col1"
        chapter_title="$col2"
        chapter_safe="$col3"
        chapter_url="$col4"
        volume_dir="$novel_dir/$volume_safe"
        mkdir -p "$volume_dir"
        if [[ "$chapter_title" == *插图* ]]; then
          chapter_dir="$volume_dir/$chapter_safe"
          mkdir -p "$chapter_dir"
          if [[ -d "$chapter_dir" ]] && find "$chapter_dir" -maxdepth 1 -type f -not -name ".images.txt" -print -quit | grep -q .; then
            printf '    [%03d] 跳过 %s - %s (插图已存在)\n' "$((chapter_count + 1))" "$volume_safe" "$chapter_title"
            ((++chapter_count))
            continue
          fi
          printf '    [%03d] 下载插图 %s - %s\n' "$((chapter_count + 1))" "$volume_safe" "$chapter_title"
          printf -v chapter_html '%s/chapter_%04d.html' "$TMP_DIR" "$chapter_count"
          fetch_page "$chapter_url" "$CATALOG_URL" "$chapter_html"
          image_list="$chapter_dir/.images.txt"
          python3 "$SCRIPT_DIR/scripts/extract_images.py" "$chapter_html" "$chapter_url" >"$image_list"
          if [[ ! -s "$image_list" ]]; then
            echo "        未在插图章节中找到图片链接" >&2
          else
            idx=1
            while IFS=$'\t' read -r image_url image_name; do
              [[ -z "$image_url" ]] && continue
              dest="$chapter_dir/$image_name"
              if [[ -e "$dest" ]]; then
                dest="$chapter_dir/${image_name%.*}_$idx.${image_name##*.}"
                ((idx++))
              fi
              echo "        保存图片 -> $dest"
              curl -fsSL --retry 3 --retry-delay 2 -H "Referer: $chapter_url" "$image_url" -o "$dest"
              sleep_with_jitter "$DELAY"
            done <"$image_list"
          fi
          rm -f "$chapter_html" "$image_list"
          ((++chapter_count))
          continue
        fi
        chapter_index=${volume_counters["$volume_dir"]:-0}
        chapter_index=$((chapter_index + 1))
        volume_counters["$volume_dir"]=$chapter_index
        printf -v chapter_prefix "%03d" "$chapter_index"
        chapter_path="$volume_dir/${chapter_prefix}_${chapter_safe}.txt"
        if [[ -e "$chapter_path" ]]; then
          if [[ -s "$chapter_path" ]]; then
            printf '    [%03d] 跳过 %s - %s (已存在)\n' "$((chapter_count + 1))" "$volume_safe" "$chapter_title"
            ((++chapter_count))
            continue
          else
            printf '    [%03d] 重新写入 %s - %s (原文件为空)\n' "$((chapter_count + 1))" "$volume_safe" "$chapter_title"
          fi
        else
          printf '    [%03d] 下载 %s - %s\n' "$((chapter_count + 1))" "$volume_safe" "$chapter_title"
        fi
        printf -v chapter_html '%s/chapter_%04d.html' "$TMP_DIR" "$chapter_count"
        fetch_page "$chapter_url" "$CATALOG_URL" "$chapter_html"
        python3 "$SCRIPT_DIR/scripts/extract_content.py" "$chapter_html" >"$chapter_path"
        rm -f "$chapter_html"
        echo "        保存至 $chapter_path"
        ((++chapter_count))
        ;;
    esac
  done <"$CATALOG_DATA"

  echo "完成，共保存 $chapter_count 个章节，根目录：$novel_dir"
  rm -rf "$TMP_DIR"
}

declare -a UNIQUE_URLS=()
declare -A seen_urls=()
for url in "${URLS[@]}"; do
  [[ -z "$url" ]] && continue
  if [[ -z "${seen_urls[$url]+x}" ]]; then
    UNIQUE_URLS+=("$url")
    seen_urls["$url"]=1
  fi
done

echo "待处理任务："
for idx in "${!UNIQUE_URLS[@]}"; do
  printf '  [%02d] %s\n' "$((idx + 1))" "${UNIQUE_URLS[idx]}"
done

task_idx=1
for catalog in "${UNIQUE_URLS[@]}"; do
  echo "===== 开始任务 #$task_idx: $catalog ====="
  process_catalog "$catalog"
  echo "===== 任务 #$task_idx 完成 ====="
  ((task_idx++))
done
