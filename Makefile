.PHONY: test

all:upgrade clean compile

upgrade:
	rebar3 upgrade

clean:
	rebar3 clean --all

compile:
	rebar3 compile

rel:clean compile
	rebar3 release

devrel:clean compile
	rm -f priv/configs/env.config
	ln -s dev.config priv/configs/env.config
	./dev_start.sh

test: all
	rm -f priv/configs/env.config
	ln -s test.config priv/configs/env.config
	rebar3 eunit --dir="test" --cover=true --verbose=true
	rebar3 cover
