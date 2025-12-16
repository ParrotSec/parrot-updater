/*
 * This is a Rust implementation of the old Parrot Updater script.
 * We use GTK 4 for managing the GUI.
 *
 * Libraries needed to compile the project: libgtk-4-dev libdbus-1-dev pkg-config
*/

use chrono::{DateTime, Duration, Utc};
use gtk4::prelude::*;
use gtk4::{Application, ApplicationWindow, Box, Button, Label, Orientation, ProgressBar, ScrolledWindow, TextView};
use gtk4::glib;
use std::fs;
use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;

const UPDATE_INTERVAL_MINUTES: i64 = 1;
const LAST_UPDATE_FILE: &str = ".last-updated";
const ICON: &str = "/usr/share/icons/parrot-logo.png";

enum UpdateMsg {
    Log(String),
    Finished(bool)
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let mode = if args.len() > 1 { &args[1] } else { "gui" };

    match mode {
        "scheduled" => run_scheduled(),
        _ => run_gui(),
    }
}

fn get_timestamp_path() -> PathBuf {
    let home = std::env::var("HOME").expect("Could not find $HOME");
    Path::new(&home).join(LAST_UPDATE_FILE)
}

fn run_scheduled() {
    // Check if we in a Live environment.
    if Path::new("/lib/live/mount/rootfs/filesystem.squashfs").exists() {
        return;
    }

    let path = get_timestamp_path();

    let should_run = if path.exists() {
        if let Ok(metadata) = fs::metadata(&path) {
            if let Ok(modified) = metadata.modified() {
                let modified_dt: DateTime<Utc> = modified.into();
                let now = Utc::now();
                (now - modified_dt) > Duration::minutes(UPDATE_INTERVAL_MINUTES)
            } else {
                true
            }
        } else {
            true
        }
    } else {
        true
    };

    if should_run {
        let _ = fs::write(&path, Utc::now().to_rfc3339());

        // Use a headless GTK Application to handle the notification lifecycle
        // This replaces notify-rust's deprecated blocking calls.
        let app = Application::builder()
            .application_id("org.parrotsec.parrot-updater.scheduled")
            .build();

        app.connect_activate(|app| {
            let _hold = app.hold();

            let notification = gio::Notification::new("Parrot Updater");
            notification.set_body(Some("A new update is available."));

            let icon_file = gio::File::for_path(ICON);
            let icon = gio::FileIcon::new(&icon_file);
            notification.set_icon(&icon);
            notification.add_button("Update Now", "app.open-gui");

            app.send_notification(Some("updater-notification"), &notification);

            let app_clone = app.clone();
            glib::timeout_add_seconds_local(300, move || {
                app_clone.quit();
                glib::ControlFlow::Break
            });
        });

        let action = gio::SimpleAction::new("open-gui", None);
        action.connect_activate(|_, _| {
            if let Ok(exe) = std::env::current_exe() {
                let _ = Command::new(exe)
                    .arg("gui")
                    .spawn();
            }
            std::process::exit(0);
        });

        app.add_action(&action);
        app.run_with_args(&Vec::<String>::new());
    } else {
        println!("No updates needed.");
    }
}

