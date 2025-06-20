# Common
alias oh="cd ~"
alias cls="clear"
alias gs="git status"
alias sdclean="sudo apt autoclean && sudo apt autoremove"
alias ls="eza --oneline --icons --grid --across"
alias els="eza --icons -F -H --group-directories-first --git -1"

# Environment
alias lzd="lazydocker"
alias venvup="source .venv/bin/activate"
alias dkup="docker compose up -d"


# Programming
alias lzd="lazydocker"
alias venvup="source .venv/bin/activate"
alias dkup="docker compose up -d"


# Bun
alias bx="bunx"
alias ba="bun add"
alias bi="bun install"
alias br="bun run"
alias bu="bun update"
alias bre="bun remove"
alias brd="bun run dev"
alias brb="bun run build"
alias bpm="bun pm"
alias brri="bun clean && bun i"
alias bfr="bun format:check && bun lint:fix"


# Docker
alias dcb="docker compose build"
alias dcu="docker compose up -d"
alias dcd="docker compose down"

# Ubuntu
alias install="sudo apt-get install"
alias upgrade="sudo apt-get upgrade"
alias update="sudo apt-get update"
alias remove="sudo apt-get remove"
alias purge="sudo apt-get purge"


# macOS
alias port="lsof -i"
alias stop="kill -9"
alias killport='f(){ kill -9 $(lsof -ti :$1); }; f'


# Project
alias o:next="cd ~/Documents/Next"
alias o:download="cd ~/Downloads"
alias o:work="cd ~/Documents/Work"

# Directory
alias ..='cd ..'
alias ...='cd ../..'

# Starship
eval "$(starship init zsh)"

# bun completions
[ -s "/Users/tinhtute/.bun/_bun" ] && source "/Users/tinhtute/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
autoload -U compinit; compinit
source ~/.zsh/fzf-tab/fzf-tab.plugin.zsh


export PATH="$HOME/.local/bin:$PATH"


