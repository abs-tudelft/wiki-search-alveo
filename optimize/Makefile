
SOURCES = main.cpp
HEADERS =

#Include arrow
arrow_LDFLAGS=$(shell pkg-config --libs arrow)
arrow_CXXFLAGS=$(shell pkg-config --cflags arrow) -D_GLIBCXX_USE_CXX11_ABI=0

optimize: $(SOURCES) $(HEADERS)
	g++ $(SOURCES) ${arrow_CXXFLAGS} ${arrow_LDFLAGS} -o $@ -std=c++11 -fopenmp

.PHONY: clean
clean:
	rm -f optimize
