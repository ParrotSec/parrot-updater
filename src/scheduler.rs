use chrono::{DateTime, Duration, Utc};
use std::fs;
#[cfg(target_os = "linux")]
use std::process::{Command, Stdio};
use notify_rust::{Notification, Timeout};
use crate::utils::{get_timestamp_path, is_live_environment, ICON};

pub fn run_scheduled() {
    if is_live_environment() {
        return;
    }

    let path = get_timestamp_path();
    let now = Utc::now();

    let should_run = if let Ok(metadata) = fs::metadata(&path) {
        if let Ok(modified) = metadata.modified() {
            let modified_dt: DateTime<Utc> = modified.into();
            (now - modified_dt) > Duration::weeks(1)
        } else {
            true
        }
    } else {
        true
    };

    if should_run {
        let _ = fs::write(&path, now.to_rfc3339());

        let notification_result = Notification::new()
            .summary("Parrot Updater")
            .body("A new update is available.")
            .icon(ICON)
            .timeout(Timeout::Milliseconds(300_000))
            .action("open_gui", "Update Now")
            .show();

        match notification_result {
            Ok(handle) => {
                #[cfg(target_os = "linux")]
                handle.wait_for_action(|action| {
                    if action == "open_gui" {
                        if let Ok(exe) = std::env::current_exe() {
                            let _ = Command::new(exe)
                                .arg("gui")
                                .stdin(Stdio::null())
                                .stdout(Stdio::null())
                                .stderr(Stdio::null())
                                .spawn();
                        }
                    }
                });
                #[cfg(not(target_os = "linux"))]
                { let _ = handle; }
            },
            Err(e) => eprintln!("Failed to send notification: {}", e),
        }
    } else {
        if let Ok(metadata) = fs::metadata(&path) {
            if let Ok(modified) = metadata.modified() {
                let last_run: DateTime<Utc> = modified.into();
                let next_run = last_run + Duration::weeks(1);
                let remaining = next_run - now;

                if remaining.num_seconds() > 0 {
                    let days = remaining.num_days();
                    let hours = remaining.num_hours() % 24;
                    let mins = remaining.num_minutes() % 60;
                    let secs = remaining.num_seconds() % 60;

                    if days > 0 {
                        println!("No updates needed. Next check in {}d {}h {}m.", days, hours, mins);
                    } else if hours > 0 {
                        println!("No updates needed. Next check in {}h {}m {}s.", hours, mins, secs);
                    } else {
                        println!("No updates needed. Next check in {}m {}s.", mins, secs);
                    }
                    return;
                }
            }
        }
        println!("No updates needed.");
    }
}