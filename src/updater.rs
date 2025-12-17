use std::process::{Command, Stdio};
use std::io::{BufRead, BufReader};
use async_channel::Sender;

pub enum UpdateMsg {
    Log(String),
    Finished(bool),
}

pub fn run_upgrade_process(sender: Sender<UpdateMsg>) {
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
                Ok(s) => { let _ = sender.try_send(UpdateMsg::Finished(s.success())); }
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
}