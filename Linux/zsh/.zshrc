# ZSH_THEME=...
# plugins=(...)
export PATH="/opt/homebrew/bin:$PATH"
export PATH="/home/linuxbrew/.linuxbrew/bin:$PATH"
export PATH="~/.local/bin:$PATH"
export PATH="$PATH:$(go env GOPATH)/bin"
export FZF_CTRL_R_OPTS="--preview 'echo {}' --preview-window down:3:hidden:wrap --bind '?:toggle-preview'"
export FZF_ALT_C_OPTS="--preview 'eza -la --group-directories-first --color=always {} | head -200'"

fpath+=/usr/share/zsh/site-functions
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

# Bind fzf completion after zsh-vi-mode initializes
zvm_after_init() {
    bindkey '^I' fzf_completion
    bindkey '^P' autosuggest-accept
    source /usr/share/fzf/key-bindings.zsh
}

# Carapace
export CARAPACE_BRIDGES='zsh,fish,bash,inshellisense' # optional
zstyle ':completion:*' format $'\e[2;37mCompleting %d\e[m'
source <(carapace _carapace)

# Transient prompt - must be loaded BEFORE starship
[[ -f /usr/share/zsh/plugins/zsh-transient-prompt/transient-prompt.plugin.zsh ]] && \
    source /usr/share/zsh/plugins/zsh-transient-prompt/transient-prompt.plugin.zsh

# Starship and Zoxide
eval "$(starship init zsh)"
eval "$(zoxide init zsh --cmd cd)"

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

# Scripts
if [[ $- =~ i ]] && [[ -z "$TMUX" ]] && [[ -n "$SSH_TTY" ]]; then
    tmux attach-session -t ssh_tmux || tmux new-session -s ssh_tmux
fi
