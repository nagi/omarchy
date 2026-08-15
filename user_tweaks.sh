#!/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# AI tools
if ! command -v npm >/dev/null; then
  echo "Install Omarchy's Javascript dev tools first"
  exit 1
fi
npm install -g @google/gemini-cli
npm install -g @anthropic-ai/claude-code

# Set locale
echo Checking locale ...
grep -q en_US.UTF-8 <(locale) && echo Setting locale... && sudo localectl set-locale LANG=en_GB.UTF-8

# Non-deterministic dotfiles first
echo "checking for cloud share..."
CLOUD_DIR=~/Dropbox/Linux
DOTFILES_DIR=$CLOUD_DIR/dotfiles
ENVIRONMENT_FILE=$CLOUD_DIR/secrets/environment
OROR_DIR=$CLOUD_DIR/omarchy-run-or-raise
TADA_DIR=$CLOUD_DIR/tada

if [ ! -d $CLOUD_DIR ]; then
  echo "$CLOUD_DIR should exist. Is Dropbox installed and synced?"
  exit 1
fi

# Projects that live in the cloud share and get wired into hotkeys further down.
# Missing means the cloud share is incomplete, which is a real problem worth
# stopping for - this script either fails loudly or runs to "Done!". Present is
# taken to mean built and working; no binaries are probed.
for project in "$OROR_DIR" "$TADA_DIR"; do
  if [ ! -d "$project" ]; then
    echo "$project is missing. Clone and build it, then re-run this script."
    exit 1
  fi
done

echo "checking for non-deterministic dotfiles..."
if [ ! -d $DOTFILES_DIR ]; then
  echo "$DOTFILES_DIR should exist."
  exit 1
else
  echo "symlinking dotfiles..."
  DOTFILES=$(ls -A "$DOTFILES_DIR")
  for f in $DOTFILES; do
    [ ! -d "$HOME/$f" ] && ln -sf "$DOTFILES_DIR/$f" "$HOME/.$f"
  done
fi

# For wireguard VPN
echo "Installing wireguard ..."
command -v wg >/dev/null || sudo pacman -S --noconfirm --needed wireguard-tools
sudo pacman -S --noconfirm --needed systemd-resolvconf

# Various bits and pieces
echo "Installing console apps..."
sudo pacman -S --noconfirm --needed \
  alsa-utils \
  doctl aws-cli \
  dog ldns \
  dos2unix \
  fd \
  htop \
  psmisc \
  the_silver_searcher \
  tk \
  tree \
  usbutils \
  wev \

command -v ack >/dev/null || yay -S --noconfirm ack
command -v ccrypt >/dev/null || yay -S --noconfirm ccrypt
command -v trash >/dev/null || yay -S --noconfirm trash-d
command -v heroku >/dev/null || yay -S --noconfirm trash-d heroku-cli

# Console toys
echo "Installing console toys..."
sudo pacman -S --noconfirm --needed cowsay toilet figlet lolcat
command -v boxes >/dev/null || yay -S --noconfirm boxes

# GUI apps
echo "Installing GUI apps..."
sudo pacman -S --noconfirm --needed emacs-wayland gimp inkscape dconf-editor

# Daemons
echo "Installing daemons..."
if ! pgrep -x keyd$ > /dev/null; then
  sudo pacman -S --noconfirm --needed keyd
  sudo systemctl enable --now keyd
fi

# Configuring keyboard
cat <<EOF | sudo tee /etc/keyd/default.conf > /dev/null
[ids]
*

[main]
rightalt = layer(hyper_mod)

# This layer is active when the assigned key (rightalt in this case) is held.
# The 'C-M-A' makes all other keys pressed simultaneously act as if
# Control+Meta(Super)+Alt are held down along with the other key. Shift is
# deliberately NOT in the layer: that leaves it free as a real modifier, so
# hyper+key and hyper+shift+key are two distinct chords. The oror bindings
# further down use that - unshifted raises, shifted sends the window.
[hyper_mod:C-M-A]
# Type my email address. The mapping is on the physical "2" key; the macro
# spells "@" itself, so it does not depend on shift being held.
2 = macro(1ms a 1ms n 1ms d 1ms r 1ms e 1ms w 1ms . 1ms n 1ms a 1ms g 1ms i 1ms @ 1ms g 1ms m 1ms a 1ms i 1ms l 1ms . 1ms c 1ms o 1ms m)
EOF

