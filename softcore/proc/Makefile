CONNECTALDIR ?= ../.build/connectal
S2H_INTERFACES = BridgeRequest:Controller.request
H2S_INTERFACES = Controller:BridgeIndication

BSVFILES = Controller.bsv
CPPFILES = bridge.cpp

CONNECTALFLAGS += --verilatorflags=--timing --nonstrict -D TRACE_PORTAL

include $(CONNECTALDIR)/Makefile.connectal

