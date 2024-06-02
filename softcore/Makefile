# simple shell of a Makefile to set up connectal and call the proc Makefile

MEM ?= ../guest/mem.vmh

REALMEM = $(realpath $(MEM))

test:
	@echo "MEM=$(MEM)"
	@echo $@

%:
	# create build dir if needed
	mkdir -p .build

	# clone connectal if not done yet
	[ -d .build/connectal ] || git clone https://github.com/cambridgehackers/connectal .build/connectal

	# clone fpgamake if not done yet
	[ -d .build/fpgamake ] || git clone https://github.com/cambridgehackers/fpgamake .build/fpgamake

	# clone buildcache if not done yet
	[ -d .build/buildcache ] || git clone https://github.com/cambridgehackers/buildcache .build/buildcache

	# link to the mem.vmh file
	ln -sf $(REALMEM) proc/mem.vmh

	# seed the verilator dir too
	mkdir -p proc/verilator
	ln -sf $(REALMEM) proc/verilator/mem.vmh

	# pass all arguments to proc Makefile
	$(MAKE) -C proc $@
