.PHONY: test

all:clean compile

compile:
	rebar compile

clean:
	rebar clean

test:
	rm -rf .eunit
	rebar clean compile eunit
