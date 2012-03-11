

.PHONY: all clean

all: taekim_a4.pdf taekim_ebook.pdf

taekim_ebook.pdf: taekim_ebook.tex taekim_ebook.sty
	xelatex taekim_ebook
	xelatex taekim_ebook
	pdf90 --suffix 'turned' --batch taekim_ebook.pdf
	mv taekim_ebook-turned.pdf taekim_ebook.pdf

taekim_a4.pdf: taekim_a4.tex taekim.sty
	xelatex taekim_a4
	xelatex taekim_a4

clean:
	$(RM) taekim_a4.pdf taekim_ebook.pdf

