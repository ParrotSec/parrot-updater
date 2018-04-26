all:

clean:

install:
	mkdir -p $(DESTDIR)/usr/bin/
	mkdir -p $(DESTDIR)/usr/share/applications/
	mkdir -p $(DESTDIR)/etc/xdg/autostart/
	cp update-reminder.sh $(DESTDIR)/usr/bin/update-reminder
	cp dist-upgrade.sh $(DESTDIR)/usr/bin/dist-upgrade
	cp dist-upgrade.sh $(DESTDIR)/usr/bin/full-upgrade
	cp dist-upgrade.sh $(DESTDIR)/usr/bin/upgrade
	cp dist-upgrade.sh $(DESTDIR)/usr/bin/update
	cp dist-upgrade.sh $(DESTDIR)/usr/bin/parrot-upgrade
	cp parrot-updater.desktop $(DESTDIR)/etc/xdg/autostart/
	chown root:root $(DESTDIR)/usr/bin/update-reminder
	chown root:root $(DESTDIR)/usr/bin/dist-upgrade
	chown root:root $(DESTDIR)/etc/xdg/autostart/parrot-updater.desktop
	chmod 755 $(DESTDIR)/usr/bin/update-reminder
	chmod 755 $(DESTDIR)/usr/bin/dist-upgrade
	chmod 755 $(DESTDIR)/usr/bin/full-upgrade
	chmod 755 $(DESTDIR)/usr/bin/upgrade
	chmod 755 $(DESTDIR)/usr/bin/update
	chmod 755 $(DESTDIR)/usr/bin/parrot-upgrade
	chmod 755 $(DESTDIR)/etc/xdg/autostart/parrot-updater.desktop
