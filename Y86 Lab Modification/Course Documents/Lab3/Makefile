all:
	mkdir -p obj
	pdflatex -output-directory=./obj lab3.tex
	pdflatex -output-directory=./obj lab3.tex
	ln -sf src/obj/lab3.pdf ../

clean:
	rm -rf ./obj
	rm ../lab3.pdf
