

.PHONY: all 

all: taekim_a4.pdf

%.pdf: %.tex
	xelatex $<
	xelatex $<


