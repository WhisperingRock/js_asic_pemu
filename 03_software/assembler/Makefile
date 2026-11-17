.PHONY: asm demo clean

asm:
	python3 carp_asm.py program.asm -o program.mem

demo:
	python3 carp_asm.py demo/spi_tx.asm -o spi_tx.mem --sm regular
	python3 carp_asm.py demo/spi_rx.asm -o spi_rx.mem --sm bi

clean:
	rm -f *.mem