echo "Installing console apps..."
sudo pacman -S --noconfirm --needed alsa-utils dog dos2unix fd htop the_silver_searcher tk wev usbutils
command -v ack >/dev/null || yay -S --noconfirm ack
command -v ccrypt >/dev/null || yay -S --noconfirm ccrypt

# Console toys
echo "Installing console toys..."
sudo pacman -S --noconfirm --needed cowsay toilet figlet lolcat
command -v ack >/dev/null || yay -S --noconfirm boxes

# GUI apps
echo "Installing GUI apps..."
sudo pacman -S --noconfirm --needed emacs-wayland gimp inkscape dconf-editor

# My clock settings
echo "Setting the clock format..."
SHELL_JSON=~/.config/omarchy/shell.json
# Quattro's bar is Quickshell, not Waybar. The clock is a widget configured in
# shell.json, its tokens are Qt's ("dddd", not "%A"), and it has no on-click:
# left click opens a calendar panel and right click cycles the formats below.
# Written with jq rather than `omarchy bar set` because that command splits its
# value on commas before it reaches the shell (4.0.0.alpha).
jq --arg format "dddd, MMMM d, yyyy (HH:mm)" --arg format_alt "d MMMM 'W'ww yyyy" \
  '.bar.layout |= with_entries(.value |= map(
     if .id == "omarchy.clock" then . + { format: $format, formatAlt: $format_alt } else . end))' \
  "$SHELL_JSON" >/tmp/shell.json && mv /tmp/shell.json "$SHELL_JSON"

# Hyprland config
echo "tweaking Hyprland config..."

# Quattro moved Hyprland's config from ~/.config/hypr/*.conf to *.lua. The .conf
# files survive the upgrade on disk but nothing reads them any more, so
# everything below writes Lua.
#
# Each block is delimited by markers and rewritten from scratch on every run, so
# re-running after adding, renaming or dropping something converges on the same
# file rather than appending a second copy. The block body is read from stdin.
rewrite_lua_block() {
  local file="$1" tmp
  tmp=$(mktemp)
  # Drop the previous block, then any blank lines it left at the end of the
  # file, so the separator added below does not accumulate one per run.
  sed '/^-- >>> user_tweaks >>>$/,/^-- <<< user_tweaks <<<$/d' "$file" |
    awk '{a[NR]=$0} END {while (n<NR && a[NR-n] ~ /^[[:space:]]*$/) n++; for (i=1; i<=NR-n; i++) print a[i]}' >"$tmp"
  {
    printf '\n-- >>> user_tweaks >>>\n'
    cat
    printf -- '-- <<< user_tweaks <<<\n'
  } >>"$tmp"
  mv "$tmp" "$file"
}

# Swap caps lock & escape
echo "Swapping caps and escape..."
rewrite_lua_block ~/.config/hypr/input.lua <<"EOF"
-- Regenerated by user_tweaks.sh - edit it there, not here.
-- Omarchy's default is "compose:caps,shift:both_capslock_cancel", which parks
-- compose on caps lock. Move compose to right ctrl so caps can go back to
-- being escape. A partial hl.config() only overrides the keys it names.
hl.config({
  input = {
    kb_layout = "us",
    kb_options = "caps:escape,compose:rctrl",
    repeat_delay = 600,
  },
})
EOF

# Run or raise: switch to a named workspace, then raise the app or launch it.
gem list -i thor >/dev/null 2>&1 || gem install thor

echo "Mapping hotkeys..."
# Quoted heredoc: every $(...) below must reach bindings.lua verbatim so it is
# evaluated at press time, not now. That also blocks the cloud-share paths from
# expanding, so they go in as placeholders and sed fills them in - which keeps
# the bindings following CLOUD_DIR if the cloud share ever moves.
BINDINGS_BLOCK=$(mktemp)
cat <<"EOF" >"$BINDINGS_BLOCK"
-- Regenerated by user_tweaks.sh - edit it there, not here.
--
-- Commands below are Lua long-bracket strings ([[...]]), which pass their shell
-- quoting through untouched. Hyprland runs them through a shell, so every
-- $(...) is still evaluated at press time.

