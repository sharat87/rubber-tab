SHELL = /bin/bash
.PHONY: build build-styles build-scripts watch package open-fontello save-fontello

FONTELLO_HOST = http://fontello.com
CURL = curl --silent --show-error --fail
BROWSER = x-www-browser

LSC = ./node_modules/LiveScript/bin/lsc
STYLUS = ./node_modules/stylus/bin/stylus
UGLIFYJS = ./node_modules/uglify-js/bin/uglifyjs --screw-ie8
ENTR = entr

build: build-styles build-scripts

build-styles:
	@echo Building styles
	@ls styles/themes | while read theme; do \
		${STYLUS} --print --compress --import themes/$$theme styles/master.styl \
			> styles/$${theme%\.*}.css; \
	done

build-scripts:
	@echo Compiling scripts
	@${LSC} --bare --compile `find -name '*.ls'`

watch:
	find -name '*.styl' -or -name '*.ls' | ${ENTR} -r ${MAKE} build

package: build
	rm -f rubber-tab.zip
	mkdir pkg
	cp -rt pkg fontello icons index.html manifest.json scripts styles vendor
	find pkg -name '*.js' | xargs -I% ${UGLIFYJS} -o % %
	cd pkg; zip -r ../rubber-tab.zip * > /dev/null
	rm -r pkg

open-fontello:
	${CURL} -o .fontello --form config=@fontello/config.json ${FONTELLO_HOST}
	${BROWSER} ${FONTELLO_HOST}/`cat .fontello`

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
