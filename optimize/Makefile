
SOURCES = main.cpp
HEADERS =

optimize: $(SOURCES) $(HEADERS)
	g++ $(SOURCES) -larrow -o $@ -std=c++11 -fopenmp

.PHONY: clean
clean:
	rm -f optimize
