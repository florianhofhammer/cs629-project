CONNECTALDIR?=../..
S2H_INTERFACES = EchoRequest:Echo.request
H2S_INTERFACES = Echo:EchoIndication

BSVFILES = Echo.bsv
CPPFILES= testecho.cpp

CONNECTALFLAGS += --verilatorflags=--timing --nonstrict -D TRACE_PORTAL

include $(CONNECTALDIR)/Makefile.connectal

