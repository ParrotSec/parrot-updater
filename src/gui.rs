use gtk4::prelude::*;
use gtk4::{Application, ApplicationWindow, Box, Button, Label, Orientation, ProgressBar, ScrolledWindow, TextView};
use gtk4::glib;
use std::fs;
use std::thread;
use chrono::Utc;
use crate::utils::{VERSION, AUTHOR, PROJECT_URL};

use crate::updater::{UpdateMsg, run_upgrade_process};
use crate::utils::get_timestamp_path;

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
        .default_width(600)
        .default_height(400)
        .build();

    if let Some(settings) = gtk4::Settings::default() {
        settings.set_gtk_application_prefer_dark_theme(true);
    }

    let vbox = Box::new(Orientation::Vertical, 10);
    let hbox_btns = Box::new(Orientation::Horizontal, 10);
    set_margin_all(&vbox, 10);

    let lbl_status = Label::new(Some("Ready to update system"));
    let progress = ProgressBar::builder().visible(false).build();
    let text_view = TextView::builder().editable(false).monospace(true).build();
    let scrolled = ScrolledWindow::builder().child(&text_view).vexpand(true).build();

    let btn_start = Button::with_label("Start Update");
    let btn_about = Button::builder()
        .icon_name("help-about-symbolic")
        .tooltip_text("About Parrot Updater")
        .build();

    hbox_btns.set_halign(gtk4::Align::Center);
    hbox_btns.append(&btn_start);
    hbox_btns.append(&btn_about);

    vbox.append(&lbl_status);
    vbox.append(&progress);
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
                .build();

            about.show();
        }
    });

    btn_start.connect_clicked({
        let lbl_status = lbl_status.clone();
        let progress = progress.clone();
        let text_view = text_view.clone();
        let window = window.clone();

        move |btn| {
            btn.set_sensitive(false);
            progress.set_visible(true);
            lbl_status.set_label("Updating...");

            let buffer = text_view.buffer();
            buffer.set_text("");

            let (sender, receiver) = async_channel::unbounded::<UpdateMsg>();

            thread::spawn(move || {
                run_upgrade_process(sender);
            });

            glib::timeout_add_local(
                std::time::Duration::from_millis(50),
                {
                    let lbl_status = lbl_status.clone();
                    let progress = progress.clone();
                    let text_view = text_view.clone();
                    let btn = btn.clone();
                    let window = window.clone();

                    move || {
                        while let Ok(msg) = receiver.try_recv() {
                            match msg {
                                UpdateMsg::Log(text) => {
                                    let buf = text_view.buffer();
                                    let mut iter = buf.end_iter();
                                    buf.insert(&mut iter, &format!("{}\n", text.replace("\x1b", "")));
                                    let mark = buf.create_mark(None, &buf.end_iter(), false);
                                    text_view.scroll_to_mark(&mark, 0.0, true, 0.0, 1.0);
                                    progress.pulse();
                                }
                                UpdateMsg::Finished(success) => {
                                    progress.set_visible(false);
                                    if success {
                                        lbl_status.set_label("Update completed!");
                                        btn.set_label("Done");
                                        let _ = fs::write(get_timestamp_path(), Utc::now().to_rfc3339());
                                        show_finished_dialog(&window);
                                    } else {
                                        lbl_status.set_label("Update failed");
                                        btn.set_sensitive(true);
                                        btn.set_label("Retry");
                                    }
                                    return glib::ControlFlow::Break;
                                }
                            }
                        }
                        glib::ControlFlow::Continue
                    }
                }
            );
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