-- SUPER + PAUSE plays TADA. CONTROL SUPER SHIFT ALT + T used to play it too;
-- oror now uses that chord to send a window to the Terminal workspace.
o.bind("SUPER + PAUSE", "Play TADA!", [[__TADA__ --sounds-dir __ASSETS__]])

-- Run or raise (oror): switch to a named workspace, then raise the app there or
-- launch it.
--
-- Omarchy binds SUPER + CTRL + ALT itself - the same chord the keyd hyper layer
-- emits unshifted - and three of them collide with the letters below: T is
-- "Show time", W is "Toggle weather", and D is "Calendar", which is new in
-- Quattro. All three are unbound here; the rest of that chord (Delete
-- mirroring, R reminders, B battery, Z reset zoom) is on free letters and still
-- works from hyper.
hl.unbind("SUPER + CTRL + ALT + T")
hl.unbind("SUPER + CTRL + ALT + W")
hl.unbind("SUPER + CTRL + ALT + D")

-- The workspace names are the bar labels. Waybar sorted named workspaces
-- alphabetically, which is why these used to carry "a-" ... "h-" sort prefixes;
-- the cloned workspaces widget takes its order from shell.json instead, so the
-- prefixes are gone. Each -w value must still match a name in that widget's
-- config further down this script.

-- -c is derived at press time so these follow `omarchy default terminal|browser`.
-- The window class is the desktop id minus its .desktop suffix. Do NOT use the
-- entry's StartupWMClass: Chrome declares "Google-chrome" but its actual class
-- is "google-chrome", and oror matches exactly.
--
-- Quattro no longer keeps ~/.config/xdg-terminals.list unless a terminal has
-- been picked explicitly, so ask xdg-terminal-exec for the id rather than
-- reading that file. --print-id can append a ":reason" suffix, hence the %%:*.
o.bind("CONTROL + SUPER + ALT + T", "Terminal",
  [[__OROR__ -q -w "Terminal" -c "$(t=$(xdg-terminal-exec --print-id); t=${t%%:*}; echo ${t%.desktop})" -e "uwsm-app -- xdg-terminal-exec"]])
-- --profile-directory picks the profile explicitly, otherwise a second launch
-- shows the profile picker, and choosing there just focuses the window that is
-- already open elsewhere instead of making a new one. Chromium-specific, and
-- the default browser is chromium here rather than Chrome; revisit if it ever
-- changes away from a Chromium.
o.bind("CONTROL + SUPER + ALT + C", "Chrome",
  [[__OROR__ -q -w "Chrome" -c "$(b=$(xdg-settings get default-web-browser); echo ${b%.desktop})" -e "omarchy-launch-browser --profile-directory=Default --new-window"]])
-- Class is "code" lowercase; code.desktop declares StartupWMClass=Code, which
-- never matches. --new-window because a bare `code` just focuses an existing
-- window wherever it already is, same as Chrome without a profile argument.
o.bind("CONTROL + SUPER + ALT + V", "VS Code",
  [[__OROR__ -q -w "VS Code" -c code -e "uwsm-app -- code --new-window"]])
-- Classes below were read from `hyprctl clients` after launching each app, not
-- from the .desktop entry. Emacs is the StartupWMClass trap again: emacsclient
-- declares "Emacs" but the pgtk frame's class is lowercase "emacs".
o.bind("CONTROL + SUPER + ALT + F", "Files",
  [[__OROR__ -q -w "Files" -c org.gnome.Nautilus -e "uwsm-app -- nautilus --new-window"]])
o.bind("CONTROL + SUPER + ALT + E", "Emacs",
  [[__OROR__ -q -w "Emacs" -c emacs -e "uwsm-app -- emacsclient --alternate-editor= --create-frame"]])
