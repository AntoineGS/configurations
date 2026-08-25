#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/desktop-shell
image_dir=$state_dir/clipboard-images
history_file=$state_dir/clipboard-history.json
current_tmp=""

cleanup() {
  [[ -z $current_tmp ]] || rm -f -- "$current_tmp"
}
trap cleanup EXIT

[[ ! -L $state_dir && ! -L $image_dir ]] || exit 1
install -d -m 700 -- "$state_dir" "$image_dir"
if [[ -e $history_file ]]; then
  [[ -f $history_file && ! -L $history_file ]] || exit 1
  chmod 600 -- "$history_file"
fi
if find "$image_dir" -mindepth 1 -maxdepth 1 -type l -print -quit | grep -q .; then
  exit 1
fi
find "$image_dir" -mindepth 1 -maxdepth 1 -type f -exec chmod 600 -- {} +

if [[ ${1:-} == --init ]]; then
  exit 0
fi

types=$(wl-paste --list-types 2>/dev/null || true)
if [[ ${CLIPBOARD_STATE:-} == sensitive ]] || grep -qx 'x-kde-passwordManagerHint' <<<"$types"; then
  exit 0
fi

emit_image() {
  local mime=$1
  local ext hash file

  current_tmp=$(mktemp --tmpdir="$image_dir" clipboard.XXXXXX)
  chmod 600 -- "$current_tmp"
  cat >"$current_tmp"
  if [[ ! -s $current_tmp ]]; then
    rm -f -- "$current_tmp"
    current_tmp=""
    return 0
  fi

  if [[ $mime == image ]]; then
    mime=$(file --brief --mime-type -- "$current_tmp")
  fi
  case $mime in
    image/png | image/jpeg | image/webp | image/gif | image/bmp | image/tiff) ;;
    *)
      rm -f -- "$current_tmp"
      current_tmp=""
      return 0
      ;;
  esac

  ext=${mime#image/}
  [[ $ext == jpeg ]] && ext=jpg

  hash=$(sha256sum -- "$current_tmp")
  hash=${hash%% *}
  file=$image_dir/$hash.$ext
  if [[ ! -e $file ]]; then
    if ! ln -- "$current_tmp" "$file" 2>/dev/null && [[ ! -f $file ]]; then
      return 1
    fi
  fi
  rm -f -- "$current_tmp"
  current_tmp=""

  jq -cn --arg mime "$mime" --arg path "$file" --arg captured_at "$(date +'%A %H:%M')" \
    '{type:"image", mime:$mime, path:$path, capturedAt:$captured_at}'
}

emit_text() {
  perl -MEncode=decode,FB_CROAK,LEAVE_SRC -MJSON::PP=encode_json -0777 -e '
    my $raw = <STDIN>;
    exit unless length $raw;

    my $encoding;
    my $heuristic_encoding = 0;
    if ($raw =~ /^(?:\xFF\xFE|\xFE\xFF)/) {
      $encoding = "UTF-16";
    } elsif (length($raw) % 2 == 0 && index($raw, "\0") >= 0) {
      my $units = length($raw) / 2;
      my $nuls = $raw =~ tr/\0/\0/;
      if ($nuls * 4 >= $units * 3) {
        my $even_bytes = $raw;
        $even_bytes =~ s/(.)./$1/sg;
        my $even_nuls = $even_bytes =~ tr/\0/\0/;
        undef $even_bytes;

        my $odd_bytes = $raw;
        $odd_bytes =~ s/.(.)/$1/sg;
        my $odd_nuls = $odd_bytes =~ tr/\0/\0/;

        if ($odd_nuls * 4 >= $units * 3 && $even_nuls * 4 < $units) {
          $encoding = "UTF-16LE";
          $heuristic_encoding = 1;
        } elsif ($even_nuls * 4 >= $units * 3 && $odd_nuls * 4 < $units) {
          $encoding = "UTF-16BE";
          $heuristic_encoding = 1;
        }
      }
    }

    my $text = $encoding ? eval { decode($encoding, $raw, FB_CROAK | LEAVE_SRC) } : undef;
    if ($heuristic_encoding && defined($text) && $text =~ /[\x00-\x08\x0E-\x1A\x1C-\x1F]/) {
      $text = undef;
    }
    $text = decode("UTF-8", $raw) unless defined $text;
    print "{\"type\":\"text\",\"text\":", encode_json($text), "}\n";
  '
}

case ${1:-} in
  text) emit_text; exit 0 ;;
  image) emit_image image; exit 0 ;;
  image/png | image/jpeg | image/webp | image/gif | image/bmp | image/tiff) emit_image "$1"; exit 0 ;;
  "") ;;
  *) exit 0 ;;
esac

for mime in image/png image/jpeg image/webp image/gif image/bmp image/tiff; do
  if grep -qx "$mime" <<<"$types"; then
    timeout 2s wl-paste --type "$mime" 2>/dev/null | emit_image "$mime"
    exit 0
  fi
done

if grep -q '^text/' <<<"$types" || grep -qx 'UTF8_STRING' <<<"$types" || grep -qx 'STRING' <<<"$types"; then
  wl-paste --type text --no-newline 2>/dev/null | emit_text
fi
