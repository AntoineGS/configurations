#!/usr/bin/env zsh

emulate -L zsh
set -eu
setopt pipe_fail

script_dir=${0:A:h}
candidate_script=${script_dir:h}/fzf-picker-candidates.zsh
preview_script=${script_dir:h}/fzf-preview.sh
zshrc_script=${script_dir:h:h}/zsh/.zshrc
tmp_dir=$(mktemp -d)
trap 'rm -rf -- "$tmp_dir"' EXIT
integer assertions=0

fail() {
  print -ru2 -- "FAIL: $*"
  exit 1
}

assert_equal() {
  local expected=$1 actual=$2 message=$3
  (( ++assertions ))
  [[ $actual == "$expected" ]] || fail "$message: expected ${(qqq)expected}, got ${(qqq)actual}"
}

assert_file_equal() {
  local expected=$1 actual=$2 message=$3
  (( ++assertions ))
  cmp -s -- "$expected" "$actual" || fail "$message"
}

assert_contains() {
  local expected=$1 actual=$2 message=$3
  (( ++assertions ))
  [[ $actual == *"$expected"* ]] || fail "$message: ${(qqq)actual} does not contain ${(qqq)expected}"
}

assert_not_contains() {
  local unexpected=$1 actual=$2 message=$3
  (( ++assertions ))
  [[ $actual != *"$unexpected"* ]] || fail "$message: ${(qqq)actual} contains ${(qqq)unexpected}"
}

