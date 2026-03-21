#!/bin/sh
set -eu

nix develop .#ci --command stylua --check lua spec
git ls-files '*.lua' | xargs nix develop .#ci --command selene --display-style quiet
nix develop .#ci --command prettier --check .
nix fmt
git diff --exit-code -- '*.nix'
nix develop .#ci --command vimdoc-language-server check doc/
nix develop .#ci --command busted
