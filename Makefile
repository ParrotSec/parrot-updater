all:

clean:

install:
	mkdir -p $(DESTDIR)/usr/bin/
	mkdir -p $(DESTDIR)/usr/share/applications/
	mkdir -p $(DESTDIR)/etc/xdg/autostart/
	cp update-reminder.sh $(DESTDIR)/usr/bin/update-reminder
	cp parrot-updater.desktop $(DESTDIR)/etc/xdg/autostart/
	chown root:root $(DESTDIR)/usr/bin/update-reminder
	chown root:root $(DESTDIR)/etc/xdg/autostart/parrot-updater.desktop
	chmod 755 $(DESTDIR)/usr/bin/update-reminder
	chmod 755 $(DESTDIR)/etc/xdg/autostart/parrot-updater.desktop
