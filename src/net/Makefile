architecture := $(shell uname -s)
ifeq ($(architecture),Darwin)
	SWTCH=
else
	SWTCH= -D
endif
SRCdir = `pwd`/..
BLDdir = $(SRCdir)/ebld
COMdir = $(SRCdir)/common
MFSdir = $(SRCdir)/emfs
LIBdir = $(SRCdir)/lib
CETCdir = $(SRCdir)/cetc
PROG = enet$(EXE)
default: $(PROG)

.SUFFIXES: .o .F .c
.F.o:
	$(MFC) $(FFLAGS) -c $<
%.o : %.f90
	$(MCC) $(FFLAGS) -c $<

MODULE_OBJECTS = startup.o CFC_Module.o

OBJECTS = network.o arrow.o ascii_mat.o azalt.o dossupport.o edatabase.o emfnetw.o \
	filelist.o icndbscn.o mfcdat.o mfrlst.o netwedit.o nwkrewr.o netwkc2f.o \
	netutil.o sort.o

MODULES = start_up.mod parse_command_line.mod CFC_Module.mod

$(PROG): $(MODULE_OBJECTS) $(OBJECTS)
	$(MFC) $(LD_FLAGS) -o $(PROG) $(FFLAGS) $(MODULE_OBJECTS) $(OBJECTS) $(ULIBS)

arrow.F:
	rm -f arrow.F
	ln -s $(COMdir)/arrow.F .
ascii_mat.F:
	rm -f ascii_mat.F
	ln -s $(COMdir)/ascii_mat.F .
azalt.F:
	rm -f azalt.F
	ln -s $(COMdir)/azalt.F .
CFC_Module.f90:
	rm -f CFC_Module.f90
	ln -s $(BLDdir)/CFC_Module.f90 .
dossupport.F:
	rm -f dossupport.F
	ln -s $(COMdir)/dossupport.F .
edatabase.F:
	rm -f edatabase.F
	ln -s $(COMdir)/edatabase.F .
emfnetw.F:
	rm -f emfnetw.F
	ln -s $(COMdir)/emfnetw.F .
filelist.F:
	rm -f filelist.F
	ln -s $(COMdir)/filelist.F .
mfcdat.F:
	rm -f mfcdat.F
	ln -s $(MFSdir)/mfcdat.F .
mfrlst.F:
	rm -f mfrlst.F
	ln -s $(MFSdir)/mfrlst.F .
nwkrewr.F:
	rm -f nwkrewr.F
	ln -s $(COMdir)/nwkrewr.F .
sort.F:
	rm -f sort.F
	ln -s $(COMdir)/sort.F .
startup.F:
	rm -f startup.F
	ln -s $(COMdir)/startup.F .

strip:
	strip $(PROG)

install:
	install $(SWTCH) $(PROG) $(ESPBinDir)/$(PROG)

clean:
	rm -f core $(PROG) $(PROG).exe $(MODULE_OBJECTS) $(OBJECTS) $(MODULES) \
	*.o arrow.F ascii_mat.F azalt.F dossupport.F edatabase.F emfnetw.F filelist.F \
	nwkrewr.F mfcdat.F mfrlst.F sort.F startup.F CFC_Module.f90 cfc_module.mod

distclean: clean

uninstall:
	-rm -f $(ESPBinDir)/$(PROG)
	
.PHONY: clean install default strip uninstall distclean
