#![cfg_attr(not(test), windows_subsystem = "windows")]

mod command;
mod window;
mod worker;

use std::{
    error::Error,
    sync::mpsc::{TrySendError, sync_channel},
    thread,
};

const QUEUE_CAPACITY: usize = 64;

fn main() {
    std::panic::set_hook(Box::new(|panic| window::log(&format!("panic: {panic}"))));
    if let Err(error) = run() {
        window::log(&format!("bridge startup failed: {error}"));
    }
}

fn run() -> Result<(), Box<dyn Error>> {
    let Some(_instance) = window::acquire_instance()? else {
        return Ok(());
    };

    let message = window::register_message()?;
    let (sender, receiver) = sync_channel(QUEUE_CAPACITY);
    window::initialize(message, sender.clone())?;

    let path = worker::socket_path()?;
    let worker = thread::Builder::new()
        .name("komorebi-ahk-bridge-worker".into())
        .spawn(move || worker::run(receiver, path))?;

    let loop_result = window::create_hidden_window().and_then(|_window| window::message_loop());

    match sender.try_send(worker::SHUTDOWN) {
        Ok(()) => {}
        Err(TrySendError::Full(_)) => window::log("worker shutdown command dropped: queue full"),
        Err(TrySendError::Disconnected(_)) => {
            window::log("worker shutdown command dropped: worker disconnected")
        }
    }

    drop(worker);
    loop_result?;
    Ok(())
}
