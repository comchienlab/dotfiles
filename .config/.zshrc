# Common
alias oh="cd ~"
alias cls="clear"
alias gs="git status"
alias sdclean="sudo apt autoclean && sudo apt autoremove"
alias ls="eza --oneline --icons --grid --across"
alias els="eza --icons -F -H --group-directories-first --git -1"
alias ll="eza -la -G -w 200"


# Environments
alias lzd="lazydocker"
alias venvup="source .venv/bin/activate"
alias dkup="docker compose up -d"


# Directory
alias ..="cd .."
alias ...="cd ../.."


# Git
alias gcl="git clone"


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
alias bxclean="bun pm cache rm && rm -rf node_modules dist build .next .turbo .nuxt coverage && rm -f bun.lockb"


# Docker
alias dcb="docker compose build"
alias dcu="docker compose up -d"
alias dcd="docker compose down"


# macOS
alias port="lsof -i"
alias stop="kill -9"
alias killport='f(){ kill -9 $(lsof -ti :$1); }; f'


# Project
alias o:next="cd ~/Documents/Next"
alias o:download="cd ~/Downloads"
alias o:work="cd ~/Work"


# Starship
#eval "$(starship init zsh)"

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

export PATH="/opt/homebrew/bin:$PATH"
eval "$(starship init zsh)"

#THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"

# Task Master aliases added on 6/26/2025
alias tm='task-master'
alias taskmaster='task-master'

# Claude code
alias fclaude="claude --dangerously-skip-permissions"

# 🔑 Set Gemini API Key
gemini_key() {
    if [ -z "$1" ]; then
        echo "❌ Usage: gemini_key <your_api_key>"
        return 1
    fi

    export GEMINI_API_KEY="$1"
    echo "✅ GEMINI_API_KEY set successfully!"
}

# fnm
FNM_PATH="/opt/homebrew/opt/fnm/bin"
if [ -d "$FNM_PATH" ]; then
  eval "`fnm env`"
fi


claude_execute() {
  emulate -L zsh
  setopt NO_GLOB
  local query="$*"
  local prompt="You are a command line expert. The user wants to run a command but they don't know how. Here is what they asked: ${query}. Return ONLY the exact shell command needed. Do not prepend with an explanation, no markdown, no code blocks - just return the raw command you think will solve their query."
  local cmd

  cmd=$(claude --dangerously-skip-permissions --disallowedTools "Bash(*)" --model default -p "$prompt" --output-format text | tr -d '\000-\037' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  if [[ -z "$cmd" ]]; then
    echo "claude_execute: No command found"
    return 1
  fi

  echo -e "$ \033[0;36m$cmd\033[0m"
  echo -n "Press Enter to execute, or Ctrl+C to cancel..."
  read
  eval "$cmd"
}
alias ce="noglob claude_execute"

source ~/.zshfn

# Added by Antigravity
export PATH="/Users/tinhtute/.antigravity/antigravity/bin:$PATH"
