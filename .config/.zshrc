alias cls="clear"
alias gs="git status"
alias oh="cd ~"
alias sdclean="sudo apt autoclean && sudo apt autoremove"
alias ls="eza --oneline --icons --grid --across"
alias els="eza --icons -F -H --group-directories-first --git -1"

alias lzd="lazydocker"
alias venvup="source .venv/bin/activate"
alias dkup="docker compose up -d"

# Bun
alias bx="bunx"
alias brd="bun run dev"
alias brb="bun run build"
alias brri="bun clean && bun i"

# Starship
eval "$(starship init zsh)"

export VOLTA_HOME="$HOME/.volta"
export PATH="$VOLTA_HOME/bin:$PATH"
source ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh

# fnm
FNM_PATH="/home/$USER/.local/share/fnm"
if [ -d "$FNM_PATH" ]; then
  export PATH="$FNM_PATH:$PATH"
  eval "`fnm env`"
fi


# bun completions
[ -s "/home/$USER/.bun/_bun" ] && source "/home/$USER/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
