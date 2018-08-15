all:
	mkdir -p obj
	pdflatex -output-directory=./obj lab.tex
	pdflatex -output-directory=./obj lab.tex
	cp obj/lab.pdf ./lab4.pdf

clean:
	rm -rf ./obj
	rm ../lab4.pdf
