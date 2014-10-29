.PHONY: test

all:clean compile

compile:
	rebar compile

clean:
	rebar clean

test:
	rm -f priv/configs/env.config
	cd priv/configs && ln -s test.config env.config
	rm -rf .eunit
	rebar eunit
