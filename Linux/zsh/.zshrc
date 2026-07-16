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

_zoxide_tab_or_complete() {
    if [[ -z $BUFFER ]]; then
        local dir
        dir=$(zoxide query --interactive 2>/dev/null) || { zle redisplay; return 0; }
        if [[ -n $dir ]]; then
            zle push-line
            BUFFER="builtin cd -- ${(q)dir}"
            zle accept-line
            zle reset-prompt
        else
            zle redisplay
        fi
    else
        zle fzf_completion
    fi
}
zle -N _zoxide_tab_or_complete

_fzf_cd_navigate() {
    emulate -L zsh
    local saved=$BUFFER scursor=$CURSOR
    local dir=$PWD
    local tempfile=${TMPDIR:-/tmp}/fzf-cd-${$}-${RANDOM}
    while true; do
        {
            fd --base-directory "$dir" --type d --max-depth 1 --hidden \
                --color=always 2>/dev/null | sort
            echo
        } | fzf --ansi --style=full --layout=reverse --print-query \
            --prompt "${dir%/}/ " \
            --expect=ctrl-l,ctrl-h \
            --preview "eza -la --color=always --group-directories-first -- ${(q)dir}/{} 2>/dev/null" \
            --preview-window=right:50%:wrap >$tempfile
        local ret=$?
        if [[ $ret -ne 0 ]]; then
            BUFFER=$saved CURSOR=$scursor
            rm -f $tempfile
            zle redisplay
            return 0
        fi
        local out=$(<$tempfile)
        local -a lines=("${(@f)out}")
        local query=${lines[1]} key=${lines[2]} name=${lines[3]%/}
        case $key in
            ctrl-l)
                [[ -z $name ]] && continue
                dir=$dir/$name
                ;;
            ctrl-h)
                dir=${dir:h}
                ;;
            *)
                local target=$dir
                if [[ -n $query ]]; then
                    if [[ $query == /* ]]; then
                        target=$query
                    else
                        target=$dir/$query
                    fi
                fi
                BUFFER="builtin cd -- ${(q)target}"
                rm -f $tempfile
                zle accept-line
                return 0
                ;;
        esac
    done
}
zle -N _fzf_cd_navigate

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
    bindkey '^I' _zoxide_tab_or_complete
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
