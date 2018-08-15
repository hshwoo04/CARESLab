all:
	mkdir -p obj
	pdflatex -output-directory=./obj lab.tex
	pdflatex -output-directory=./obj lab.tex
	cp ./obj/lab.pdf ../lab2.pdf

clean:
	rm -rf ./obj
	rm ../lab2.pdf