-- The webapps' classes are derived from the --app URL by the browser: "/"
-- becomes "_" and "//" becomes "__", so a trailing slash leaves a double
-- underscore before -Default. The "chrome-" prefix is the same under Chromium
-- as under Chrome. Read them rather than deriving them by hand. Each is served
-- by the running browser pid, so the exec rule cannot place these windows and
-- oror moves them itself after launch.
o.bind("CONTROL + SUPER + ALT + D", "Discord",
  [[__OROR__ -q -w "Discord" -c "chrome-discord.com__channels_@me-Default" -e "omarchy-launch-webapp https://discord.com/channels/@me"]])
-- SUPER SHIFT ALT + G still opens WhatsApp via omarchy-launch-or-focus-webapp.
o.bind("CONTROL + SUPER + ALT + W", "WhatsApp",
  [[__OROR__ -q -w "WhatsApp" -c "chrome-web.whatsapp.com__-Default" -e "omarchy-launch-webapp https://web.whatsapp.com/"]])
-- A Trello board, on a workspace named for its purpose rather than the app. The
-- class embeds the board id, so -c and -e have to be changed together.
o.bind("CONTROL + SUPER + ALT + L", "Lists",
  [[__OROR__ -q -w "Lists" -c "chrome-trello.com__b_YJb2amCk_todo-Default" -e "omarchy-launch-webapp https://trello.com/b/YJb2amCk/todo"]])

-- Adding shift sends the focused window to the same workspace instead of
-- raising the app there. This is why the keyd hyper layer is C-M-A and not
-- C-M-S-A: shift stays a real modifier, so hyper and hyper+shift are two chords
-- rather than one. Following Omarchy's convention, shift moves and follows; add
-- follow = false to leave focus where it is.
-- These name the workspace directly rather than going through oror - moving a
-- window needs no class, no launch and no run-or-raise decision.
o.bind("CONTROL + SUPER + SHIFT + ALT + C", "Send window to Chrome", hl.dsp.window.move({ workspace = "name:Chrome" }))
o.bind("CONTROL + SUPER + SHIFT + ALT + T", "Send window to Terminal", hl.dsp.window.move({ workspace = "name:Terminal" }))
o.bind("CONTROL + SUPER + SHIFT + ALT + E", "Send window to Emacs", hl.dsp.window.move({ workspace = "name:Emacs" }))
o.bind("CONTROL + SUPER + SHIFT + ALT + F", "Send window to Files", hl.dsp.window.move({ workspace = "name:Files" }))
o.bind("CONTROL + SUPER + SHIFT + ALT + D", "Send window to Discord", hl.dsp.window.move({ workspace = "name:Discord" }))
o.bind("CONTROL + SUPER + SHIFT + ALT + L", "Send window to Lists", hl.dsp.window.move({ workspace = "name:Lists" }))
o.bind("CONTROL + SUPER + SHIFT + ALT + V", "Send window to VS Code", hl.dsp.window.move({ workspace = "name:VS Code" }))
o.bind("CONTROL + SUPER + SHIFT + ALT + W", "Send window to WhatsApp", hl.dsp.window.move({ workspace = "name:WhatsApp" }))
EOF
sed -i -e "s|__OROR__|$OROR_DIR/bin/oror|g" \
       -e "s|__TADA__|$TADA_DIR/target/release/tada|g" \
       -e "s|__ASSETS__|$CLOUD_DIR/assets|g" "$BINDINGS_BLOCK"
rewrite_lua_block ~/.config/hypr/bindings.lua <"$BINDINGS_BLOCK"
rm -f "$BINDINGS_BLOCK"

# Lua config errors take down more than a stray line in a .conf file did, so
# fail loudly here rather than leaving a half-configured session behind.
hyprctl reload >/dev/null
CONFIG_ERRORS=$(hyprctl configerrors 2>/dev/null | grep -v '^no errors$' || true)
if [ -n "$CONFIG_ERRORS" ]; then
  echo "Hyprland reported config errors:"
  echo "$CONFIG_ERRORS"
  exit 1
fi

