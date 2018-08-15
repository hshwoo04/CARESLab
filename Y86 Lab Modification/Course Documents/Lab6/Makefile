all:
	mkdir -p obj
	pdflatex -output-directory=./obj lab.tex
	pdflatex -output-directory=./obj lab.tex
	ln -sf obj/lab.pdf ./lab6.pdf

clean:
	rm -rf ./obj
	rm ../lab6.pdf
