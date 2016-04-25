OBJS = prng
CXXFLAGS += -fPIC -O2
IFLAGS = -I../
IFLAGS += -I ~/pepper_deps/include
IFLAGS += -I$(HOME)/toolchains/include -I$(IUS_HOME)/inca/include

all: $(OBJS:=.o)

%.o: %.cpp %.h
	$(CXX) $(CXXFLAGS) $(IFLAGS) -c $<

clean:
	rm -rf *.o
