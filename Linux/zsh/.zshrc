# Default: hide preview, dynamically show for files/directories
zstyle ':completion:*' fzf-completion-opts \
    --preview-window='right:50%:wrap:hidden' \
    --bind 'focus:transform:val={2}; val=${val//\\/}; val=${val%% }; [[ -e $val || -d $val ]] && echo "change-preview-window(right:50%:wrap:nohidden)" || echo "change-preview-window(hidden)"'

# Command-name completion: show docs
zstyle ':completion:*:complete:-command-:*' fzf-completion-opts \
    --preview='tldr {2} 2>/dev/null || man {2} 2>/dev/null | col -bx | head -80' \
    --preview-window='right:50%:wrap'

fpath+=/usr/share/zsh/site-functions
fpath+=~/.local/share/zsh/completions
fpath+=/usr/share/zsh/plugins/zsh-claudecode-completion
autoload -U compinit && compinit
autoload -U edit-command-line
autoload -U zmv
zle -N edit-command-line
bindkey '\C-x\C-e' edit-command-line
bindkey " " magic-space

# Oh My Zsh
source "$ZSH/oh-my-zsh.sh"
source /usr/share/zsh/plugins/zsh-vi-mode/zsh-vi-mode.plugin.zsh
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.plugin.zsh
source /usr/share/fzf-tab-completion/zsh/fzf-zsh-completion.sh
source /usr/share/fzf/completion.zsh

