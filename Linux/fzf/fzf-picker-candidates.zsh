#!/usr/bin/env zsh

emulate -L zsh

set_cursor_shape() {
  local shape=$1
  local tty=${FZF_PICKER_TTY:-/dev/tty}
  local sequence
  case $shape in
    insert) sequence=$'\e[6 q' ;;
    normal) sequence=$'\e[2 q' ;;
    *) return 2 ;;
  esac
  print -rn -- "$sequence" >| "$tty" 2>/dev/null || true
}

encode_path() {
  print -rn -- "$1" | base64 --wrap=0
}

decode_path() {
  local payload=$1 decoded
  [[ -n $payload && $payload != *[^A-Za-z0-9+/=]* ]] || return 1
  decoded=$(print -rn -- "$payload" | base64 --decode 2>/dev/null || exit 1; print x) || return 1
  reply=${decoded%x}
}

escape_display() {
  if [[ $1 != *[\\\']* && $1 != *[[:cntrl:]]* ]]; then
    reply=$1
    return
  fi
  local quoted=${(qqqq)1}
  reply=${quoted[3,-2]}
  local normalized= octal hex
  integer i=1 value
  while (( i <= ${#reply} )); do
    if [[ ${reply[i]} == '\' && ${reply[i + 1]} == '\' ]]; then
      normalized+=${reply[i,i + 1]}
      (( i += 2 ))
    elif [[ ${reply[i]} == '\' && ${reply[i + 1,i + 3]} == [0-7][0-7][0-7] ]]; then
      octal=${reply[i + 1,i + 3]}
      value=$(( 8#$octal ))
      if (( value < 32 || value == 127 )); then
        printf -v hex '%02X' "$value"
        normalized+="\\x$hex"
        (( i += 4 ))
      else
        normalized+=${reply[i]}
        (( ++i ))
      fi
    else
      normalized+=${reply[i]}
      (( ++i ))
    fi
  done
  reply=$normalized
}

emit_candidate_with_payload() {
  local kind=$1 display=$2 payload=$3
  escape_display "$display"
  print -r -- "$kind"$'\t'"$reply"$'\t'"$payload"
}

emit_candidate() {
  local kind=$1 display=$2 raw_path=$3
  emit_candidate_with_payload "$kind" "$display" "$(encode_path "$raw_path")"
}

emit_cd_local_candidates() {
  local dir=$1 name
  [[ -d $dir ]] || return 1
  typeset -a hidden_dirs dirs
  hidden_dirs=()
  dirs=()
  emit_candidate local . "$dir"
  emit_candidate local .. "${dir:h}"
  fd --base-directory "$dir" --type d --max-depth 1 --hidden --no-ignore --color=never --print0 2>/dev/null |
    while IFS= read -r -d $'\0' name; do
      [[ $name == ./* ]] && name=${name[3,-1]}
      name=${name%/}
      [[ $name == .* ]] && hidden_dirs+=("$name") || dirs+=("$name")
    done
  (( pipestatus[1] == 0 )) || return 1
  for name in "${(@oi)hidden_dirs}" "${(@oi)dirs}"; do
    emit_candidate local "$name" "${dir%/}/$name"
  done
}

mode=$1
dir=$2

case $mode in
  encode)
    encode_path "$2"
    print
    ;;
  decode0)
    shift
    for payload in "$@"; do
      decode_path "$payload" || exit 1
      print -rn -- "$reply"$'\0'
    done
    ;;
  cursor)
    set_cursor_shape "$2"
    ;;
  modal)
    keymap_mode=$2
    dir_file=$3
    prompt_file=$4
    keymap_mode_file=$5
    [[ -r $dir_file && -n $prompt_file && -n $keymap_mode_file ]] || exit 1
    decode_path "$(<"$dir_file")" || exit 1
    current_dir=$reply
    escape_display "$current_dir"
    prompt_dir=$reply
    case $keymap_mode in
      insert)
        indicator=I
        actions="enable-search+rebind(ctrl-l,tab,right,ctrl-h,left,shift-tab)+unbind(h,j,k,l,i,a,q,space)"
        cursor_mode=insert
        ;;
      normal)
        indicator=N
        actions="disable-search+rebind(h,j,k,l,i,a,q,space,ctrl-l,tab,right,ctrl-h,left,shift-tab)"
        cursor_mode=normal
        ;;
      add)
        indicator=A
        actions="enable-search+unbind(h,j,k,l,i,a,q,space,ctrl-l,tab,right,ctrl-h,left,shift-tab)+clear-query"
        cursor_mode=insert
        ;;
      *) exit 2 ;;
    esac
    print -r -- "$keymap_mode" >| "$keymap_mode_file"
    print -r -- "[$indicator] ${prompt_dir%/}/ " >| "$prompt_file"
    set_cursor_shape "$cursor_mode"
    print -r -- "$actions+transform-prompt(cat ${(q)prompt_file})"
    ;;
  escape)
    picker=$2
    dir_file=$3
    prompt_file=$4
    keymap_mode_file=$5
    case $picker in
      cd|cp) ;;
      *) exit 2 ;;
    esac
    [[ -r $keymap_mode_file ]] || exit 1
    keymap_mode=$(<"$keymap_mode_file")
    case $keymap_mode in
      insert)
        "$0" modal normal "$dir_file" "$prompt_file" "$keymap_mode_file"
        ;;
      normal)
        print -r -- clear-multi
        ;;
      add)
        actions=$("$0" modal normal "$dir_file" "$prompt_file" "$keymap_mode_file") || exit 1
        print -r -- "$actions+clear-query"
        ;;
      *) exit 2 ;;
    esac
    ;;
  slash)
    picker=$2
    query=$3
    root_payload=$4
    dir_file=$5
    prompt_file=$6
    mode_file=$7
    candidates_file=$8
    keymap_mode_file=$9
    case $picker in
      cd|cp) ;;
      *) exit 2 ;;
    esac
    [[ -r $keymap_mode_file ]] || exit 1
    keymap_mode=$(<"$keymap_mode_file")
    case $keymap_mode in
      add)
        print -r -- 'put(/)'
        return
        ;;
      normal)
        if [[ -n $query ]]; then
          print -r -- ignore
          return
        fi
        ;;
      insert) ;;
      *) exit 2 ;;
    esac
    if [[ -z $query ]]; then
      target_payload=$root_payload
    elif [[ $query == .. ]]; then
      [[ -r $dir_file ]] || exit 1
      target_payload=$("$0" parent "$(<"$dir_file")") || exit 1
    else
      print -r -- 'put(/)'
      return
    fi
    "$0" navigate "$picker" "$target_payload" "$dir_file" "$prompt_file" "$mode_file" \
      "$candidates_file" "$keymap_mode_file"
    ;;
  enter)
    picker=$2
    query=$3
    dir_file=$4
    prompt_file=$5
    mode_file=$6
    candidates_file=$7
    keymap_mode_file=$8
    [[ -r $keymap_mode_file ]] || exit 1
    keymap_mode=$(<"$keymap_mode_file")
    case $keymap_mode in
      insert|normal)
        print -r -- 'print(enter)+accept'
        return
        ;;
      add) ;;
      *) exit 2 ;;
    esac
    [[ -r $dir_file && -n $prompt_file && -n $candidates_file ]] || exit 1
    decode_path "$(<"$dir_file")" || exit 1
    current_dir=$reply
    creation_error() {
      escape_display "$current_dir"
      print -r -- "[A!] ${reply%/}/ " >| "$prompt_file"
      print -r -- "transform-prompt(cat ${(q)prompt_file})"
    }
    if [[ -z $query || $query == /* ]]; then
      creation_error
      return
    fi
    components=("${(@s:/:)query}")
    if (( ${components[(I)..]} != 0 )); then
      creation_error
      return
    fi
    target=${current_dir%/}/$query
    if ! mkdir -p -- "$target" 2>/dev/null || [[ ! -d $target ]]; then
      creation_error
      return
    fi
    target_payload=$(encode_path "$target") || exit 1
    keymap_next=$keymap_mode_file.next
    print -r -- normal >| "$keymap_next" || exit 1
    actions=$("$0" navigate "$picker" "$target_payload" "$dir_file" "$prompt_file" "$mode_file" \
      "$candidates_file" "$keymap_next") || {
      rm -f -- "$keymap_next"
      exit 1
    }
    mv -f -- "$keymap_next" "$keymap_mode_file" || exit 1
    set_cursor_shape normal
    print -r -- "disable-search+rebind(h,j,k,l,i,a,q,space,ctrl-l,tab,right,ctrl-h,left,shift-tab)+$actions"
    ;;
  navigate)
    picker=$2
    target_payload=$3
    dir_file=$4
    prompt_file=$5
    mode_file=$6
    candidates_file=$7
    keymap_mode_file=$8
    decode_path "$target_payload" || exit 1
    raw_target=$reply
    prompt_prefix=
    if [[ -r $keymap_mode_file ]]; then
      keymap_mode=$(<"$keymap_mode_file")
      case $keymap_mode in
        insert) prompt_prefix='[I] ' ;;
        normal) prompt_prefix='[N] ' ;;
        add) prompt_prefix='[A] ' ;;
      esac
    fi
    next_file=$candidates_file.next
    dir_next=$dir_file.next
    prompt_next=$prompt_file.next
    next_files=("$next_file" "$dir_next" "$prompt_next")
    if [[ $mode_file != - ]]; then
      mode_next=$mode_file.next
      next_files+=("$mode_next")
    fi
    case $picker in
      cd) candidate_mode=cd ;;
      cp) candidate_mode=cp ;;
      *) exit 2 ;;
    esac
    "$0" "$candidate_mode" "$raw_target" >| "$next_file" || {
      rm -f -- "${next_files[@]}"
      exit 1
    }
    escape_display "$raw_target"
    prompt_dir=$reply
    print -r -- "$target_payload" >| "$dir_next" || {
      rm -f -- "${next_files[@]}"
      exit 1
    }
    print -r -- "$prompt_prefix${prompt_dir%/}/ " >| "$prompt_next" || {
      rm -f -- "${next_files[@]}"
      exit 1
    }
    if [[ $mode_file != - ]]; then
      print -r -- local >| "$mode_next" || {
        rm -f -- "${next_files[@]}"
        exit 1
      }
      mv -f -- "$mode_next" "$mode_file" || {
        rm -f -- "${next_files[@]}"
        exit 1
      }
    fi
    mv -f -- "$prompt_next" "$prompt_file" || {
      rm -f -- "${next_files[@]}"
      exit 1
    }
    mv -f -- "$dir_next" "$dir_file" || {
      rm -f -- "${next_files[@]}"
      exit 1
    }
    mv -f -- "$next_file" "$candidates_file" || {
      rm -f -- "${next_files[@]}"
      exit 1
    }
    actions="clear-multi+reload-sync(cat ${(q)candidates_file})+transform-prompt(cat ${(q)prompt_file})+clear-query+wait+first"
    print -r -- "$actions"
    ;;
  parent)
    decode_path "$2" || exit 1
    raw_path=${reply:h}
    encode_path "$raw_path"
    print
    ;;
  preview)
    picker=$2
    case $picker in
      cd|cp) ;;
      *) exit 2 ;;
    esac
    decode_path "$3" || exit 1
    if [[ -n ${FZF_PICKER_PREVIEW_COMMAND:-} ]]; then
      "$FZF_PICKER_PREVIEW_COMMAND" "$reply"
    else
      case $picker in
        cd) eza -la --color=always --group-directories-first -- "$reply" ;;
        cp) "${0:A:h}/fzf-preview.sh" --literal "$reply" ;;
        *) exit 2 ;;
      esac
    fi
    ;;
  relative0)
    decode_path "$2" || exit 1
    base=$reply
    shift 2
    for payload in "$@"; do
      decode_path "$payload" || exit 1
      raw_path=$reply
      if IFS= read -r -d $'\0' relative < <(
        realpath --zero --no-symlinks --relative-to="$base" -- "$raw_path" 2>/dev/null
      ); then
        [[ $relative == -* ]] && relative=./$relative
        print -rn -- "$relative"$'\0'
      else
        print -rn -- "$raw_path"$'\0'
      fi
    done
    ;;
  cd-local)
    emit_cd_local_candidates "$dir"
    ;;
  cd)
    local_output=$(emit_cd_local_candidates "$dir") || exit 1
    typeset -A seen_paths
    typeset -a local_records fields
    batch_encoder=${FZF_PICKER_BATCH_ENCODER:-${0:A:h}/fzf-batch-encode.pl}
    zoxide_output=$(mktemp "${TMPDIR:-/tmp}/fzf-picker-zoxide.XXXXXX") || zoxide_output=
    local_records=("${(@f)local_output}")
    for record in "${local_records[@]}"; do
      fields=("${(@ps:\t:)record}")
      seen_paths[${fields[3]}]=1
      print -r -- "$record"
    done
    if [[ -n $zoxide_output ]]; then
      if (setopt pipe_fail; zoxide query --list 2>/dev/null | "$batch_encoder" 2>/dev/null >| "$zoxide_output"); then
        while IFS= read -r -d $'\0' payload && IFS= read -r -d $'\0' dir_path; do
          (( ${+seen_paths[$payload]} )) && continue
          seen_paths[$payload]=1
          emit_candidate_with_payload zoxide "$dir_path" "$payload"
        done < "$zoxide_output"
      fi
      rm -f -- "$zoxide_output"
    fi
    ;;
  cp)
    [[ -d $dir ]] || exit 1
    typeset -a hidden_dirs dirs hidden_files files
    hidden_dirs=()
    dirs=()
    hidden_files=()
    files=()
    emit_candidate directory . "$dir"
    emit_candidate directory .. "${dir:h}"
    fd --base-directory "$dir" --max-depth 1 --hidden --color=never --print0 2>/dev/null |
      while IFS= read -r -d $'\0' name; do
        [[ $name == ./* ]] && name=${name[3,-1]}
        if [[ -d ${dir%/}/$name ]]; then
          name=${name%/}
          [[ $name == .* ]] && hidden_dirs+=("$name") || dirs+=("$name")
        else
          [[ $name == .* ]] && hidden_files+=("$name") || files+=("$name")
        fi
      done
    (( pipestatus[1] == 0 )) || exit 1
    for name in "${(@oi)hidden_dirs}" "${(@oi)dirs}"; do
      emit_candidate directory "$name/" "${dir%/}/$name"
    done
    for name in "${(@oi)hidden_files}" "${(@oi)files}"; do
      emit_candidate file "$name" "${dir%/}/$name"
    done
    ;;
  *)
    print -ru2 -- \
      "usage: $0 {encode|decode0|parent|preview|relative0|cd|cd-local|cp|navigate|modal|escape|slash|enter|cursor} [ARGUMENTS...]"
    exit 2
    ;;
esac