# Show the named workspaces in the bar. Quattro's stock omarchy.workspaces
# widget only ever draws workspaces 1-10, labelled with their number, and has no
# equivalent of Waybar's format-icons or persistent-workspaces. So clone it once
# and give the clone a QML that draws named workspaces too. The clone also
# switches the bar over to it, and survives `omarchy update`.
echo "Adding named workspaces to the bar..."
WORKSPACES_PLUGIN=~/.config/omarchy/plugins/${USER}.workspaces
if [ ! -d "$WORKSPACES_PLUGIN" ]; then
  echo "Cloning the workspaces widget..."
  omarchy plugin clone omarchy.workspaces
fi

# The widget QML lives in the oror project rather than inline here: it belongs
# with the bindings it labels, and keeping one copy means the two cannot drift.
WORKSPACES_QML=$OROR_DIR/shell/Workspaces.qml
if [ ! -f "$WORKSPACES_QML" ]; then
  echo "$WORKSPACES_QML is missing. Update the oror checkout, then re-run this script."
  exit 1
fi
cp "$WORKSPACES_QML" "$WORKSPACES_PLUGIN/Workspaces.qml"

# Array order is the button order, and every name must match the -w value of its
# binding exactly. Only the always-running apps are persistent; the rest behave
# like workspaces 6-10, appearing only when they hold a window.
jq --arg id "${USER}.workspaces" --argjson named '[
      { "name": "Chrome",   "persistent": true },
      { "name": "Terminal", "persistent": true },
      { "name": "Emacs",    "persistent": true },
      { "name": "Files",    "persistent": true },
      { "name": "Discord" },
      { "name": "Lists" },
      { "name": "VS Code" },
      { "name": "WhatsApp" }
    ]' \
  '.bar.layout |= with_entries(.value |= map(
     if .id == $id then .named = $named else . end))' \
  "$SHELL_JSON" >/tmp/shell.json && mv /tmp/shell.json "$SHELL_JSON"

omarchy restart shell

# Spacemacs
if [ -d ~/.emacs.d/.git ]; then
  echo "Spacemacs is installed."
else
  echo "installing Spacemacs..."
  sudo pacman -S --noconfirm --needed adobe-source-code-pro-fonts
  git clone https://github.com/syl20bnr/spacemacs ~/.emacs.d
fi

# zsh
if command -v zsh &>/dev/null; then
  echo "Zsh is installed."
else
  echo "Installing zsh and Oh My Zsh..."
  sudo pacman -S --noconfirm --needed zsh
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  sudo chsh -s /usr/bin/zsh
  # TODO
  # launcher=~/.local/share/omarchy/bin/omarchy-launch-floating-terminal-with-presentation
  # sed -i "s/e bash/e zsh/" $launcher
fi
echo "Writing dotfiles..."

cat <<"EOF" >~/.zshrc
export ZSH="$HOME/.oh-my-zsh"
export OMAKUB_PATH="$HOME/.local/share/omakub"
export PATH="./bin:$HOME/.local/bin:$OMAKUB_PATH/bin:$PATH"

export EDITOR="nvim"
export SUDO_EDITOR="$EDITOR"

ZSH_THEME="robbyrussell"

plugins=(
  bundler
  command-not-found
  fzf
  git
  ssh
  ssh-agent
  vi-mode
  zsh-interactive-cd
)

zstyle :omz:update mode auto           # Autom update...
zstyle :omz:update frequency 13        # ... in days.
zstyle :omz:plugins:ssh-agent lazy yes # Prompt lazily

source $ZSH/oh-my-zsh.sh

alias cds="cd $HOME/Projects/SchooLLM"
alias cdf="cd $HOME/Projects/NAGI.MEAT.APP/fizzy"
alias cdd="cd $HOME/Projects/NAGI.MEAT.APP/discipline_game/"

alias d='docker'
alias r='rails'
alias bat='batcat'
alias lzg='lazygit'
alias lzd='lazydocker'

alias vim=nvim;
alias view="nvim -R";
alias vimdiff="nvim -d";

alias rm=trash

alias caly="cal $(date +%Y)"

