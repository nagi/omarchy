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
jq '.clock |= . + {
  "format": "{:%A, %B %d, %Y (%R)}",
  "on-click": "omarchy-launch-floating-terminal-with-presentation cal -3 `date +%Y`"
} | del(.clock."format-alt")' ~/.config/waybar/config.jsonc > /tmp/output.jsonc && mv /tmp/output.jsonc ~/.config/waybar/config.jsonc
omarchy-restart-waybar

# Gnome settings
echo "tweaking Gnome config..."

# Swap caps lock & escape
if grep -q "compose:caps" ~/.config/hypr/input.conf; then
  echo Swapping caps and escape...
  # overwrite "  kb_options = compose:caps # ,grp:alts_toggle"
  sed -i "s/compose:caps.*/caps:escape, compose:rctrl/" ~/.config/hypr/input.conf
fi

if ! grep -q "Play TADA!" ~/.config/hypr/bindings.conf; then
  exec_tada="$TADA_DIR/target/release/tada --sounds-dir $CLOUD_DIR/assets"
  echo Mapping TADA hotkey...
  echo "bindd = SUPER, PAUSE, Play TADA!, exec, $exec_tada" >> ~/.config/hypr/bindings.conf
  # CONTROL SUPER SHIFT ALT, T used to play TADA too; oror now uses it for the
  # Terminal workspace. SUPER + PAUSE above still plays TADA.
fi

# Run or raise: switch to a named workspace, then raise the app or launch it.
gem list -i thor >/dev/null 2>&1 || gem install thor

# The block below is delimited by markers and rewritten from scratch on every
# run, so re-running after adding, renaming or dropping a binding here converges
# on the same file rather than appending a second copy.
echo "Mapping run-or-raise hotkeys..."
BINDINGS=~/.config/hypr/bindings.conf
# Drop the previous block, then any blank lines it left at the end of the file,
# so the separator added below does not accumulate one blank line per run.
sed '/^# >>> oror bindings >>>$/,/^# <<< oror bindings <<<$/d' "$BINDINGS" |
  awk '{a[NR]=$0} END {while (n<NR && a[NR-n] ~ /^[[:space:]]*$/) n++; for (i=1; i<=NR-n; i++) print a[i]}' >/tmp/bindings.conf
mv /tmp/bindings.conf "$BINDINGS"
printf '\n' >>"$BINDINGS"

# Quoted heredoc: every $(...) below must reach bindings.conf verbatim so it
# is evaluated at press time, not now. That also blocks $OROR_DIR from
# expanding, so it goes in as a placeholder and sed fills it in - which keeps
# the bindings following CLOUD_DIR if the cloud share ever moves.
cat <<"EOF" | sed "s|__OROR_DIR__|$OROR_DIR|g" >>"$BINDINGS"
# >>> oror bindings >>>
# Run or raise (oror). Everything between these markers is regenerated by
# user_tweaks.sh - edit it there, not here.
# Omarchy binds SUPER CTRL ALT itself - the same chord the hyper layer now
# emits unshifted - and two of them collide with the letters below: T was
# "Show time" and W was "Show weather". Both are unbound here; the other four
# (Delete mirror, R reminders, B battery, Z reset zoom) are on free letters and
# still work from hyper.
unbind = SUPER CTRL ALT, T
unbind = SUPER CTRL ALT, W
# -c is derived at press time so these follow `omarchy default terminal|browser`.
# The window class is the desktop id minus its .desktop suffix. Do NOT use the
# entry's StartupWMClass: Chrome declares "Google-chrome" but its actual class
# is "google-chrome", and oror matches exactly.
bindd = CONTROL SUPER ALT, T, Terminal, exec, __OROR_DIR__/bin/oror -q -w "b-Terminal" -c "$(t=$(grep -m1 '\.desktop$' ~/.config/xdg-terminals.list); echo ${t%.desktop})" -e "uwsm-app -- xdg-terminal-exec"
# --profile-directory picks Andrew explicitly, otherwise a second launch shows
# the profile picker, and choosing Andrew there just focuses the window that is
# already open elsewhere instead of making a new one. Chrome-specific: revisit
# if the default browser ever changes away from a Chromium.
bindd = CONTROL SUPER ALT, C, Chrome, exec, __OROR_DIR__/bin/oror -q -w "a-Chrome" -c "$(b=$(xdg-settings get default-web-browser); echo ${b%.desktop})" -e "omarchy-launch-browser --profile-directory=Default --new-window"
# Class is "code" lowercase; code.desktop declares StartupWMClass=Code, which
# never matches. --new-window because a bare `code` just focuses an existing
# window wherever it already is, same as Chrome without a profile argument.
# The workspace name has a space; oror passes it to hyprctl unsplit, but it
# needs quoting here because Hyprland hands this argument to the shell.
bindd = CONTROL SUPER ALT, V, VS Code, exec, __OROR_DIR__/bin/oror -q -w "g-VS Code" -c code -e "uwsm-app -- code --new-window"
# Classes below were read from `hyprctl clients` after launching each app, not
# from the .desktop entry. Emacs is the StartupWMClass trap again: emacsclient
# declares "Emacs" but the pgtk frame's class is lowercase "emacs".
bindd = CONTROL SUPER ALT, F, Files, exec, __OROR_DIR__/bin/oror -q -w "d-Files" -c org.gnome.Nautilus -e "uwsm-app -- nautilus --new-window"
bindd = CONTROL SUPER ALT, E, Emacs, exec, __OROR_DIR__/bin/oror -q -w "c-Emacs" -c emacs -e "uwsm-app -- emacsclient --alternate-editor= --create-frame"
# The webapps' classes are derived from the --app URL by Chrome: "/" becomes
# "_" and "//" becomes "__", so a trailing slash leaves a double underscore
# before -Default. Read them rather than deriving them by hand. Each is served
# by the running Chrome pid, so the exec rule cannot place these windows and
# oror moves them itself after launch.
bindd = CONTROL SUPER ALT, D, Discord, exec, __OROR_DIR__/bin/oror -q -w "e-Discord" -c "chrome-discord.com__channels_@me-Default" -e "omarchy-launch-webapp https://discord.com/channels/@me"
# SUPER SHIFT ALT + G still opens WhatsApp via launch-or-focus-webapp.
bindd = CONTROL SUPER ALT, W, WhatsApp, exec, __OROR_DIR__/bin/oror -q -w "h-WhatsApp" -c "chrome-web.whatsapp.com__-Default" -e "omarchy-launch-webapp https://web.whatsapp.com/"
# A Trello board, on a workspace named for its purpose rather than the app. The
# class embeds the board id, so -c and -e have to be changed together.
bindd = CONTROL SUPER ALT, L, Lists, exec, __OROR_DIR__/bin/oror -q -w "f-Lists" -c "chrome-trello.com__b_YJb2amCk_todo-Default" -e "omarchy-launch-webapp https://trello.com/b/YJb2amCk/todo"

