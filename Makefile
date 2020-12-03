converter := ./converter
source_dir := ./jpgramma/
repo_dir := https://github.com/pizzamx/jpgramma
# repo_dir := https://github.com/jiangming1399/jpgramma

.PHONY: all clean

all: taekim_a4.pdf taekim_a4_print.pdf taekim_ebook.pdf

taekim_ebook.pdf: taekim_ebook.tex taekim_ebook.sty body.tex
	xelatex taekim_ebook
	xelatex taekim_ebook
	xelatex taekim_ebook
	pdf90 --suffix 'turned' --batch taekim_ebook.pdf
	mv taekim_ebook-turned.pdf taekim_ebook.pdf

taekim_a4.pdf: taekim_a4.tex taekim.sty body.tex
	xelatex taekim_a4
	xelatex taekim_a4
	xelatex taekim_a4

taekim_a4_print.pdf: taekim_a4_print.tex taekim_print.sty body.tex
	xelatex taekim_a4_print
	xelatex taekim_a4_print
	xelatex taekim_a4_print

clean:
	$(RM) taekim_a4.pdf taekim_a4_print.pdf taekim_ebook.pdf
	$(RM) *.log *.aux *.out *.toc
dist_clean: clean
	$(RM) -r body.tex out
	$(RM) $(converter)
	$(RM) -rf $(source_dir)

converter: main.go
	go build -o $(converter)
	
body.tex: converter
	test -d $(source_dir) || git clone $(repo_dir) $(source_dir)
	$(converter) $(source_dir)