alias ll='eza -lh --icons --group-directories-first'
alias lla='ll -a'
alias llt='ll --sort modified --reverse'
alias lltree='eza --tree --level=5 --long --icons --git'

alias httpss="python3 -m http.server 8000"
alias servers="ss -ltnp"

if command -v mise &> /dev/null; then
  eval "$(mise activate zsh)"
fi

EOF

echo $CLOUD_DIR/quotes/meditation >>~/.zshrc
echo "source $ENVIRONMENT_FILE" >>~/.zshrc

cat <<"EOF" >~/.inputrc
set editing-mode vi
set keymap vi
set bell-style visible
EOF

cat <<"EOF" >~/.ackrc
--type-set=haml=.haml
--type-set=js=.coffee,.hbs
--type-set=sass=.sass,.scss
--type-set=slim=.slim

--ignore-dir=.idea
--ignore-dir=.sass-cache
--ignore-dir=.shadow-cljs
--ignore-dir=coverage
--ignore-dir=dragonfly
--ignore-dir=javascripts/lib
--ignore-dir=lexdata
--ignore-dir=log
--ignore-dir=node_modules/
--ignore-dir=patched-gems
--ignore-dir=public/system
--ignore-dir=tmp
--ignore-dir=vendor

--ignore-file=ext:bak
--ignore-file=ext:pdf
--ignore-file=is:tags

--ignore-file=match:.eslintcache
--ignore-file=match:.gitignore
--ignore-file=match:.powrc
--ignore-file=match:.rbenv-version
--ignore-file=match:.rspec
--ignore-file=match:.rvmrc
--ignore-file=match:/[._].*\.swp$/
--ignore-file=match:jquery-ui.js
--ignore-file=match:jquery.js
EOF

# .gitconfig
cat <<EOF >~/.gitconfig
[user]
	name = Andrew Nagi
	email = andrew.nagi@gmail.com
[alias]
	aa = add --all
	amend = ci --amend
	b = branch
	ba = branch -a
	ci = commit -v
	co = checkout
	dc = diff --cached
	di = diff
	me = "!git log --pretty=format:\"%h%x09%an%x09%ad%x09%s\" | grep -i nagi | less"
	la = !git l --all
	pom = push origin master
	phm = push heroku master
	r = remote
	rv = remote -v
	rm="!git ls-files --deleted | xargs git rm"
	st = status
[color]
	ui = true
[core]
	editor = nvim
	autocrlf = input
	excludesfile = ~/.gitignore_global
[merge]
	tool = "nvim -d"
[init]
	defaultBranch = master
EOF

# .gitignore_global
cat <<EOF >~/.gitignore_global
# My Stuff

.aider

# https://github.com/github/gitignore

# MacOS
#######

*.DS_Store
.AppleDouble
.LSOverride

# Icon must end with two \r
Icon

# Thumbnails
._*

# Files that might appear in the root of a volume
.DocumentRevisions-V100
.fseventsd
.Spotlight-V100
.TemporaryItems
.Trashes
.VolumeIcon.icns
.com.apple.timemachine.donotpresent

# Directories potentially created on remote AFP share
.AppleDB
.AppleDesktop
Network Trash Folder
Temporary Items
.apdisk

# Emacs
#######

# -*- mode: gitignore; -*-
*~
\#*\#
/.emacs.desktop
/.emacs.desktop.lock
*.elc
auto-save-list
tramp
.\#*

# Org-mode
.org-id-locations
*_archive

# flymake-mode
*_flymake.*

# eshell files
/eshell/history
/eshell/lastdir

# elpa packages
/elpa/

# reftex files
*.rel

# AUCTeX auto folder
/auto/

# cask packages
.cask/
dist/

# Flycheck
flycheck_*.el

# projectiles files
.projectile

# directory configuration
.dir-locals.el
Contact GitHub API Training Shop Blog About

# VIM
#####

# swap
[._]*.s[a-v][a-z]
[._]*.sw[a-p]
[._]s[a-v][a-z]
[._]sw[a-p]
# session
Session.vim
# temporary
.netrwhist
*~
# auto-generated tag files
tags
EOF

echo Done!
exit 0
