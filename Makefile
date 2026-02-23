.PHONY: test lint test-hook test-all

test:
	@eval $$(luarocks --lua-version 5.1 path --no-bin) && busted --verbose

lint:
	luacheck lua/ spec/

test-hook:
	bash spec/hook_test.sh

test-all: test test-hook
