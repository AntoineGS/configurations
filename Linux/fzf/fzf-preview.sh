#!/usr/bin/env zsh
#
# fzf preview script
# Handles: files, directories, images, PDFs, videos, audio, archives, markdown
# Dependencies (optional): bat, chafa, pdftoppm, ffmpegthumbnailer, glow

if [[ $# -ne 1 ]]; then
  >&2 echo "usage: $0 FILENAME[:LINENO][:IGNORED]"
  exit 1
fi

# fzf-tab-completion passes data in format: fullvalue SEP value SEP index SEP ...
# where SEP is U+00A0 (non-breaking space)
# We want field 2 (the actual value)
_FZF_COMPLETION_SEP=$'\u00a0'

# Split by non-breaking space and extract field 2
IFS="$_FZF_COMPLETION_SEP" read -r -A fields <<< "$1"
if (( ${#fields[@]} >= 2 )); then
    extracted="${fields[2]}"
else
    extracted="$1"
fi

# Apply tilde expansion
file=${extracted/#\~\//$HOME/}

center=0
if [[ ! -r $file ]]; then
  if [[ $file =~ ^(.+):([0-9]+)\ *$ ]] && [[ -r ${BASH_REMATCH[1]} ]]; then
    file=${BASH_REMATCH[1]}
    center=${BASH_REMATCH[2]}
  elif [[ $file =~ ^(.+):([0-9]+):[0-9]+\ *$ ]] && [[ -r ${BASH_REMATCH[1]} ]]; then
    file=${BASH_REMATCH[1]}
    center=${BASH_REMATCH[2]}
  fi
fi

# Strip all backslashes and trailing whitespace (fzf-tab-completion escaping)
file=${file//\\/}
file=${file%% }

# --- Cache setup ---
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/fzf-preview"
mkdir -p "$CACHE_DIR"

get_cache_key() {
  local mtime=$(stat -c "%Y" "$1" 2>/dev/null)
  local size=$(stat -c "%s" "$1" 2>/dev/null)
  echo "${mtime}_${size}_$(basename "$1")"
}

get_cached_image() {
  local cache_file="$CACHE_DIR/$(get_cache_key "$1")"
  if [[ -f "$cache_file" ]]; then
    touch "$cache_file"
    echo "$cache_file"
    return 0
  fi
  return 1
}

cache_image() {
  local src="$1" original="$2"
  local cache_file="$CACHE_DIR/$(get_cache_key "$original")"
  cp "$src" "$cache_file" 2>/dev/null && echo "$cache_file"
}

# --- Image display ---
show_image() {
  local img="$1"
  local dim=${FZF_PREVIEW_COLUMNS}x${FZF_PREVIEW_LINES}
  if [[ $dim == x ]]; then
    dim=$(stty size < /dev/tty | awk '{print $2 "x" $1}')
  fi

  if [[ $KITTY_WINDOW_ID ]] || { [[ $GHOSTTY_RESOURCES_DIR ]] && command -v kitten > /dev/null; }; then
    kitten icat --clear --transfer-mode=memory --unicode-placeholder --stdin=no \
      --place="$dim@0x0" "$img" | sed '$d' | sed $'$s/$/\e[m/'
  elif command -v chafa > /dev/null; then
    chafa -f symbols -s "$dim" --relative off --optimize 0 --probe off "$img"
  else
    file "$img"
  fi
}

# --- Main preview logic ---
type=$(file --brief --dereference --mime-type -- "$file" 2>/dev/null)

case "$type" in
  inode/directory)
    eza -la --group-directories-first --color=always -- "$file"
    ;;

  application/pdf)
    if cached=$(get_cached_image "$file"); then
      show_image "$cached"
    elif command -v pdftoppm > /dev/null; then
      tmpimg=$(mktemp /tmp/fzf-preview-XXXXXX)
      trap "rm -f '$tmpimg' '${tmpimg}.jpg'" EXIT
      if pdftoppm -singlefile -jpeg "$file" "$tmpimg" 2>/dev/null; then
        cached=$(cache_image "${tmpimg}.jpg" "$file")
        show_image "${cached:-${tmpimg}.jpg}"
      fi
    fi
    ;;

  video/*)
    if cached=$(get_cached_image "$file"); then
      show_image "$cached"
    elif command -v ffmpegthumbnailer > /dev/null; then
      tmpimg=$(mktemp /tmp/fzf-preview-XXXXXX.jpg)
      trap "rm -f '$tmpimg'" EXIT
      if ffmpegthumbnailer -i "$file" -o "$tmpimg" -s 1080 -m 2>/dev/null; then
        cached=$(cache_image "$tmpimg" "$file")
        show_image "${cached:-$tmpimg}"
      fi
    fi
    ;;

  audio/*)
    if cached=$(get_cached_image "$file"); then
      show_image "$cached"
    elif command -v ffmpeg > /dev/null; then
      tmpimg=$(mktemp /tmp/fzf-preview-XXXXXX.jpg)
      trap "rm -f '$tmpimg'" EXIT
      if ffmpeg -y -i "$file" -an -c:v copy "$tmpimg" 2>/dev/null; then
        cached=$(cache_image "$tmpimg" "$file")
        show_image "${cached:-$tmpimg}"
      else
        command -v exiftool > /dev/null && exiftool "$file" 2>/dev/null
      fi
    fi
    ;;

  image/*)
    show_image "$file"
    ;;

  application/zip)
    file "$file"
    echo
    unzip -l "$file" 2>/dev/null
    ;;

  application/gzip)
    file "$file"
    echo
    zcat -l "$file" 2>/dev/null
    ;;

  application/x-xz)
    file "$file"
    echo
    xz -l "$file" 2>/dev/null
    ;;

  application/x-tar|application/x-bzip2)
    file "$file"
    echo
    tar tf "$file" 2>/dev/null | head -100
    ;;

  text/*)
    if [[ "${file: -3}" == ".md" ]] && command -v glow > /dev/null; then
      glow --width $((FZF_PREVIEW_COLUMNS - 1)) "$file"
    else
      bat --style="${BAT_STYLE:-numbers}" --color=always --pager=never \
        --highlight-line="${center:-0}" -- "$file"
    fi
    ;;

  *)
    # Fallback: try bat for anything that looks like text, otherwise show file info
    if file --brief "$file" 2>/dev/null | grep -qi text; then
      bat --style="${BAT_STYLE:-numbers}" --color=always --pager=never \
        --highlight-line="${center:-0}" -- "$file"
    else
      file "$file"
    fi
    ;;
esac