# Adding shift sends the focused window to the same workspace instead of
# raising the app there. This is why the keyd hyper layer is C-M-A and not
# C-M-S-A: shift stays a real modifier, so hyper and hyper+shift are two
# chords rather than one. Following Omarchy's convention, shift moves and
# follows; swap to movetoworkspacesilent to leave focus where it is.
# These name the workspace directly rather than going through oror - moving a
# window needs no class, no launch and no run-or-raise decision. Hyprland takes
# the rest of the line as the argument, so "g-VS Code" needs no quoting here.
bindd = CONTROL SUPER SHIFT ALT, C, Send window to Chrome, movetoworkspace, name:a-Chrome
bindd = CONTROL SUPER SHIFT ALT, T, Send window to Terminal, movetoworkspace, name:b-Terminal
bindd = CONTROL SUPER SHIFT ALT, E, Send window to Emacs, movetoworkspace, name:c-Emacs
bindd = CONTROL SUPER SHIFT ALT, F, Send window to Files, movetoworkspace, name:d-Files
bindd = CONTROL SUPER SHIFT ALT, D, Send window to Discord, movetoworkspace, name:e-Discord
bindd = CONTROL SUPER SHIFT ALT, L, Send window to Lists, movetoworkspace, name:f-Lists
bindd = CONTROL SUPER SHIFT ALT, V, Send window to VS Code, movetoworkspace, name:g-VS Code
bindd = CONTROL SUPER SHIFT ALT, W, Send window to WhatsApp, movetoworkspace, name:h-WhatsApp
# <<< oror bindings <<<
EOF

# Show the named workspaces in Waybar. Without a format-icons entry the
# "default" icon renders them as an empty string; persistent-workspaces keeps
# each button visible while its workspace is empty. Dropping the "active" icon
# stops the focused workspace collapsing to a dot - it keeps its own label.
# Every name needs a format-icons entry and must match the -w value of its
# binding exactly. Only the always-running apps are persistent; the rest behave
# like workspaces 6+, appearing only when focused or holding a window.
# Merging rather than replacing keeps Omarchy's numbered workspaces.
#
# The "a-" ... "h-" prefixes are the button order. Waybar sorts numbered
# workspaces first, then named ones ALPHABETICALLY - the key order in these
# maps is never read, so the prefix is the only lever. format-icons maps each
# prefixed name back to its bare label, so the sort key never reaches the bar.
echo "Adding named workspaces to Waybar..."
jq '."hyprland/workspaces"."format-icons" |= . + {"a-Chrome": "Chrome", "b-Terminal": "Terminal", "c-Emacs": "Emacs", "d-Files": "Files", "e-Discord": "Discord", "f-Lists": "Lists", "g-VS Code": "VS Code", "h-WhatsApp": "WhatsApp"}
  | ."hyprland/workspaces"."persistent-workspaces" |= . + {"a-Chrome": [], "b-Terminal": [], "c-Emacs": [], "d-Files": []}
  | del(."hyprland/workspaces"."format-icons".active)' ~/.config/waybar/config.jsonc > /tmp/output.jsonc && mv /tmp/output.jsonc ~/.config/waybar/config.jsonc

if ! grep -q "workspaces button.active" ~/.config/waybar/style.css; then
  echo "Underlining the active workspace..."
  # The transparent border on every button reserves the space, so nothing
  # shifts when focus moves. GTK3 renders box-shadow here as broken dashes.
  cat <<"EOF" >>~/.config/waybar/style.css

/* Active workspace shows its own label (no dot), marked with an underline. */
#workspaces button {
  border-bottom: 2px solid transparent;
}

#workspaces button.active {
  opacity: 1;
  border-bottom-color: @foreground;
}
EOF
fi

omarchy-restart-waybar

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
