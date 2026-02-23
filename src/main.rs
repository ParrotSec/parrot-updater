mod utils;
mod scheduler;
mod gui;

fn main() {
    let mode = std::env::args().nth(1);
    let mode_str = mode.as_deref().unwrap_or("gui");

    match mode_str {
        "scheduled" => scheduler::run_scheduled(),
        "gui" => gui::run_gui(),
        _ => {
            println!("Usage: parrot-updater [gui|scheduled]");
        }
    }
}