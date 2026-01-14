use gtk4::prelude::*;
use gtk4::{Application, ApplicationWindow, Box, Button, Label, Orientation, ScrolledWindow};
use gtk4::glib;
use vte4::prelude::*;
use vte4::Terminal;
use std::fs;
use chrono::Utc;
use crate::utils::{VERSION, AUTHOR, PROJECT_URL, get_timestamp_path};

fn set_margin_all(widget: &impl WidgetExt, margin: i32) {
    widget.set_margin_top(margin);
    widget.set_margin_bottom(margin);
    widget.set_margin_start(margin);
    widget.set_margin_end(margin);
}

pub fn run_gui() {
    let app = Application::builder()
        .application_id("org.parrotsec.parrot-updater")
        .build();

    app.connect_activate(build_ui);
    app.run_with_args(&Vec::<String>::new());
}

fn build_ui(app: &Application) {
    let window = ApplicationWindow::builder()
        .application(app)
        .title("Parrot Updater")
        .default_width(700)
        .default_height(500)
        .build();

    if let Some(settings) = gtk4::Settings::default() {
        settings.set_gtk_application_prefer_dark_theme(true);
    }

    let vbox = Box::new(Orientation::Vertical, 10);
    let hbox_btns = Box::new(Orientation::Horizontal, 10);
    set_margin_all(&vbox, 10);

    let lbl_status = Label::new(Some("Ready to update system"));

    let terminal = Terminal::new();
    terminal.set_scroll_on_output(true);
    terminal.set_scrollback_lines(10000);
    terminal.set_cursor_blink_mode(vte4::CursorBlinkMode::Off);

    let scrolled = ScrolledWindow::builder()
        .child(&terminal)
        .vexpand(true)
        .build();

    let btn_start = Button::with_label("Start Update");
    let btn_about = Button::builder()
        .icon_name("help-about-symbolic")
        .tooltip_text("About Parrot Updater")
        .build();

    hbox_btns.set_halign(gtk4::Align::Center);
    hbox_btns.append(&btn_start);
    hbox_btns.append(&btn_about);

    vbox.append(&lbl_status);
    vbox.append(&scrolled);
    vbox.append(&hbox_btns);

    window.set_child(Some(&vbox));

    btn_about.connect_clicked({
        let window = window.clone();
        move |_| {
            let about = gtk4::AboutDialog::builder()
                .transient_for(&window)
                .modal(true)
                .program_name("Parrot Updater")
                .version(VERSION)
                .authors(vec![AUTHOR.to_string()])
                .website(PROJECT_URL)
                .website_label("Source Code")
                .comments("The official system updater for ParrotOS.")
                .copyright("© Parrot Security")
                .license_type(gtk4::License::Gpl30)
                .logo_icon_name("parrot-logo")
                .build();

            about.show();
        }
    });

    btn_start.connect_clicked({
        let lbl_status = lbl_status.clone();
        let terminal = terminal.clone();
        let window = window.clone();

        move |btn| {
            btn.set_sensitive(false);
            lbl_status.set_label("Updating...");

            let cmd_str = "pkexec parrot-upgrade";

            let argv: &[&str] = &["/bin/sh", "-c", cmd_str];

            // Since we are using vte4, we may remove updater.rs
            terminal.spawn_async(
                vte4::PtyFlags::DEFAULT,
                None,
                argv,
                &[],
                glib::SpawnFlags::DEFAULT,
                || {},
                -1,
                None::<&gtk4::gio::Cancellable>,
                {
                    let lbl_status = lbl_status.clone();
                    let btn = btn.clone();

                    move |result| {
                        if let Err(e) = result {
                            lbl_status.set_label(&format!("Failed to start: {}", e));
                            btn.set_sensitive(true);
                        }
                    }
                }
            );

            terminal.connect_child_exited({
                let lbl_status = lbl_status.clone();
                let btn = btn.clone();
                let window = window.clone();

                move |_terminal, exit_status| {
                    if exit_status == 0 {
                        lbl_status.set_label("Update completed!");
                        btn.set_label("Done");
                        let _ = fs::write(get_timestamp_path(), Utc::now().to_rfc3339());
                        show_finished_dialog(&window);
                    } else {
                        lbl_status.set_label(&format!("Update failed (exit code: {})", exit_status));
                        btn.set_sensitive(true);
                        btn.set_label("Retry");
                    }
                }
            });
        }
    });

    window.present();
}

fn show_finished_dialog(parent: &ApplicationWindow) {
    let dlg = gtk4::MessageDialog::builder()
        .transient_for(parent)
        .text("Update Completed")
        .buttons(gtk4::ButtonsType::Ok)
        .modal(true)
        .build();

    dlg.connect_response({
        let parent = parent.clone();
        move |d, _| {
            d.close();
            parent.close();
        }
    });

    dlg.show();
}