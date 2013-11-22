SHELL = /bin/bash
.PHONY: build build-styles build-scripts watch package open-fontello save-fontello

FONTELLO_HOST = http://fontello.com
CURL = curl --silent --show-error --fail

build: build-styles build-scripts

build-styles:
	stylus styles

build-scripts:
	lsc --bare --compile --output scripts scripts/*.ls

watch:
	${MAKE} build
	ls styles/*.styl scripts/*.ls | entr ${MAKE} build

package:
	rm -f chrome-ext.zip
	mkdir pkg
	ls | grep -vF pkg | xargs cp -rt pkg
	rm pkg/scripts/*.ls pkg/styles/*.styl pkg/Makefile
	cd pkg; zip -r ../chrome-ext.zip * > /dev/null
	rm -r pkg

open-fontello:
	${CURL} -o .fontello --form config=@fontello/config.json ${FONTELLO_HOST}
	x-www-browser ${FONTELLO_HOST}/`cat .fontello`

save-fontello:
	@rm -rf .fontello.{src,zip}
	${CURL} -o .fontello.zip ${FONTELLO_HOST}/`cat .fontello`/get
	@unzip .fontello.zip -d .fontello.src > /dev/null
	cat .fontello.src/*/css/{fontello-embedded,animation}.css \
		| grep -v margin | sed s,/font/,/fontello/, \
		> fontello/all.css
	mv .fontello.src/*/{config.json,font/fontello.{eot,svg}} fontello
#	sed 's,\<css/,../styles/,' .fontello.src/*/demo.html > fontello/demo.html
	@rm -rf .fontello.{src,zip}
