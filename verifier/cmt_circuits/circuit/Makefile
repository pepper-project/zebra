
OBJS = basic_cmt_circuit circuit circuit_data circuit_layer cmt_circuit magic_var_operation pws_circuit pws_circuit_parser cmt_circuit_builder

CXXFLAGS += -fPIC -O2
IFLAGS = -I../include
IFLAGS += -I ~/pepper_deps/include
IFLAGS += -I$(HOME)/toolchains/include -I$(IUS_HOME)/inca/include

all: $(OBJS:=.o)

%.o: %.cpp %.h
	$(CXX) $(CXXFLAGS) $(IFLAGS) -c $<

clean:
	rm -rf *.o
