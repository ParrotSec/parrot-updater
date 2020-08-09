all:

clean:

install:
	mkdir -p bin/
	nim c --nimcache:/tmp --out:bin/update-reminder -d:release src/update_reminder.nim