fn run_gui() {
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
        .default_width(360)
        .default_height(200)
        .build();

    window.connect_close_request(move |_| {
        std::process::exit(0);
    });

    if let Some(settings) = gtk4::Settings::default() {
        settings.set_gtk_application_prefer_dark_theme(true);
    }

    let vbox = Box::new(Orientation::Vertical, 10);
    vbox.set_margin_top(10);
    vbox.set_margin_bottom(10);
    vbox.set_margin_start(10);
    vbox.set_margin_end(10);

    let lbl_status = Label::new(Some("Ready to update system"));
    lbl_status.set_css_classes(&["title-4"]);

    let progress = ProgressBar::new();
    progress.set_visible(false);

    let text_view = TextView::builder()
        .editable(false)
        .monospace(true)
        .build();
    let scrolled_window = ScrolledWindow::builder()
        .hscrollbar_policy(gtk4::PolicyType::Automatic)
        .child(&text_view)
        .vexpand(true)
        .build();

    let btn_start = Button::with_label("Start Update");

    let hbox_btns = Box::new(Orientation::Horizontal, 10);
    hbox_btns.set_halign(gtk4::Align::Center);
    hbox_btns.append(&btn_start);

    vbox.append(&lbl_status);
    vbox.append(&progress);
    vbox.append(&scrolled_window);
    vbox.append(&hbox_btns);
    window.set_child(Some(&vbox));

    let buffer = text_view.buffer();
    let btn_start_clone = btn_start.clone();
    let window_clone = window.clone();

    btn_start.connect_clicked(move |_| {
        btn_start_clone.set_sensitive(false);
        progress.set_visible(true);
        progress.pulse();
        lbl_status.set_label("Updating...");
        buffer.set_text("");

        let (sender, receiver) = async_channel::unbounded::<UpdateMsg>();

        thread::spawn(move || {
            let cmd_str = "pkexec env DEBIAN_FRONTEND=noninteractive parrot-upgrade -y";

            let child = Command::new("sh")
                .arg("-c")
                .arg(cmd_str)
                .stdout(Stdio::piped())
                .stderr(Stdio::piped())
                .spawn();

            match child {
                Ok(mut child_proc) => {
                    if let Some(stdout) = child_proc.stdout.take() {
                        let reader = BufReader::new(stdout);
                        for line in reader.lines().filter_map(Result::ok) {
                                let _ = sender.try_send(UpdateMsg::Log(line));
                        }
                    }

                    let status = child_proc.wait();
                    match status {
                        Ok(s) => {
                            let _ = sender.try_send(UpdateMsg::Finished(s.success()));
                        }
                        Err(e) => {
                            let _ = sender.try_send(UpdateMsg::Log(format!("Process error: {}", e)));
                            let _ = sender.try_send(UpdateMsg::Finished(false));
                        }
                    }
                }
                Err(e) => {
                    let _ = sender.try_send(UpdateMsg::Log(format!("Failed to start process: {}", e)));
                    let _ = sender.try_send(UpdateMsg::Finished(false));
                }
            }
        });

        // TODO:
        // Instead of cloning every single widget,
        // we could group them into a struct and share that across closures
        //
        // Otherwise we can use glib::clone! macro.
        let buffer_clone = buffer.clone();
        let lbl_status_clone = lbl_status.clone();
        let progress_clone = progress.clone();
        let btn_start_clone2 = btn_start_clone.clone();
        let text_view_clone = text_view.clone();
        let window_clone2 = window_clone.clone();

        glib::timeout_add_local(std::time::Duration::from_millis(50), move || {
            while let Ok(msg) = receiver.try_recv() {
                match msg {
                    UpdateMsg::Log(text) => {
                        let clean_text = text.replace("\x1b", "");
                        let mut iter = buffer_clone.end_iter();
                        buffer_clone.insert(&mut iter, &format!("{}\n", clean_text));

                        let mark = buffer_clone.create_mark(None, &buffer_clone.end_iter(), false);
                        text_view_clone.scroll_to_mark(&mark, 0.0, true, 0.0, 1.0);
                        progress_clone.pulse();
                    }
                    UpdateMsg::Finished(success) => {
                        progress_clone.set_visible(false);

                        if success {
                            lbl_status_clone.set_label("Update completed successfully!");
                            btn_start_clone2.set_label("Done");

                            let path = get_timestamp_path();
                            let _ = fs::write(&path, Utc::now().to_rfc3339());

                            let dlg = gtk4::MessageDialog::builder()
                                .transient_for(&window_clone2)
                                .text("Update Completed")
                                .secondary_text("Your system is now up to date.")
                                .buttons(gtk4::ButtonsType::Ok)
                                .modal(true)
                                .build();
                            dlg.connect_response(|d, _| d.close());
                            dlg.show();

                        } else {
                            lbl_status_clone.set_label("Update failed");
                            btn_start_clone2.set_sensitive(true);
                            btn_start_clone2.set_label("Retry");
                        }

                        return glib::ControlFlow::Break;
                    }
                }
            }
            glib::ControlFlow::Continue
        });
    });

    window.present();
}