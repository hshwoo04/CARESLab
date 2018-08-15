all:
	mkdir -p obj
	pdflatex -output-directory=./obj lab1.tex
	pdflatex -output-directory=./obj lab1.tex
	ln -sf src/obj/lab1.pdf ../

clean:
	rm -rf ./obj
	rm ../lab1.pdf
