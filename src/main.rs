mod utils;
mod updater;
mod scheduler;
mod gui;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let mode = args.get(1).map(|s| s.as_str()).unwrap_or("gui");

    match mode {
        "scheduled" => scheduler::run_scheduled(),
        "gui" => gui::run_gui(),
        _ => {
            println!("Usage: parrot-updater [gui|scheduled]");
        }
    }
}