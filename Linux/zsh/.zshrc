# ZSH_THEME=...
# plugins=(...)

fpath+=/usr/share/zsh/site-functions
autoload -U compinit && compinit

# Oh My Zsh
source "$ZSH/oh-my-zsh.sh"
source /usr/share/zsh/plugins/zsh-vi-mode/zsh-vi-mode.plugin.zsh

source /usr/share/fzf-tab-completion/zsh/fzf-zsh-completion.sh
# Bind fzf completion after zsh-vi-mode initializes
zvm_after_init() {
  bindkey '^I' fzf_completion
}

# Carapace
export CARAPACE_BRIDGES='zsh,fish,bash,inshellisense' # optional
zstyle ':completion:*' format $'\e[2;37mCompleting %d\e[m'
source <(carapace _carapace)

# Starship and Zoxide
eval "$(starship init zsh)"
eval "$(zoxide init zsh --cmd cd)"

# Aliases
alias ll="eza -la --group-directories-first"
alias ls="eza --group-directories-first"
alias tailbat="tail -f $1| bat --paging=never -l log -"
alias :q="exit"
alias y="yazi"
