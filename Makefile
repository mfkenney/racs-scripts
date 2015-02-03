#
# Install RACS scripts and config files
#
SHELL = /bin/sh
INSTALL = install
CFGDIR := $(HOME)/config
BINDIR := $(HOME)/bin
DATADIRS := $(HOME)/archive $(HOME)/snapshots $(HOME)/INBOX $(HOME)/OUTBOX

SCRIPTS := $(wildcard *.sh)
CFGFILES := defaults settings
CRONFILE := jobs.cron
ADCFG := adc_config/$(shell hostname -s).yml

install: dirs install-config install-bin install-adc-config

.PHONY: install dirs install-bin install-config install-adc-config

dirs:
	@echo "Creating data directories ..."
	$(INSTALL) -d $(DATADIRS)

install-bin: $(SCRIPTS)
	@echo "Installing scripts ..."
	$(INSTALL) -d $(BINDIR)
	$(INSTALL) -m 755 $^ $(BINDIR)/

install-config: $(CFGFILES)
	@echo "Installing configuration files ..."
	$(INSTALL) -d $(CFGDIR)
	$(INSTALL) -m 644 $^ $(CFGDIR)/

install-cron: $(CRONFILE)
	@echo "Installing Cron jobs ..."
	crontab $(CRONFILE)

install-adc-config:
	@echo "Installing A/D config file ..."
	-test ! -f $(ADCFG) || $(INSTALL) -m 644 $(ADCFG) $(CFGDIR)/adc.yml
