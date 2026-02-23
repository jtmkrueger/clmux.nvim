.PHONY: test lint test-hook test-all

test:
	@eval $$(luarocks path --no-bin) && busted --verbose

lint:
	luacheck lua/ spec/

test-hook:
	bash spec/hook_test.sh

test-all: test test-hook
