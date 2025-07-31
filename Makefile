executable := /usr/local/bin/gdl

install :
	cp gdl.sh $(executable)
	chmod +x $(executable)

uninstall :
	rm $(executable)