_fzf_cd_navigate() {
    emulate -L zsh
    local saved=$BUFFER scursor=$CURSOR
    local candidate_helper=$HOME/.config/fzf/fzf-picker-candidates.zsh
    local temp_root=${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}
    local tempdir
    tempdir=$(mktemp -d "$temp_root/fzf-cd-${$}-XXXXXX") || { zle redisplay; return 0; }
    local output_file=$tempdir/output
    local candidates_file=$tempdir/candidates
    local dir_file=$tempdir/dir
    local prompt_file=$tempdir/prompt
    local keymap_mode_file=$tempdir/keymap-mode
    local root_payload home_payload

    $candidate_helper cd "$PWD" >| $candidates_file || {
        rm -f -- $candidates_file
        rmdir -- $tempdir
        zle redisplay
        return 0
    }
    $candidate_helper encode "$PWD" >| $dir_file || {
        rm -f -- $candidates_file $dir_file
        rmdir -- $tempdir
        zle redisplay
        return 0
    }
    root_payload=$($candidate_helper encode /) || {
        rm -f -- $candidates_file $dir_file
        rmdir -- $tempdir
        zle redisplay
        return 0
    }
    home_payload=$($candidate_helper encode "$HOME") || {
        rm -f -- $candidates_file $dir_file
        rmdir -- $tempdir
        zle redisplay
        return 0
    }
    $candidate_helper modal insert "$dir_file" "$prompt_file" "$keymap_mode_file" >/dev/null || {
        rm -f -- $candidates_file $dir_file $prompt_file $keymap_mode_file
        rmdir -- $tempdir
        zle redisplay
        return 0
    }

    fzf --ansi --style=full --layout=reverse --sort --print-query \
        --delimiter=$'\t' --with-nth=2 \
        --multi=1 \
        --prompt "$(<$prompt_file)" \
        --bind "enter:transform:${(q)candidate_helper} enter cd {q} ${(q)dir_file} ${(q)prompt_file} - ${(q)candidates_file} ${(q)keymap_mode_file}" \
        --bind "esc:transform:${(q)candidate_helper} escape cd ${(q)dir_file} ${(q)prompt_file} ${(q)keymap_mode_file}" \
        --bind "i:transform:${(q)candidate_helper} modal insert ${(q)dir_file} ${(q)prompt_file} ${(q)keymap_mode_file}" \
        --bind "a:transform:${(q)candidate_helper} modal add ${(q)dir_file} ${(q)prompt_file} ${(q)keymap_mode_file}" \
        --bind 'j:down,k:up,h:trigger(ctrl-h),l:trigger(tab),q:abort,space:clear-multi+toggle' \
        --bind 'start:unbind(h,j,k,l,i,a,q,space)' \
        --bind "ctrl-l,tab,right:transform:
            target={3}
            [[ -n \$target ]] && ${(q)candidate_helper} navigate cd \"\$target\" ${(q)dir_file} ${(q)prompt_file} - ${(q)candidates_file} ${(q)keymap_mode_file}" \
        --bind "ctrl-h,left:transform:
            target=\$(<${(q)dir_file})
            target=\$(${(q)candidate_helper} parent \"\$target\") || exit 0
            ${(q)candidate_helper} navigate cd \"\$target\" ${(q)dir_file} ${(q)prompt_file} - ${(q)candidates_file} ${(q)keymap_mode_file}" \
        --bind "/:transform:${(q)candidate_helper} slash cd {q} ${(q)root_payload} ${(q)dir_file} ${(q)prompt_file} - ${(q)candidates_file} ${(q)keymap_mode_file}" \
        --bind "~:transform:
            if [[ \$(<${(q)keymap_mode_file}) == add ]]; then
                print -r -- 'put(~)'
            elif [[ \$(<${(q)keymap_mode_file}) == normal && -n {q} ]]; then
                print -r -- ignore
            elif [[ -n {q} ]]; then
                print -r -- 'put(~)'
            else
                ${(q)candidate_helper} navigate cd ${(q)home_payload} ${(q)dir_file} ${(q)prompt_file} - ${(q)candidates_file} ${(q)keymap_mode_file}
            fi" \
        --preview "${(q)candidate_helper} preview cd {3} 2>/dev/null" \
        --preview-window=right:50%:wrap \
        < $candidates_file >| $output_file
    local ret=$?
    $candidate_helper cursor insert
    local ignored_query key record target_payload target decoded_target
    local -a fields
    integer target_count=0
    {
        IFS= read -r ignored_query
        IFS= read -r key
        IFS= read -r record
    } < $output_file
    fields=("${(@ps:\t:)record}")
    (( ${#fields} == 3 )) && target_payload=${fields[3]}
    if [[ $ret -eq 0 && $key == enter && -n $target_payload ]]; then
        while IFS= read -r -d $'\0' decoded_target; do
            (( ++target_count ))
            target=$decoded_target
        done < <($candidate_helper decode0 "$target_payload")
    fi
    rm -f -- $output_file $candidates_file $candidates_file.next $dir_file $prompt_file $keymap_mode_file
    rmdir -- $tempdir
    if [[ $ret -ne 0 || $key != enter || -z $target_payload ]] || (( target_count != 1 )); then
        BUFFER=$saved CURSOR=$scursor
        zle redisplay
        return 0
    fi
    BUFFER="builtin cd -- ${(q)target}"
    zle accept-line
}
zle -N _fzf_cd_navigate

_fzf_cp_complete() {
    emulate -L zsh
    local candidate_helper=$HOME/.config/fzf/fzf-picker-candidates.zsh
    local temp_root=${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}
    local tempdir
    tempdir=$(mktemp -d "$temp_root/fzf-cp-${$}-XXXXXX") || { zle redisplay; return 0; }
    local output_file=$tempdir/output
    local candidates_file=$tempdir/candidates
    local selected_file=$tempdir/selected
    local dir_file=$tempdir/dir
    local prompt_file=$tempdir/prompt
    local keymap_mode_file=$tempdir/keymap-mode
    local pwd_payload root_payload home_payload

    $candidate_helper cp "$PWD" >| $candidates_file || {
        rm -f -- $candidates_file
        rmdir -- $tempdir
        zle redisplay
        return 0
    }
    pwd_payload=$($candidate_helper encode "$PWD") || {
        rm -f -- $candidates_file $dir_file
        rmdir -- $tempdir
        zle redisplay
        return 0
    }
    root_payload=$($candidate_helper encode /) || {
        rm -f -- $candidates_file $dir_file
        rmdir -- $tempdir
        zle redisplay
        return 0
    }
    home_payload=$($candidate_helper encode "$HOME") || {
        rm -f -- $candidates_file $dir_file
        rmdir -- $tempdir
        zle redisplay
        return 0
    }
    print -r -- "$pwd_payload" >| $dir_file
    $candidate_helper modal insert "$dir_file" "$prompt_file" "$keymap_mode_file" >/dev/null || {
        rm -f -- $candidates_file $dir_file $prompt_file $keymap_mode_file
        rmdir -- $tempdir
        zle redisplay
        return 0
    }

    fzf --ansi --style=full --layout=reverse --no-sort \
        --delimiter=$'\t' --with-nth=2 \
        --multi \
        --prompt "$(<$prompt_file)" \
        --bind "enter:transform:${(q)candidate_helper} enter cp {q} ${(q)dir_file} ${(q)prompt_file} - ${(q)candidates_file} ${(q)keymap_mode_file}" \
        --bind "esc:transform:${(q)candidate_helper} escape cp ${(q)dir_file} ${(q)prompt_file} ${(q)keymap_mode_file}" \
        --bind "i:transform:${(q)candidate_helper} modal insert ${(q)dir_file} ${(q)prompt_file} ${(q)keymap_mode_file}" \
        --bind "a:transform:${(q)candidate_helper} modal add ${(q)dir_file} ${(q)prompt_file} ${(q)keymap_mode_file}" \
        --bind 'j:down,k:up,h:trigger(ctrl-h),l:trigger(tab),q:abort,space:toggle' \
        --bind 'start:unbind(h,j,k,l,i,a,q,space)' \
        --bind "ctrl-l,tab,right:transform:
            kind={1}
            target={3}
            [[ \$kind == directory && -n \$target ]] && ${(q)candidate_helper} navigate cp \"\$target\" ${(q)dir_file} ${(q)prompt_file} - ${(q)candidates_file} ${(q)keymap_mode_file}" \
        --bind "ctrl-h,left:transform:
            target=\$(<${(q)dir_file})
            target=\$(${(q)candidate_helper} parent \"\$target\") || exit 0
            ${(q)candidate_helper} navigate cp \"\$target\" ${(q)dir_file} ${(q)prompt_file} - ${(q)candidates_file} ${(q)keymap_mode_file}" \
        --bind "/:transform:${(q)candidate_helper} slash cp {q} ${(q)root_payload} ${(q)dir_file} ${(q)prompt_file} - ${(q)candidates_file} ${(q)keymap_mode_file}" \
        --bind "~:transform:
            if [[ \$(<${(q)keymap_mode_file}) == add ]]; then
                print -r -- 'put(~)'
            elif [[ \$(<${(q)keymap_mode_file}) == normal && -n {q} ]]; then
                print -r -- ignore
            elif [[ -n {q} ]]; then
                print -r -- 'put(~)'
            else
                ${(q)candidate_helper} navigate cp ${(q)home_payload} ${(q)dir_file} ${(q)prompt_file} - ${(q)candidates_file} ${(q)keymap_mode_file}
            fi" \
        --preview "${(q)candidate_helper} preview cp {3} 2>/dev/null" \
        --preview-window=right:50%:wrap \
        < $candidates_file >| $output_file
    local ret=$?
    $candidate_helper cursor insert
    local key record tabless selected
    local -a fields payloads selected_paths quoted
    local -A accepted_counts
    integer records_valid=1 decode_valid=0 accepted_count=0 matched_count=0 count
    {
        IFS= read -r key || records_valid=0
        while IFS= read -r record; do
            tabless=${record//$'\t'/}
            if (( ${#record} - ${#tabless} == 2 )); then
                fields=("${(@ps:\t:)record}")
                if [[ -n ${fields[3]} ]]; then
                    count=${accepted_counts[$record]:-0}
                    accepted_counts[$record]=$(( count + 1 ))
                    (( ++accepted_count ))
                else
                    records_valid=0
                fi
            else
                records_valid=0
            fi
        done
    } < $output_file
    if [[ $ret -eq 0 && $key == enter ]] && (( records_valid && accepted_count > 0 )); then
        while IFS= read -r record; do
            count=${accepted_counts[$record]:-0}
            if (( count > 0 )); then
                fields=("${(@ps:\t:)record}")
                payloads+=("${fields[3]}")
                accepted_counts[$record]=$(( count - 1 ))
                (( ++matched_count ))
            fi
        done < $candidates_file
    fi
    if [[ $ret -eq 0 && $key == enter ]] && \
        (( records_valid && matched_count == accepted_count && ${#payloads} == accepted_count )) && \
        $candidate_helper relative0 "$pwd_payload" "${payloads[@]}" >| $selected_file; then
        while IFS= read -r -d $'\0' selected; do
            selected_paths+=("$selected")
        done < $selected_file
        (( ${#selected_paths} == ${#payloads} )) && decode_valid=1
    fi
    rm -f -- $output_file $candidates_file $candidates_file.next $selected_file $dir_file $prompt_file $keymap_mode_file
    rmdir -- $tempdir
    if (( ! decode_valid )); then
        zle redisplay
        return 0
    fi
    for selected in "${selected_paths[@]}"; do
        quoted+=("${(q)selected}")
    done
    LBUFFER+="${(j: :)quoted}"
    zle redisplay
}
zle -N _fzf_cp_complete

_fzf_tab_complete() {
    emulate -L zsh
    local word marker="__fzf_cp_marker_${$}_${RANDOM}__"
    local input=$LBUFFER$marker
    local -a parsed_words command_words
    parsed_words=( ${(z)input} )
    if [[ -n $RBUFFER || $parsed_words[-1] != $marker ]]; then
        zle fzf_completion
        return
    fi
    parsed_words[-1]=()
    for word in $parsed_words; do
        case $word in
            ';' | '&' | '&&' | '||' | '|' | '|&' | '&!' | '&|') command_words=() ;;
            *) command_words+=($word) ;;
        esac
    done
    if [[ $command_words[1] == cp ]]; then
        zle _fzf_cp_complete
    else
        zle fzf_completion
    fi
}
zle -N _fzf_tab_complete

_cd_space_autopicker() {
    zle magic-space
    if [[ $BUFFER == "cd " && $CURSOR -eq 3 ]]; then
        zle _fzf_cd_navigate
    fi
}
zle -N _cd_space_autopicker

# Bind fzf completion after zsh-vi-mode initializes
zvm_after_init() {
    source /usr/share/fzf/key-bindings.zsh
    bindkey '^I' _fzf_tab_complete
    bindkey ' ' _cd_space_autopicker
    bindkey '^P' autosuggest-accept
    bindkey '^[k' clear-screen
}

# Carapace
zstyle ':completion:*' format $'\e[2;37mCompleting %d\e[m'
source <(carapace _carapace)

# Transient prompt - must be loaded BEFORE starship
[[ -f /usr/share/zsh/plugins/zsh-transient-prompt/transient-prompt.plugin.zsh ]] && \
    source /usr/share/zsh/plugins/zsh-transient-prompt/transient-prompt.plugin.zsh

# Starship and Zoxide
eval "$(starship init zsh)"
[[ -n "$ZSH_VERSION" && $- == *i* ]] && eval "$(zoxide init zsh --cmd cd)"

# Transient prompt config - must be set AFTER starship init
TRANSIENT_PROMPT_PROMPT='$(starship prompt --terminal-width="$COLUMNS" --keymap="${KEYMAP:-}" --status="$STARSHIP_CMD_STATUS" --pipestatus="${STARSHIP_PIPE_STATUS[*]}" --cmd-duration="${STARSHIP_DURATION:-}" --jobs="$STARSHIP_JOBS_COUNT")'
TRANSIENT_PROMPT_RPROMPT='$(starship prompt --right --terminal-width="$COLUMNS" --keymap="${KEYMAP:-}" --status="$STARSHIP_CMD_STATUS" --pipestatus="${STARSHIP_PIPE_STATUS[*]}" --cmd-duration="${STARSHIP_DURATION:-}" --jobs="$STARSHIP_JOBS_COUNT")'
TRANSIENT_PROMPT_TRANSIENT_PROMPT='$(starship module character)'

# Aliases
alias ll="eza -la --group-directories-first"
alias ls="eza --group-directories-first"
alias tailbat="tail -f $1| bat --paging=never -l log -"
alias :q="exit"
alias y="yazi"
alias lg="lazygit"
alias gu="gitui"
alias guw="gitui --watcher"
alias clauded="claude --dangerously-skip-permissions"

# Scripts
if [[ $- =~ i ]] && [[ -z "$TMUX" ]] && [[ -n "$SSH_TTY" ]]; then
    first_session=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | head -1)
    if [[ -n "$first_session" ]]; then
        tmux attach-session -t "$first_session"
    else
        tmux new-session -s ssh_tmux
    fi
fi

# Pull fresh env (WAYLAND_DISPLAY etc.) from tmux session on every prompt so
# long-running panes self-heal after an SSH reconnect with a new waypipe socket.
if [[ -n "$TMUX" ]]; then
    _tmux_refresh_env() { eval "$(tmux show-environment -s 2>/dev/null | grep -v SSH_AUTH_SOCK)" }
    precmd_functions+=(_tmux_refresh_env)
fi

git-https-to-ssh() {
    local remote="${1:-origin}"
    local url=$(git remote get-url "$remote" 2>/dev/null)

    if [[ -z "$url" ]]; then
        echo "Remote '$remote' not found"
        return 1
    fi

    if [[ "$url" =~ ^https://([^/]+)/(.+)$ ]]; then
        local host="${match[1]}"
        local path="${match[2]}"
        local ssh_url="git@${host}:${path}"
        git remote set-url "$remote" "$ssh_url"
        echo "Converted $remote: $url -> $ssh_url"
    else
        echo "URL is not HTTPS format: $url"
        return 1
    fi
}

headless-ssh() {
    export OP_BIOMETRIC_UNLOCK_ENABLED=false
    eval "$(op signin)"
    eval "$(ssh-agent -s)"

    op read "op://Private/Main PC/private key" | ssh-add -

    # Override IdentityAgent from ~/.ssh/config to use the new agent
    export GIT_SSH_COMMAND="ssh -o IdentityAgent=$SSH_AUTH_SOCK"

    if [[ $# -gt 0 ]]; then
        "$@"
    fi
}

# needs to be here or 1password changes it after zshenv
export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR}/ssh-agent.socket"
export PATH="/home/antoinegs/.ocv/bin:$PATH"

# bun completions
[ -s "/tmp/opencode/bun-latest/_bun" ] && source "/tmp/opencode/bun-latest/_bun"
