.PHONY: test lint

test:
	@eval $$(luarocks path --no-bin) && busted --verbose

lint:
	luacheck lua/ spec/
