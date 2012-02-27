

.PHONY: all 

all: taekim_a4.pdf taekim_ebook.pdf

%.pdf: %.tex
	xelatex $<
	xelatex $<


