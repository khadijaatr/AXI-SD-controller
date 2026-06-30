TMPDIR := $(CURDIR)/vcs_tmp
export TMPDIR

all: clean comp run waveverdi

test: comp run

clean:
	rm -rf simv* csrc* *.log *.fsdb *.rc *.key verdi_config_file verdiLog *.conf vcs_tmp

comp:
	mkdir -p $(TMPDIR)
	vcs -f build.cud -sverilog -kdb +vcs+fsdbon -cm line+cond+fsm+tgl+branch

run:
	mkdir -p $(TMPDIR)
	qrsh -V -cwd -b y -q normal ./simv -cm line+cond+fsm+tgl+branch 2>&1 | tee log
	#qrsh -V -cwd -b y -q normal ./simv +ntb_random_seed_automatic 2>&1 | tee log

waveverdi:
	verdi -ssf novas.fsdb

coverage:
	verdi -cov -covdir simv.vdb
