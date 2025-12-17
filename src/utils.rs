use std::path::{Path, PathBuf};

pub const LAST_UPDATE_FILE: &str = ".last-updated";
pub const ICON: &str = "/usr/share/icons/parrot-logo.png";

pub fn get_timestamp_path() -> PathBuf {
    let home = std::env::var("HOME").expect("Could not find $HOME");
    Path::new(&home).join(LAST_UPDATE_FILE)
}

pub fn is_live_environment() -> bool {
    Path::new("/lib/live/mount/rootfs/filesystem.squashfs").exists()
}