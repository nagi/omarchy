#!/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# Keep only absolute entries on PATH. The .zshrc written further down puts
# "./bin" first, which is handy interactively but poisonous here: run this from
# a checkout that has a bin/ and every command below resolves to that checkout
# instead of the installed system. Running it from ~/Projects/omarchy - the
# obvious place, since that is where this script lives - shadowed every
# `omarchy*` call with the 3.8.5 source tree's copy, so `omarchy restart shell`
# failed with "Unknown Omarchy command" while 3.x commands that no longer exist
# on the system would happily have run.
PATH=$(printf '%s' "$PATH" | tr ':' '\n' | grep '^/' | paste -sd:)
export PATH

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

# oror is Ruby and needs thor. It is not installed onto PATH: the bindings the
# plugin generates call bin/oror in the checkout by a path derived from the
# plugin's own location.
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
-- The run-or-raise bindings that used to live in this block have moved into the
-- oror plugin, along with the workspace-to-monitor rules that used to be a block
-- like this one in monitors.lua. See the plugin section further down this
-- script; the bindings themselves are generated from workspaces.json in the oror
-- checkout.

-- SUPER + PAUSE plays TADA. CONTROL SUPER SHIFT ALT + T used to play it too;
-- oror now uses that chord to send a window to the Terminal workspace.
o.bind("SUPER + PAUSE", "Play TADA!", [[__TADA__ --sounds-dir __ASSETS__]])
EOF
sed -i -e "s|__TADA__|$TADA_DIR/target/release/tada|g" \
       -e "s|__ASSETS__|$CLOUD_DIR/assets|g" "$BINDINGS_BLOCK"
rewrite_lua_block ~/.config/hypr/bindings.lua <"$BINDINGS_BLOCK"
rm -f "$BINDINGS_BLOCK"

# The oror plugin carries the named-workspace bindings, the rules that place
# every workspace on a monitor, and the bar widget that draws them - all three
# generated from one workspaces.json in the oror checkout, so a workspace name
# only ever needs changing in one place.
#
# Omarchy plugins are a Quickshell thing: the shell never reads ~/.config/hypr,
# and the installer never runs plugin code. So the Hyprland half is pulled in by
# one guarded dofile appended to hyprland.lua. That line and the symlink below
# are the only marks this leaves on the stock config - no generated block to go
# stale, and nothing here to rewrite when a workspace is added.
echo "Installing the oror plugin..."
PLUGIN_DIR=~/.config/omarchy/plugins/nagi.oror

# Linked rather than cloned so the checkout stays the one working copy: edits are
# live, and `omarchy plugin remove` only unlinks a link. Validate the checkout
# and never the link - validation walks the folder for symlinks and refuses to
# start on one.
omarchy plugin validate "$OROR_DIR"
ln -sfn "$OROR_DIR" "$PLUGIN_DIR"
[ -d "$PLUGIN_DIR/" ] || { echo "$PLUGIN_DIR is a dangling link."; exit 1; }

# Idempotent by the grep: the block is appended once and then left alone, so an
# edit to it survives a re-run. `omarchy refresh hyprland` would drop it, and
# re-running this script is what puts it back.
HYPRLAND_LUA=~/.config/hypr/hyprland.lua
if ! grep -q "plugins/nagi.oror/hypr/init.lua" "$HYPRLAND_LUA"; then
  cat <<"EOF" >>"$HYPRLAND_LUA"

-- The oror plugin: named-workspace bindings and workspace rules.
--
-- dofile, not require: Omarchy's bootstrap only clears package.loaded for
-- modules named default.hypr.*, hypr.* and omarchy.current.theme.*, so anything
-- required from outside those trees would load once and then go stale on every
-- reload. Guarded both ways, so a missing plugin or a broken file leaves a
-- stock, working Hyprland config behind rather than no config at all.
local oror_init = os.getenv("HOME") .. "/.config/omarchy/plugins/nagi.oror/hypr/init.lua"
local oror_handle = io.open(oror_init, "r")
if oror_handle then
  oror_handle:close()
  local ok, err = pcall(dofile, oror_init)
  if not ok then print("oror plugin config failed: " .. tostring(err)) end
end
EOF
fi

# Put the widget in the bar unless it is already there. This is a read-only
# check: the widget reads workspaces.json itself, so its shell.json entry is
# nothing but an id and no part of this script edits that file.
omarchy-shell shell rescanPlugins >/dev/null
jq -e '[.bar.layout[]?[]?] | any(.id == "nagi.oror")' ~/.config/omarchy/shell.json >/dev/null 2>&1 ||
  omarchy plugin enable nagi.oror --section left --after omarchy.menu

# Lua config errors take down more than a stray line in a .conf file did, so
# fail loudly here rather than leaving a half-configured session behind. This
# covers the plugin too: hyprland.lua dofiles it, so a bad workspaces.json shows
# up as a config error.
hyprctl reload >/dev/null
CONFIG_ERRORS=$(hyprctl configerrors 2>/dev/null | grep -v '^no errors$' || true)
if [ -n "$CONFIG_ERRORS" ]; then
  echo "Hyprland reported config errors:"
  echo "$CONFIG_ERRORS"
  exit 1
fi

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
