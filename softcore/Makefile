# simple shell of a Makefile to set up connectal and call the proc Makefile

MEM ?= ../guest/mem.vmh

%:
	# create build dir if needed
	mkdir -p .build

	# clone connectal if not done yet
	[ -d .build/connectal ] || git clone https://github.com/cambridgehackers/connectal

	# link to the mem.vmh file
	ln -sf $(MEM) proc/mem.vmh
	
	# pass all arguments to proc Makefile
	$(MAKE) -C .build/connectal/softcore/proc $@
