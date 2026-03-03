export FZF_DEFAULT_OPTS="--style full --preview='~/.config/fzf/fzf-preview.sh {}'"
export FZF_DEFAULT_COMMAND="fd --type f"
export ZSH="/usr/share/oh-my-zsh"
export MANPAGER="sh -c 'awk '\''{ gsub(/\x1B\[[0-9;]*m/, \"\", \$0); gsub(/.\x08/, \"\", \$0); print }'\'' | bat -p -lman'"
export PATH="$HOME/.local/bin:$PATH"
export EDITOR=nvim
export VISUAL=nvim
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export LG_CONFIG_FILE="$HOME/.config/lazygit/config.yml,$HOME/.local/share/catppuccin/lazygit/themes/mocha/mauve.yml"

# Load local secrets (not tracked in git)
if [[ -f ~/.zshenv.local ]]; then
  source ~/.zshenv.local
fi
export RIPGREP_CONFIG_PATH=~/.ripgreprc
