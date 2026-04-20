default:
    @just --list

format:
    nix fmt -- --ci
    stylua --check lua spec
    prettier --check .

test:
    busted

lint:
    git ls-files '*.lua' | xargs selene --display-style quiet
    lua-language-server --check . --checklevel=Error
    vimdoc-language-server check doc/

ci: format lint test
    @:
