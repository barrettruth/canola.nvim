.PHONY: lint fastlint test

lint:
	stylua --check lua spec
	selene --display-style quiet .

fastlint:
	pre-commit run --all-files

test:
	luarocks test --local
