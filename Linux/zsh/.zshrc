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
zvm_config() {
    ZVM_LINE_INIT_MODE=$ZVM_MODE_INSERT
}
source /usr/share/zsh/plugins/zsh-vi-mode/zsh-vi-mode.plugin.zsh
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.plugin.zsh
source /usr/share/fzf-tab-completion/zsh/fzf-zsh-completion.sh
source /usr/share/fzf/completion.zsh
source "$HOME/.config/shell-picker/shell-picker.plugin.zsh"

# Bind fzf completion after zsh-vi-mode initializes
zvm_after_init() {
    source /usr/share/fzf/key-bindings.zsh
    shell-picker-bind-zsh
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
alias ocv="opencode"
alias clauded="claude --dangerously-skip-permissions"

# Scripts
if [[ $- =~ i ]] && [[ -n "$SSH_TTY" ]] && [[ -z "$HERDR_ENV" ]]; then
    herdr-waypipe-env publish 2>/dev/null || true
    herdr
fi

# Pull fresh Waypipe variables into existing Herdr panes after an SSH reconnect.
if [[ "${HERDR_ENV:-}" == 1 ]]; then
    _herdr_refresh_waypipe_env() {
        local snapshot line name value read_status
        local wayland_display xdg_runtime_dir display
        local -i record=0 valid=1
        local -i seen_wayland_display=0 seen_xdg_runtime_dir=0 seen_display=0

        snapshot=$(
            herdr-waypipe-env read 2>/dev/null
            read_status=$?
            printf x
            exit "$read_status"
        ) || return
        snapshot=${snapshot%x}

        while IFS= read -r line; do
            (( record++ ))
            if [[ "$line" != *=* ]]; then
                valid=0
                break
            fi

            name=${line%%=*}
            value=${line#*=}

            case "$name" in
                WAYLAND_DISPLAY)
                    if (( record != 1 || seen_wayland_display )) || [[ -z "$value" ]]; then
                        valid=0
                        break
                    fi
                    wayland_display=$value
                    seen_wayland_display=1
                    ;;
                XDG_RUNTIME_DIR)
                    if (( record != 2 || seen_xdg_runtime_dir )) || [[ -z "$value" ]]; then
                        valid=0
                        break
                    fi
                    xdg_runtime_dir=$value
                    seen_xdg_runtime_dir=1
                    ;;
                DISPLAY)
                    if (( record != 3 || seen_display )); then
                        valid=0
                        break
                    fi
                    display=$value
                    seen_display=1
                    ;;
                *)
                    valid=0
                    break
                    ;;
            esac
        done < <(printf %s "$snapshot")

        if (( ! valid || record != 3 || ! seen_wayland_display || ! seen_xdg_runtime_dir || ! seen_display )); then
            return 1
        fi

        export WAYLAND_DISPLAY="$wayland_display"
        export XDG_RUNTIME_DIR="$xdg_runtime_dir"
        if [[ -n "$display" ]]; then
            export DISPLAY="$display"
        else
            unset DISPLAY
        fi
    }
    precmd_functions+=(_herdr_refresh_waypipe_env)
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

eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv zsh)"