test_codec() {
  local root=$tmp_dir/root name raw_path payload decoded expected record tabless
  local -a fields
  local -a names=(
    $'tab\tname'
    $'line\nname'
    'trailing '
    'back\\slash'
    $'nbsp\u00a0name'
    '-leading'
    $'control\x01name'
    $'ending-newline\n'
  )
  local -a displays=(
    'tab\tname'
    'line\nname'
    'trailing '
    'back\\\\slash'
    $'nbsp\u00a0name'
    '-leading'
    'control\x01name'
    'ending-newline\n'
  )
  local -A records
  integer i record_count=0

  mkdir -- "$root"
  for name in "${names[@]}"; do
    : >| "$root/$name"
  done

  for i in {1..${#names}}; do
    raw_path=$root/${names[i]}
    payload=$("$candidate_script" encode "$raw_path") || fail "encode rejected ${(qqq)raw_path}"
    decoded=$tmp_dir/decoded-$i
    expected=$tmp_dir/expected-$i
    "$candidate_script" decode0 "$payload" >| "$decoded" || fail "decode0 rejected encoded path $i"
    [[ -s $decoded ]] || fail "decode0 emitted no bytes for path $i"
    truncate -s -1 -- "$decoded"
    print -rn -- "$raw_path" >| "$expected"
    assert_file_equal "$expected" "$decoded" "codec changed path bytes for ${(qqq)name}"
  done

  while IFS= read -r record; do
    (( ++record_count ))
    tabless=${record//$'\t'/}
    assert_equal 2 $(( ${#record} - ${#tabless} )) "record $record_count must contain exactly two tabs"
    fields=("${(@ps:\t:)record}")
    records[${fields[3]}]=$record
  done < <("$candidate_script" cp "$root")
  assert_equal $(( ${#names} + 2 )) "$record_count" "candidate output must contain one line per entry plus dot entries"

  for i in {1..${#names}}; do
    raw_path=$root/${names[i]}
    payload=$("$candidate_script" encode "$raw_path") || fail "encode rejected candidate path $i"
    record=${records[$payload]-}
    [[ -n $record ]] || fail "candidate missing for ${(qqq)names[i]}"
    fields=("${(@ps:\t:)record}")
    assert_equal file "${fields[1]}" "candidate kind for ${(qqq)names[i]}"
    if [[ ${names[i]} == $'control\x01name' ]]; then
      (( ++assertions ))
      [[ ${fields[2]} != *'\001'* ]] || fail "candidate display emitted an octal control escape"
    fi
    assert_equal "${displays[i]}" "${fields[2]}" "candidate display for ${(qqq)names[i]}"
    decoded=$tmp_dir/candidate-decoded-$i
    expected=$tmp_dir/candidate-expected-$i
    "$candidate_script" decode0 "${fields[3]}" >| "$decoded" || fail "decode0 rejected candidate payload $i"
    truncate -s -1 -- "$decoded"
    print -rn -- "$raw_path" >| "$expected"
    assert_file_equal "$expected" "$decoded" "candidate payload changed path bytes for ${(qqq)names[i]}"
  done

  (( ++assertions ))
  if "$candidate_script" decode0 'not%base64' >| "$tmp_dir/malformed" 2>/dev/null; then
    fail "decode0 accepted a malformed payload"
  fi

}

test_directory_enumeration() {
  local root=$tmp_dir/directory-enumeration-root picker name raw_path payload record decoded expected
  local -a names displays fields
  local -A records
  integer i record_count expected_count

  names=(
    $'tab\tdirectory'
    $'line\ndirectory'
    'trailing-directory '
    'back\slash-directory'
    $'nbsp\u00a0directory'
    '-leading-directory'
    $'control\x01directory'
    'space directory'
  )
  displays=(
    'tab\tdirectory'
    'line\ndirectory'
    'trailing-directory '
    'back\\slash-directory'
    $'nbsp\u00a0directory'
    '-leading-directory'
    'control\x01directory'
    'space directory'
  )

  mkdir -- "$root"
  for name in "${names[@]}"; do
    mkdir -- "$root/$name"
  done

  for picker in cd-local cp; do
    records=()
    record_count=0
    while IFS= read -r record; do
      (( ++record_count ))
      local tabless=${record//$'\t'/}
      assert_equal 2 $(( ${#record} - ${#tabless} )) "$picker record $record_count must contain exactly two tabs"
      fields=("${(@ps:\t:)record}")
      records[${fields[3]}]=$record
    done < <("$candidate_script" "$picker" "$root")
    expected_count=$(( ${#names} + 2 ))
    assert_equal "$expected_count" "$record_count" "$picker must emit one safe record per directory plus dot entries"

    for i in {1..${#names}}; do
      raw_path=$root/${names[i]}
      payload=$("$candidate_script" encode "$raw_path") || fail "$picker encode rejected ${(qqq)raw_path}"
      record=${records[$payload]-}
      [[ -n $record ]] || fail "$picker candidate missing for ${(qqq)names[i]}"
      fields=("${(@ps:\t:)record}")
      if [[ $picker == cd-local ]]; then
        assert_equal local "${fields[1]}" "cd-local kind for ${(qqq)names[i]}"
        assert_equal "${displays[i]}" "${fields[2]}" "cd-local display for ${(qqq)names[i]}"
      else
        assert_equal directory "${fields[1]}" "cp kind for ${(qqq)names[i]}"
        assert_equal "${displays[i]}/" "${fields[2]}" "cp display for ${(qqq)names[i]}"
      fi
      decoded=$tmp_dir/$picker-directory-decoded-$i
      expected=$tmp_dir/$picker-directory-expected-$i
      "$candidate_script" decode0 "${fields[3]}" >| "$decoded" || fail "$picker decode0 rejected directory $i"
      truncate -s -1 -- "$decoded"
      print -rn -- "$raw_path" >| "$expected"
      assert_file_equal "$expected" "$decoded" "$picker payload changed directory bytes for ${(qqq)names[i]}"
    done
  done
}

test_cd_merged() {
  local root=$tmp_dir/cd-merged-root fake_bin=$tmp_dir/cd-merged-bin
  local external_one=$tmp_dir/zoxide-one external_two=$tmp_dir/zoxide-two
  local output=$tmp_dir/cd-merged-output failed_output=$tmp_dir/cd-merged-failed
  local record payload decoded_path
  local -a fields kinds displays decoded expected_paths expected_kinds expected_displays

  mkdir -p -- "$root/.hidden" "$root/visible" "$external_one" "$external_two" "$fake_bin"
  print -r -- '#!/usr/bin/env zsh' >| "$fake_bin/zoxide"
  print -r -- 'print -r -- "$FZF_PICKER_TEST_LOCAL_DUPLICATE"' >> "$fake_bin/zoxide"
  print -r -- 'print -r -- "$FZF_PICKER_TEST_ZOXIDE_ONE"' >> "$fake_bin/zoxide"
  print -r -- 'print -r -- "$FZF_PICKER_TEST_ZOXIDE_TWO"' >> "$fake_bin/zoxide"
  chmod +x -- "$fake_bin/zoxide"

  FZF_PICKER_TEST_LOCAL_DUPLICATE=$root/visible \
    FZF_PICKER_TEST_ZOXIDE_ONE=$external_one \
    FZF_PICKER_TEST_ZOXIDE_TWO=$external_two \
    PATH="$fake_bin:$PATH" "$candidate_script" cd "$root" >| "$output" || fail "merged cd generation failed"

  while IFS= read -r record; do
    fields=("${(@ps:\t:)record}")
    kinds+=("${fields[1]}")
    displays+=("${fields[2]}")
    payload=${fields[3]}
    IFS= read -r -d $'\0' decoded_path < <("$candidate_script" decode0 "$payload") || \
      fail "merged cd emitted an invalid payload"
    decoded+=("$decoded_path")
  done < "$output"

  expected_paths=("$root" "${root:h}" "$root/.hidden" "$root/visible" "$external_one" "$external_two")
  expected_kinds=(local local local local zoxide zoxide)
  expected_displays=(. .. .hidden visible "$external_one" "$external_two")
  assert_equal "${(j:$'\0':)expected_paths}" "${(j:$'\0':)decoded}" \
    "merged cd did not preserve local-first deduplicated path order"
  assert_equal "${(j:$'\0':)expected_kinds}" "${(j:$'\0':)kinds}" \
    "merged cd emitted incorrect candidate kinds"
  assert_equal "${(j:$'\0':)expected_displays}" "${(j:$'\0':)displays}" \
    "merged cd emitted incorrect displays"

  print -r -- '#!/usr/bin/env zsh' >| "$fake_bin/zoxide"
  print -r -- 'exit 7' >> "$fake_bin/zoxide"
  chmod +x -- "$fake_bin/zoxide"
  PATH="$fake_bin:$PATH" "$candidate_script" cd "$root" >| "$failed_output" || \
    fail "zoxide failure prevented local cd generation"
  "$candidate_script" cd-local "$root" >| "$output" || fail "local comparison generation failed"
  assert_file_equal "$output" "$failed_output" "zoxide failure changed local cd candidates"
}

test_operations() {
  local root=$tmp_dir/operations-root raw_dir child dash_child missing dir_payload child_payload parent_payload decoded
  local dir_file=$tmp_dir/dir prompt_file=$tmp_dir/prompt source_mode_file=$tmp_dir/source-mode
  local candidates_file=$tmp_dir/candidates keymap_mode_file=$tmp_dir/keymap-mode
  local expected=$tmp_dir/expected actual=$tmp_dir/actual before=$tmp_dir/before recorder=$tmp_dir/preview-recorder
  local preview_output=$tmp_dir/preview-output record payload raw_path malformed='not%base64'
  local fake_bin=$tmp_dir/fake-bin replace_bin=$tmp_dir/replace-bin actions_output=$tmp_dir/actions-output
  local -a fields decoded_candidates expected_candidates

  root=$tmp_dir/operations-root
  raw_dir=$root/$'directory-ending-newline\n'
  child=$raw_dir/$'child-ending-newline\n'
  dash_child=$raw_dir/-leading
  mkdir -p -- "$child" "$dash_child"
  dir_payload=$("$candidate_script" encode "$raw_dir") || fail "encode rejected operation directory"

  parent_payload=$("$candidate_script" parent "$dir_payload") || fail "parent rejected encoded directory"
  "$candidate_script" decode0 "$parent_payload" >| "$actual" || fail "decode0 rejected parent result"
  print -rn -- "$root"$'\0' >| "$expected"
  assert_file_equal "$expected" "$actual" "parent changed path bytes"

  print -r -- stale >| "$dir_file"
  print -r -- stale >| "$prompt_file"
  print -r -- zoxide >| "$source_mode_file"
  print -r -- stale >| "$candidates_file"
  print -r -- normal >| "$keymap_mode_file"
  "$candidate_script" navigate cp "$dir_payload" "$dir_file" "$prompt_file" "$source_mode_file" \
    "$candidates_file" "$keymap_mode_file" >/dev/null || fail "navigate rejected encoded directory"
  assert_equal "$dir_payload" "$(<"$dir_file")" "navigate did not preserve encoded directory state"
  assert_equal local "$(<"$source_mode_file")" "navigate did not update source mode"
  assert_equal "[N] ${raw_dir//$'\n'/\\n}/ " "$(<"$prompt_file")" "navigate prompt did not escape decoded directory"

  print -r -- add >| "$keymap_mode_file"
  "$candidate_script" navigate cp "$dir_payload" "$dir_file" "$prompt_file" - \
    "$candidates_file" "$keymap_mode_file" >/dev/null || fail "navigate rejected Add keymap state"
  assert_equal "[A] ${raw_dir//$'\n'/\\n}/ " "$(<"$prompt_file")" "navigate did not preserve Add prompt state"
  print -r -- insert >| "$keymap_mode_file"
  "$candidate_script" navigate cp "$dir_payload" "$dir_file" "$prompt_file" - \
    "$candidates_file" "$keymap_mode_file" >/dev/null || fail "navigate rejected Insert keymap state"
  assert_equal "[I] ${raw_dir//$'\n'/\\n}/ " "$(<"$prompt_file")" "navigate did not preserve Insert prompt state"

  decoded_candidates=()
  while IFS= read -r record; do
    fields=("${(@ps:\t:)record}")
    payload=${fields[3]}
    IFS= read -r -d $'\0' raw_path < <("$candidate_script" decode0 "$payload") || \
      fail "navigate emitted invalid candidate payload"
    decoded_candidates+=("$raw_path")
  done < "$candidates_file"
  expected_candidates=("$raw_dir" "${raw_dir:h}" "$child" "$dash_child")
  assert_equal "${(j:$'\0':)expected_candidates}" "${(j:$'\0':)decoded_candidates}" \
    "navigate reloaded candidates from the wrong directory"

  payload=$("$candidate_script" encode "$child")
  parent_payload=$("$candidate_script" encode "$dash_child")
  : >| "$tmp_dir/not-a-directory"
  missing=$tmp_dir/not-a-directory/$'missing-ending-newline\n'
  decoded=$("$candidate_script" encode "$missing")
  "$candidate_script" relative0 "$dir_payload" "$payload" "$parent_payload" "$decoded" >| "$actual" || \
    fail "relative0 rejected encoded paths"
  print -rn -- $'child-ending-newline\n\0./-leading\0'"$missing"$'\0' >| "$expected"
  assert_file_equal "$expected" "$actual" "relative0 changed relative path bytes"

  cp -- "$candidates_file" "$before"
  local old_dir=$(<"$dir_file") old_prompt=$(<"$prompt_file") old_source=$(<"$source_mode_file")
  if "$candidate_script" navigate cp "$malformed" "$dir_file" "$prompt_file" "$source_mode_file" \
    "$candidates_file" "$keymap_mode_file" >/dev/null 2>&1; then
    fail "navigate accepted malformed payload"
  fi
  assert_file_equal "$before" "$candidates_file" "malformed navigation changed candidates"
  assert_equal "$old_dir" "$(<"$dir_file")" "malformed navigation changed directory state"
  assert_equal "$old_prompt" "$(<"$prompt_file")" "malformed navigation changed prompt state"
  assert_equal "$old_source" "$(<"$source_mode_file")" "malformed navigation changed source mode"

  mkdir -- "$fake_bin"
  print -r -- '#!/usr/bin/env zsh' >| "$fake_bin/fd"
  print -r -- 'exit 7' >> "$fake_bin/fd"
  chmod +x -- "$fake_bin/fd"
  (( ++assertions ))
  if PATH="$fake_bin:$PATH" "$candidate_script" cd-local "$raw_dir" >| "$actual" 2>/dev/null; then
    fail "cd-local masked fd failure"
  fi
  (( ++assertions ))
  if PATH="$fake_bin:$PATH" "$candidate_script" cp "$raw_dir" >| "$actual" 2>/dev/null; then
    fail "cp masked fd failure"
  fi
  cp -- "$candidates_file" "$before"
  if PATH="$fake_bin:$PATH" "$candidate_script" navigate cp "$dir_payload" "$dir_file" "$prompt_file" \
    "$source_mode_file" "$candidates_file" "$keymap_mode_file" >| "$actions_output" 2>/dev/null; then
    fail "navigate accepted candidate enumeration failure"
  fi
  assert_file_equal "$before" "$candidates_file" "enumeration failure changed candidates"
  assert_equal "$old_dir" "$(<"$dir_file")" "enumeration failure changed directory state"
  assert_equal "$old_prompt" "$(<"$prompt_file")" "enumeration failure changed prompt state"
  assert_equal "$old_source" "$(<"$source_mode_file")" "enumeration failure changed source mode"
  assert_equal '' "$(<"$actions_output")" "enumeration failure emitted reload actions"

  mkdir -- "$replace_bin"
  print -r -- '#!/usr/bin/env zsh' >| "$replace_bin/mv"
  print -r -- 'exit 9' >> "$replace_bin/mv"
  chmod +x -- "$replace_bin/mv"
  child_payload=$("$candidate_script" encode "$child")
  cp -- "$candidates_file" "$before"
  if PATH="$replace_bin:$PATH" "$candidate_script" navigate cp "$child_payload" "$dir_file" "$prompt_file" \
    "$source_mode_file" "$candidates_file" "$keymap_mode_file" >| "$actions_output" 2>/dev/null; then
    fail "navigate accepted candidate replacement failure"
  fi
  assert_file_equal "$before" "$candidates_file" "replacement failure changed candidates"
  assert_equal "$old_dir" "$(<"$dir_file")" "replacement failure changed directory state"
  assert_equal "$old_prompt" "$(<"$prompt_file")" "replacement failure changed prompt state"
  assert_equal "$old_source" "$(<"$source_mode_file")" "replacement failure changed source mode"
  assert_equal '' "$(<"$actions_output")" "replacement failure emitted reload actions"

  cp -- "$candidates_file" "$before"
  if "$candidate_script" navigate cp "$child_payload" "$dir_file" "$tmp_dir/missing-state/prompt" \
    "$source_mode_file" "$candidates_file" "$keymap_mode_file" >| "$actions_output" 2>/dev/null; then
    fail "navigate accepted state preparation failure"
  fi
  assert_file_equal "$before" "$candidates_file" "state preparation failure changed candidates"
  assert_equal "$old_dir" "$(<"$dir_file")" "state preparation failure changed directory state"
  assert_equal "$old_source" "$(<"$source_mode_file")" "state preparation failure changed source mode"
  assert_equal '' "$(<"$actions_output")" "state preparation failure emitted reload actions"

  print -r -- '#!/usr/bin/env zsh' >| "$recorder"
  print -r -- 'print -rn -- "$1"$'"'"'\0'"'"' >| "$FZF_PICKER_PREVIEW_OUTPUT"' >> "$recorder"
  chmod +x -- "$recorder"
  FZF_PICKER_PREVIEW_COMMAND=$recorder FZF_PICKER_PREVIEW_OUTPUT=$preview_output \
    "$candidate_script" preview cp "$dir_payload" || fail "preview rejected encoded path"
  print -rn -- "$raw_dir"$'\0' >| "$expected"
  assert_file_equal "$expected" "$preview_output" "preview command received changed path bytes"
  rm -f -- "$preview_output"
  (( ++assertions ))
  if FZF_PICKER_PREVIEW_COMMAND=$recorder FZF_PICKER_PREVIEW_OUTPUT=$preview_output \
    "$candidate_script" preview invalid "$dir_payload" 2>/dev/null; then
    fail "preview seam accepted invalid picker"
  fi
  (( ++assertions ))
  [[ ! -e $preview_output ]] || fail "invalid picker invoked preview seam"
}

test_modal() {
  local root=$tmp_dir/modal-root dir_file=$tmp_dir/modal-dir prompt_file=$tmp_dir/modal-prompt
  local keymap_mode_file=$tmp_dir/modal-keymap tty_file=$tmp_dir/modal-tty actions expected=$tmp_dir/modal-expected
  local dir_payload

  mkdir -- "$root"
  dir_payload=$("$candidate_script" encode "$root") || fail "encode rejected modal directory"
  print -r -- "$dir_payload" >| "$dir_file"

  actions=$(FZF_PICKER_TTY=$tty_file "$candidate_script" modal insert "$dir_file" "$prompt_file" "$keymap_mode_file") || \
    fail "modal rejected Insert mode"
  assert_equal insert "$(<"$keymap_mode_file")" "Insert transition wrote the wrong keymap mode"
  assert_contains 'enable-search' "$actions" "Insert mode did not enable search"
  assert_contains 'unbind(h,j,k,l,i,a,q,space)' "$actions" "Insert mode did not unbind Normal keys"
  assert_contains 'rebind(ctrl-l,tab,right,ctrl-h,left,shift-tab)' "$actions" \
    "Insert mode did not restore directory navigation keys"
  print -rn -- $'\e[6 q' >| "$expected"
  assert_file_equal "$expected" "$tty_file" "Insert mode did not set a line cursor"

  actions=$(FZF_PICKER_TTY=$tty_file "$candidate_script" escape cd "$dir_file" "$prompt_file" "$keymap_mode_file") || \
    fail "escape rejected Insert mode"
  assert_equal normal "$(<"$keymap_mode_file")" "Insert Esc did not enter Normal mode"
  assert_not_contains 'clear-multi' "$actions" "Insert Esc cleared marks"

  actions=$(FZF_PICKER_TTY=$tty_file "$candidate_script" escape cd "$dir_file" "$prompt_file" "$keymap_mode_file") || \
    fail "escape rejected Normal mode"
  assert_equal normal "$(<"$keymap_mode_file")" "Normal Esc changed keymap mode"
  assert_equal 'clear-multi' "$actions" "Normal Esc did not only clear marks"

  actions=$(FZF_PICKER_TTY=$tty_file "$candidate_script" modal add "$dir_file" "$prompt_file" "$keymap_mode_file") || \
    fail "modal rejected Add mode"
  assert_equal add "$(<"$keymap_mode_file")" "Normal a transition did not enter Add mode"
  assert_contains 'enable-search' "$actions" "Add mode did not enable search"
  assert_contains 'unbind(h,j,k,l,i,a,q,space,ctrl-l,tab,right,ctrl-h,left,shift-tab)' "$actions" \
    "Add mode did not disable directory navigation and source switching keys"
  assert_contains 'clear-query' "$actions" "Add mode did not clear the query"
  print -rn -- $'\e[6 q' >| "$expected"
  assert_file_equal "$expected" "$tty_file" "Add mode did not set a line cursor"

  actions=$(FZF_PICKER_TTY=$tty_file "$candidate_script" escape cd "$dir_file" "$prompt_file" "$keymap_mode_file") || \
    fail "escape rejected Add mode"
  assert_equal normal "$(<"$keymap_mode_file")" "Add Esc did not enter Normal mode"
  assert_contains 'rebind(h,j,k,l,i,a,q,space,ctrl-l,tab,right,ctrl-h,left,shift-tab)' "$actions" \
    "Add Esc did not restore directory navigation keys"
  assert_contains 'clear-query' "$actions" "Add Esc did not clear the query"
  assert_not_contains 'clear-multi' "$actions" "Add Esc cleared marks"

  print -r -- insert >| "$keymap_mode_file"
  actions=$("$candidate_script" enter cd ignored "$dir_file" "$prompt_file" - "$tmp_dir/modal-candidates" \
    "$keymap_mode_file") || fail "enter rejected Insert mode"
  assert_equal 'print(enter)+accept' "$actions" "Insert Enter did not accept"
  print -r -- normal >| "$keymap_mode_file"
  actions=$("$candidate_script" enter cd ignored "$dir_file" "$prompt_file" - "$tmp_dir/modal-candidates" \
    "$keymap_mode_file") || fail "enter rejected Normal mode"
  assert_equal 'print(enter)+accept' "$actions" "Normal Enter did not accept"
}

test_create() {
  local root=$tmp_dir/create-root target existing_file dir_file=$tmp_dir/create-dir prompt_file=$tmp_dir/create-prompt
  local source_mode_file=$tmp_dir/create-source candidates_file=$tmp_dir/create-candidates
  local keymap_mode_file=$tmp_dir/create-keymap tty_file=$tmp_dir/create-tty actions query dir_payload target_payload
  local -a invalid_queries

  root=$tmp_dir/create-root
  target=$root/projects/new
  existing_file=$root/existing-file
  mkdir -p -- "$root/projects"
  : >| "$existing_file"
  dir_payload=$("$candidate_script" encode "$root") || fail "encode rejected creation directory"

  print -r -- "$dir_payload" >| "$dir_file"
  print -r -- '[A] stale/ ' >| "$prompt_file"
  print -r -- zoxide >| "$source_mode_file"
  print -r -- stale >| "$candidates_file"
  print -r -- add >| "$keymap_mode_file"
  actions=$(FZF_PICKER_TTY=$tty_file "$candidate_script" enter cd projects/new "$dir_file" "$prompt_file" \
    "$source_mode_file" "$candidates_file" "$keymap_mode_file") || fail "Add Enter rejected a valid target"
  (( ++assertions ))
  [[ -d $target ]] || fail "Add Enter did not create the requested directory"
  target_payload=$("$candidate_script" encode "$target") || fail "encode rejected created directory"
  assert_equal "$target_payload" "$(<"$dir_file")" "Add Enter did not navigate into the created directory"
  assert_equal normal "$(<"$keymap_mode_file")" "successful Add Enter did not enter Normal mode"
  assert_equal local "$(<"$source_mode_file")" "successful Add Enter did not switch cd source mode"
  assert_equal "[N] ${target%/}/ " "$(<"$prompt_file")" "successful Add Enter wrote the wrong prompt"
  assert_contains 'disable-search+rebind(h,j,k,l,i,a,q,space,ctrl-l,tab,right,ctrl-h,left,shift-tab)' "$actions" \
    "successful Add Enter did not activate the Normal keymap"
  assert_contains 'clear-multi' "$actions" "successful Add Enter did not clear marks"
  assert_contains 'clear-query' "$actions" "successful Add Enter did not clear the query"
  assert_contains 'reload-sync' "$actions" "successful Add Enter did not reload candidates"

  print -r -- "$dir_payload" >| "$dir_file"
  print -r -- add >| "$keymap_mode_file"
  print -r -- local >| "$source_mode_file"
  actions=$(FZF_PICKER_TTY=$tty_file "$candidate_script" enter cd projects "$dir_file" "$prompt_file" \
    "$source_mode_file" "$candidates_file" "$keymap_mode_file") || fail "Add Enter rejected an existing directory"
  target_payload=$("$candidate_script" encode "$root/projects") || fail "encode rejected existing directory"
  assert_equal "$target_payload" "$(<"$dir_file")" "Add Enter did not enter an existing directory"
  assert_equal normal "$(<"$keymap_mode_file")" "entering an existing directory did not enter Normal mode"

  invalid_queries=('' /absolute ../escape one/../escape existing-file)
  for query in "${invalid_queries[@]}"; do
    print -r -- "$dir_payload" >| "$dir_file"
    print -r -- '[A] stale/ ' >| "$prompt_file"
    print -r -- add >| "$keymap_mode_file"
    print -r -- zoxide >| "$source_mode_file"
    print -r -- stale >| "$candidates_file"
    actions=$(FZF_PICKER_TTY=$tty_file "$candidate_script" enter cd "$query" "$dir_file" "$prompt_file" \
      "$source_mode_file" "$candidates_file" "$keymap_mode_file") || fail "Add Enter exited for invalid target ${(qqq)query}"
    assert_equal add "$(<"$keymap_mode_file")" "invalid target ${(qqq)query} left Add mode"
    assert_equal "$dir_payload" "$(<"$dir_file")" "invalid target ${(qqq)query} changed directory state"
    assert_equal zoxide "$(<"$source_mode_file")" "invalid target ${(qqq)query} changed source mode"
    assert_equal stale "$(<"$candidates_file")" "invalid target ${(qqq)query} changed candidates"
    assert_equal "[A!] ${root%/}/ " "$(<"$prompt_file")" "invalid target ${(qqq)query} wrote the wrong prompt"
    assert_contains 'transform-prompt' "$actions" "invalid target ${(qqq)query} did not refresh the prompt"
    assert_not_contains 'clear-query' "$actions" "invalid target ${(qqq)query} cleared the query"
    assert_not_contains 'reload' "$actions" "invalid target ${(qqq)query} reloaded candidates"
  done
}

test_preview() {
  local root=$tmp_dir/preview-root cache=$tmp_dir/preview-cache output
  local nbsp_path=$root/$'before\u00a0after' newline_path=$root/$'ending-newline\n' actual_path=$root/actual
  local nbsp_marker='literal-nbsp-marker' newline_marker='literal-newline-marker'
  local completion_marker='completion-field-marker'

  mkdir -- "$root"
  print -r -- "$nbsp_marker" >| "$nbsp_path"
  print -r -- "$newline_marker" >| "$newline_path"
  print -r -- "$completion_marker" >| "$actual_path"

  output=$(XDG_CACHE_HOME=$cache BAT_STYLE=plain "$preview_script" --literal "$newline_path") || \
    fail "literal trailing-newline preview failed"
  assert_contains "$newline_marker" "$output" "literal preview changed a trailing-newline path"

  output=$(XDG_CACHE_HOME=$cache BAT_STYLE=plain "$preview_script" --literal "$nbsp_path") || \
    fail "literal NBSP preview failed"
  assert_contains "$nbsp_marker" "$output" "literal preview changed an NBSP path"

  output=$(XDG_CACHE_HOME=$cache BAT_STYLE=plain "$preview_script" \
    "$root/fullvalue"$'\u00a0'"$actual_path") || fail "fzf-tab completion preview failed"
  assert_contains "$completion_marker" "$output" "non-literal preview did not select completion field two"
}

test_zshrc_cd() {
  local zshrc cd_picker after_start start_delimiter end_delimiter marker stripped
  local fzf_call without_fzf
  local picker_home=$tmp_dir/cd-picker-home picker_helper expected
  integer accept_count=0

  zshrc=$(<"$zshrc_script")
  start_delimiter='_fzf_cd_navigate() {'
  end_delimiter='zle -N _fzf_cd_navigate'
  (( ++assertions ))
  [[ $zshrc == *$start_delimiter* ]] || fail "cd picker start delimiter is missing"
  after_start=${zshrc#*$start_delimiter}
  (( ++assertions ))
  [[ $after_start == *$end_delimiter* ]] || fail "cd picker end delimiter is missing or precedes its start"
  cd_picker=${after_start%%$end_delimiter*}

  assert_contains '$candidate_helper encode "$PWD" >| $dir_file' "$cd_picker" \
    "cd picker did not initialize encoded directory state"
  assert_contains 'root_payload=$($candidate_helper encode /)' "$cd_picker" \
    "cd picker did not precompute the encoded root"
  assert_contains 'home_payload=$($candidate_helper encode "$HOME")' "$cd_picker" \
    "cd picker did not precompute the encoded home directory"
  assert_contains '${(q)candidate_helper} escape cd' "$cd_picker" "cd picker Esc did not use helper escape mode"
  assert_contains '${(q)candidate_helper} enter cd {q}' "$cd_picker" "cd picker Enter did not use helper enter mode"
  assert_contains '${(q)candidate_helper} modal add' "$cd_picker" "cd picker Normal a did not enter Add mode"
  assert_contains 'start:unbind(h,j,k,l,i,a,q,space)' "$cd_picker" \
    "cd picker initial keymap did not unbind Normal a"

  marker='{3}'
  stripped=${cd_picker//$marker/}
  assert_equal 3 $(( (${#cd_picker} - ${#stripped}) / ${#marker} )) \
    "cd picker did not restrict field three to two navigation inputs and helper preview"
  marker='target={3}'
  stripped=${cd_picker//$marker/}
  assert_equal 2 $(( (${#cd_picker} - ${#stripped}) / ${#marker} )) \
    "cd picker did not assign both field-three navigation inputs as encoded payloads"
  marker='${(q)candidate_helper} navigate cd \"\$target\"'
  stripped=${cd_picker//$marker/}
  assert_equal 2 $(( (${#cd_picker} - ${#stripped}) / ${#marker} )) \
    "cd picker did not route both field-three navigation payloads through helper navigate"
  assert_contains '${(q)candidate_helper} parent \"\$target\"' "$cd_picker" \
    "cd picker left action did not use helper parent mode"
  assert_contains '${(q)candidate_helper} preview cd {3}' "$cd_picker" \
    "cd picker preview did not use encoded helper mode"
  assert_contains 'target_payload=${fields[3]}' "$cd_picker" \
    "cd picker did not parse the accepted record's encoded field three"

  marker='${(q)candidate_helper} navigate cd '
  stripped=${cd_picker//$marker/}
  assert_equal 4 $(( (${#cd_picker} - ${#stripped}) / ${#marker} )) \
    "cd picker contains an unexpected navigation destination"
  assert_contains '${(q)candidate_helper} navigate cd ${(q)root_payload}' "$cd_picker" \
    "cd picker root binding did not navigate with the precomputed payload"
  assert_contains '${(q)candidate_helper} navigate cd ${(q)home_payload}' "$cd_picker" \
    "cd picker home binding did not navigate with the precomputed payload"
  assert_not_contains '${(q)candidate_helper} navigate cd /' "$cd_picker" \
    "cd picker passed raw root to helper navigate"
  assert_not_contains '${(q)candidate_helper} navigate cd ${(q)HOME}' "$cd_picker" \
    "cd picker passed raw home to helper navigate"
  assert_not_contains 'eza ' "$cd_picker" "cd picker passed encoded field three directly to eza"
  assert_not_contains 'fzf-preview.sh' "$cd_picker" \
    "cd picker passed encoded field three directly to the preview script"
  assert_not_contains ':h}' "$cd_picker" "cd picker action applied a raw path modifier"
  assert_contains '$candidate_helper decode0 "$target_payload"' "$cd_picker" \
    "cd picker did not decode the accepted payload"
  assert_contains 'while IFS= read -r -d' "$cd_picker" \
    "cd picker did not consume decoded output with a NUL-aware read"
  assert_contains 'done < <($candidate_helper decode0 "$target_payload")' "$cd_picker" \
    "cd picker decoded the accepted target through command substitution"
  assert_contains '(( target_count != 1 ))' "$cd_picker" "cd picker did not require exactly one decoded target"
  assert_contains 'BUFFER="builtin cd -- ${(q)target}"' "$cd_picker" \
    "cd picker did not construct cd from the decoded target"
  assert_contains '--multi=1' "$cd_picker" "cd picker lost single-selection mode"
  assert_contains '--sort --print-query' "$cd_picker" "cd picker lost query output"
  assert_contains 'clear-multi+toggle-sort+reload-sync' "$cd_picker" \
    "cd picker source switching did not clear marks"
  fzf_call='    fzf '
  without_fzf=${cd_picker//$fzf_call/}
  assert_equal 1 $(( (${#cd_picker} - ${#without_fzf}) / ${#fzf_call} )) \
    "cd picker did not retain exactly one fzf process"

  picker_helper=$picker_home/.config/fzf/fzf-picker-candidates.zsh
  mkdir -p -- "${picker_helper:h}"
  print -r -- '#!/usr/bin/env zsh' >| "$picker_helper"
  print -r -- 'emulate -L zsh' >> "$picker_helper"
  print -r -- 'case $1 in' >> "$picker_helper"
  print -r -- '  cd-local) print -r -- $'"'"'local\tvisible\tencoded-target'"'"' ;;' >> "$picker_helper"
  print -r -- '  cd-zoxide) ;;' >> "$picker_helper"
  print -r -- '  encode) print -r -- encoded-directory ;;' >> "$picker_helper"
  print -r -- '  modal)' >> "$picker_helper"
  print -r -- '    print -r -- "$2" >| "$5"' >> "$picker_helper"
  print -r -- '    print -r -- prompt >| "$4"' >> "$picker_helper"
  print -r -- '    ;;' >> "$picker_helper"
  print -r -- '  cursor) ;;' >> "$picker_helper"
  print -r -- '  decode0) print -rn -- "$FZF_PICKER_TEST_TARGET"$'"'"'\0'"'"' ;;' >> "$picker_helper"
  print -r -- '  *) exit 2 ;;' >> "$picker_helper"
  print -r -- 'esac' >> "$picker_helper"
  chmod +x -- "$picker_helper"

  eval "$start_delimiter$cd_picker"
  fzf() {
    local record
    while IFS= read -r record; do :; done
    print -r -- ''
    print -r -- enter
    print -r -- $'local\tvisible\tencoded-target'
  }
  zle() {
    case $1 in
      accept-line) (( ++accept_count )) ;;
      *) : ;;
    esac
  }
  local HOME=$picker_home TMPDIR=$tmp_dir
  local -x FZF_PICKER_TEST_TARGET=$'directory-ending-newline\n'

  BUFFER='cd ' CURSOR=3
  _fzf_cd_navigate
  expected="builtin cd -- ${(q)FZF_PICKER_TEST_TARGET}"
  assert_equal "$expected" "$BUFFER" "cd picker lost the decoded accepted target at EOF"
  assert_equal 1 "$accept_count" "cd picker did not accept the decoded target"

  unfunction fzf zle _fzf_cd_navigate
}

test_zshrc_cp() {
  local zshrc cp_picker after_start start_delimiter end_delimiter marker stripped
  local fzf_call without_fzf
  local picker_home=$tmp_dir/cp-picker-home picker_helper candidate_source selection_source
  local first_path='first path' third_path='third path'
  local first_record duplicate_record third_record unknown_record expected

  zshrc=$(<"$zshrc_script")
  start_delimiter='_fzf_cp_complete() {'
  end_delimiter='zle -N _fzf_cp_complete'
  (( ++assertions ))
  [[ $zshrc == *$start_delimiter* ]] || fail "cp picker start delimiter is missing"
  after_start=${zshrc#*$start_delimiter}
  (( ++assertions ))
  [[ $after_start == *$end_delimiter* ]] || fail "cp picker end delimiter is missing or precedes its start"
  cp_picker=${after_start%%$end_delimiter*}

  assert_contains 'pwd_payload=$($candidate_helper encode "$PWD")' "$cp_picker" \
    "cp picker did not encode the insertion base"
  assert_contains 'print -r -- "$pwd_payload" >| $dir_file' "$cp_picker" \
    "cp picker did not initialize encoded directory state"
  assert_contains 'root_payload=$($candidate_helper encode /)' "$cp_picker" \
    "cp picker did not precompute the encoded root"
  assert_contains 'home_payload=$($candidate_helper encode "$HOME")' "$cp_picker" \
    "cp picker did not precompute the encoded home directory"
  assert_contains '--multi \' "$cp_picker" "cp picker did not enable unrestricted multi-selection"
  assert_not_contains '--multi=1' "$cp_picker" "cp picker retained single-selection mode"
  assert_contains '${(q)candidate_helper} escape cp' "$cp_picker" "cp picker Esc did not use helper escape mode"
  assert_contains '${(q)candidate_helper} enter cp {q}' "$cp_picker" "cp picker Enter did not use helper enter mode"
  assert_contains '${(q)candidate_helper} modal add' "$cp_picker" "cp picker Normal a did not enter Add mode"
  assert_contains 'space:toggle' "$cp_picker" "cp picker Normal Space did not toggle marks"
  assert_not_contains 'space:clear-multi+toggle' "$cp_picker" "cp picker Normal Space still cleared existing marks"
  assert_contains 'start:unbind(h,j,k,l,i,a,q,space)' "$cp_picker" \
    "cp picker initial keymap did not unbind Normal a"

  marker='${(q)candidate_helper} navigate cp '
  stripped=${cp_picker//$marker/}
  assert_equal 4 $(( (${#cp_picker} - ${#stripped}) / ${#marker} )) \
    "cp picker contains an unexpected navigation destination"
  assert_contains '${(q)candidate_helper} navigate cp \"\$target\"' "$cp_picker" \
    "cp picker did not route field-three navigation through helper navigate"
  assert_contains '${(q)candidate_helper} parent \"\$target\"' "$cp_picker" \
    "cp picker left action did not use helper parent mode"
  assert_contains '${(q)candidate_helper} navigate cp ${(q)root_payload}' "$cp_picker" \
    "cp picker root binding did not navigate with the precomputed payload"
  assert_contains '${(q)candidate_helper} navigate cp ${(q)home_payload}' "$cp_picker" \
    "cp picker home binding did not navigate with the precomputed payload"
  assert_not_contains '${(q)candidate_helper} navigate cp /' "$cp_picker" \
    "cp picker passed raw root to helper navigate"
  assert_not_contains '${(q)candidate_helper} navigate cp ${(q)HOME}' "$cp_picker" \
    "cp picker passed raw home to helper navigate"
  assert_not_contains 'reload-sync' "$cp_picker" \
    "cp picker bypassed helper navigation mark clearing"
  assert_contains '${(q)candidate_helper} preview cp {3}' "$cp_picker" \
    "cp picker preview did not use encoded helper mode"
  assert_not_contains 'fzf-preview.sh' "$cp_picker" \
    "cp picker passed encoded field three directly to the preview script"
  assert_not_contains ':h}' "$cp_picker" "cp picker action applied a raw path modifier"

  assert_contains 'IFS= read -r key' "$cp_picker" "cp picker did not read the printed Enter key first"
  assert_contains 'while IFS= read -r record; do' "$cp_picker" \
    "cp picker did not collect every accepted record"
  assert_contains '${#record} - ${#tabless} == 2' "$cp_picker" \
    "cp picker did not validate exactly two record tabs"
  assert_contains 'local -A accepted_counts' "$cp_picker" \
    "cp picker did not count accepted full records in an associative map"
  assert_contains 'accepted_counts[$record]' "$cp_picker" \
    "cp picker did not key accepted counts by full record"
  assert_not_contains 'for (( i = 1; i <= accepted_count; ++i ))' "$cp_picker" \
    "cp picker retained candidates-by-selections nested matching"
  assert_contains 'matched_count == accepted_count' "$cp_picker" \
    "cp picker did not require every accepted full record to match"
  assert_contains 'payloads+=("${fields[3]}")' "$cp_picker" \
    "cp picker did not collect every field-three payload"
  assert_contains '$candidate_helper relative0 "$pwd_payload" "${payloads[@]}" >| $selected_file' "$cp_picker" \
    "cp picker did not atomically decode all payloads through relative0"
  assert_contains 'while IFS= read -r -d $'"'"'\0'"'"' selected; do' "$cp_picker" \
    "cp picker did not consume relative0 output with NUL-aware reads"
  assert_contains '(( ${#selected_paths} == ${#payloads} ))' "$cp_picker" \
    "cp picker did not require one decoded path per accepted payload"
  assert_contains 'quoted+=("${(q)selected}")' "$cp_picker" \
    "cp picker did not Zsh-quote every selected path"
  assert_contains 'LBUFFER+="${(j: :)quoted}"' "$cp_picker" \
    "cp picker did not append selections separated by one literal space"

  fzf_call='    fzf '
  without_fzf=${cp_picker//$fzf_call/}
  assert_equal 1 $(( (${#cp_picker} - ${#without_fzf}) / ${#fzf_call} )) \
    "cp picker did not retain exactly one fzf process"

  picker_helper=$picker_home/.config/fzf/fzf-picker-candidates.zsh
  candidate_source=$tmp_dir/cp-candidate-source
  selection_source=$tmp_dir/cp-selection-source
  mkdir -p -- "${picker_helper:h}"
  print -r -- '#!/usr/bin/env zsh' >| "$picker_helper"
  print -r -- 'emulate -L zsh' >> "$picker_helper"
  print -r -- 'case $1 in' >> "$picker_helper"
  print -r -- '  cp)' >> "$picker_helper"
  print -r -- '    while IFS= read -r record; do print -r -- "$record"; done < "$FZF_PICKER_TEST_CANDIDATES"' \
    >> "$picker_helper"
  print -r -- '    ;;' >> "$picker_helper"
  print -r -- '  encode) print -r -- "$2" ;;' >> "$picker_helper"
  print -r -- '  modal)' >> "$picker_helper"
  print -r -- '    print -r -- "$2" >| "$5"' >> "$picker_helper"
  print -r -- '    print -r -- prompt >| "$4"' >> "$picker_helper"
  print -r -- '    ;;' >> "$picker_helper"
  print -r -- '  cursor) ;;' >> "$picker_helper"
  print -r -- '  relative0)' >> "$picker_helper"
  print -r -- '    shift 2' >> "$picker_helper"
  print -r -- '    for payload in "$@"; do print -rn -- "$payload"$'"'"'\0'"'"'; done' >> "$picker_helper"
  print -r -- '    ;;' >> "$picker_helper"
  print -r -- '  *) exit 2 ;;' >> "$picker_helper"
  print -r -- 'esac' >> "$picker_helper"
  chmod +x -- "$picker_helper"

  first_record=$'file\tfirst display\t'${first_path}
  duplicate_record=$'file\tduplicate display\t'${first_path}
  third_record=$'file\tthird display\t'${third_path}
  unknown_record=$'file\tunknown display\t'${first_path}
  {
    print -r -- "$first_record"
    print -r -- "$duplicate_record"
    print -r -- "$third_record"
  } >| "$candidate_source"
  {
    print -r -- "$third_record"
    print -r -- "$first_record"
  } >| "$selection_source"

  eval "$start_delimiter$cp_picker"
  fzf() {
    local record
    while IFS= read -r record; do :; done
    print -r -- enter
    while IFS= read -r record; do print -r -- "$record"; done < "$FZF_PICKER_TEST_SELECTIONS"
  }
  zle() { :; }
  local HOME=$picker_home TMPDIR=$tmp_dir
  local -x FZF_PICKER_TEST_CANDIDATES=$candidate_source FZF_PICKER_TEST_SELECTIONS=$selection_source

  LBUFFER='cp '
  _fzf_cp_complete
  expected="cp ${(q)first_path} ${(q)third_path}"
  assert_equal "$expected" "$LBUFFER" \
    "cp picker did not restore visible candidate order by full record identity"

  {
    print -r -- "$first_record"
    print -r -- "$first_record"
  } >| "$candidate_source"
  {
    print -r -- "$first_record"
    print -r -- "$first_record"
  } >| "$selection_source"
  LBUFFER='cp '
  _fzf_cp_complete
  expected="cp ${(q)first_path} ${(q)first_path}"
  assert_equal "$expected" "$LBUFFER" "cp picker did not preserve duplicate full-record multiplicity"

  print -r -- "$unknown_record" >| "$selection_source"
  LBUFFER='cp '
  _fzf_cp_complete
  assert_equal 'cp ' "$LBUFFER" \
    "cp picker accepted an unknown full record whose payload matched an active candidate"

  unfunction fzf zle _fzf_cp_complete
}

test_zshrc_add_mode_query_bindings() {
  local zshrc cd_picker cp_picker after_start start_delimiter end_delimiter

  zshrc=$(<"$zshrc_script")
  for start_delimiter end_delimiter in \
    '_fzf_cd_navigate() {' 'zle -N _fzf_cd_navigate' \
    '_fzf_cp_complete() {' 'zle -N _fzf_cp_complete'; do
    after_start=${zshrc#*$start_delimiter}
    [[ $after_start == *$end_delimiter* ]] || fail "picker delimiters are missing"
    if [[ $start_delimiter == '_fzf_cd_navigate() {' ]]; then
      cd_picker=${after_start%%$end_delimiter*}
    else
      cp_picker=${after_start%%$end_delimiter*}
    fi
  done

  for picker in "$cd_picker" "$cp_picker"; do
    assert_contains $'--bind "/:transform:\n            if [[ \\$(<${(q)keymap_mode_file}) == add ]]; then\n                print -r -- \'put(/)\'\n            elif [[ \\$(<${(q)keymap_mode_file}) == normal && -n {q} ]]; then' \
      "$picker" "slash binding does not handle Add mode before navigation"
    assert_contains $'--bind "~:transform:\n            if [[ \\$(<${(q)keymap_mode_file}) == add ]]; then\n                print -r -- \'put(~)\'\n            elif [[ \\$(<${(q)keymap_mode_file}) == normal && -n {q} ]]; then' \
      "$picker" "tilde binding does not handle Add mode before navigation"
  done
}

test_zshrc_add_mode_navigation_bindings() {
  local zshrc cd_picker cp_picker after_start start_delimiter end_delimiter picker marker stripped

  zshrc=$(<"$zshrc_script")
  for start_delimiter end_delimiter in \
    '_fzf_cd_navigate() {' 'zle -N _fzf_cd_navigate' \
    '_fzf_cp_complete() {' 'zle -N _fzf_cp_complete'; do
    after_start=${zshrc#*$start_delimiter}
    [[ $after_start == *$end_delimiter* ]] || fail "picker delimiters are missing"
    if [[ $start_delimiter == '_fzf_cd_navigate() {' ]]; then
      cd_picker=${after_start%%$end_delimiter*}
    else
      cp_picker=${after_start%%$end_delimiter*}
    fi
  done

  for picker in "$cd_picker" "$cp_picker"; do
    assert_contains '${(q)candidate_helper} modal insert' "$picker" \
      "picker does not initialize its dynamic keymap"
    assert_contains '${(q)candidate_helper} modal add' "$picker" \
      "picker does not enter Add through the dynamic keymap"
    assert_contains '${(q)candidate_helper} escape ' "$picker" \
      "picker does not leave Add through the dynamic keymap"
    marker='--bind "ctrl-l,tab,right:transform:'
    stripped=${picker//$marker/}
    assert_equal 1 $(( (${#picker} - ${#stripped}) / ${#marker} )) \
      "picker has a navigation binding that bypasses dynamic mode actions"
    marker='--bind "ctrl-h,left:transform:'
    stripped=${picker//$marker/}
    assert_equal 1 $(( (${#picker} - ${#stripped}) / ${#marker} )) \
      "picker has a parent-navigation binding that bypasses dynamic mode actions"
  done

  marker='--bind "shift-tab:transform:'
  stripped=${cd_picker//$marker/}
  assert_equal 1 $(( (${#cd_picker} - ${#stripped}) / ${#marker} )) \
    "cd picker has a source-switching binding that bypasses dynamic mode actions"
  assert_not_contains '--bind "shift-tab:' "$cp_picker" \
    "cp picker unexpectedly binds source switching outside dynamic mode actions"
}

(( $# > 0 )) || set -- codec directory-enumeration cd-merged operations modal create preview zshrc-cd zshrc-cp zshrc-add-mode-query-bindings zshrc-add-mode-navigation-bindings
for suite in "$@"; do
  case $suite in
    codec) test_codec ;;
    directory-enumeration) test_directory_enumeration ;;
    cd-merged) test_cd_merged ;;
    operations) test_operations ;;
    modal) test_modal ;;
    create) test_create ;;
    preview) test_preview ;;
    zshrc-cd) test_zshrc_cd ;;
    zshrc-cp) test_zshrc_cp ;;
    zshrc-add-mode-query-bindings) test_zshrc_add_mode_query_bindings ;;
    zshrc-add-mode-navigation-bindings) test_zshrc_add_mode_navigation_bindings ;;
    *) fail "usage: $0 {codec|directory-enumeration|cd-merged|operations|modal|create|preview|zshrc-cd|zshrc-cp|zshrc-add-mode-query-bindings|zshrc-add-mode-navigation-bindings}..." ;;
  esac
done
print -r -- "PASS: $assertions assertions"
