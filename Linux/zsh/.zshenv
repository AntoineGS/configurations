export FZF_DEFAULT_OPTS="--style full --preview='~/.config/fzf/fzf-preview.sh {}'"
export FZF_DEFAULT_COMMAND="fd --type f"
export FZF_CTRL_R_OPTS="--preview 'echo {}' --preview-window down:3:hidden:wrap --bind '?:toggle-preview'"
export FZF_ALT_C_OPTS="--preview 'eza -la --group-directories-first --color=always {} | head -200'"
export ZSH="/usr/share/oh-my-zsh"
export MANPAGER="sh -c 'awk '\''{ gsub(/\x1B\[[0-9;]*m/, \"\", \$0); gsub(/.\x08/, \"\", \$0); print }'\'' | bat -p -lman'"
export EDITOR=nvim
export VISUAL=nvim
export GIT_EDITOR=nvim
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export LG_CONFIG_FILE="$HOME/.config/lazygit/config.yml,$HOME/.local/share/catppuccin/lazygit/themes/mocha/mauve.yml"
export ADZUNA_APP_ID=4bb9d1ce
export ADZUNA_APP_KEY=3801f98eb7fd7d72a8e98db8afd25df9
export PATH="$HOME/.local/share/helpers:$PATH"
export PATH="$HOME/.local/bin:$PATH"
export PATH="/opt/homebrew/bin:$PATH"
export PATH="/home/linuxbrew/.linuxbrew/bin:$PATH"
export PATH="~/.local/bin:$PATH"
export PATH="$PATH:$(go env GOPATH)/bin"
export CARAPACE_BRIDGES='zsh,fish,bash,inshellisense' # optional
export RIPGREP_CONFIG_PATH=~/.ripgreprc

# Load local secrets (not tracked in git)
if [[ -f ~/.zshenv.local ]]; then
    source ~/.zshenv.local
fi
. "$HOME/.cargo/env"
