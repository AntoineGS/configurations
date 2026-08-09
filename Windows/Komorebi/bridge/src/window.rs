use std::{
    panic::{AssertUnwindSafe, catch_unwind},
    sync::{
        OnceLock,
        mpsc::{SyncSender, TrySendError},
    },
};

use windows::{
    Win32::{
        Foundation::{
            CloseHandle, E_UNEXPECTED, ERROR_ALREADY_EXISTS, GetLastError, HANDLE, HINSTANCE, HWND,
            LPARAM, LRESULT, WPARAM,
        },
        System::{
            Diagnostics::Debug::OutputDebugStringW, LibraryLoader::GetModuleHandleW,
            Threading::CreateMutexW,
        },
        UI::WindowsAndMessaging::{
            CreateWindowExW, DefWindowProcW, DestroyWindow, DispatchMessageW, GetMessageW, MSG,
            PostQuitMessage, RegisterClassW, RegisterWindowMessageW, TranslateMessage,
            WINDOW_EX_STYLE, WINDOW_STYLE, WM_CLOSE, WM_DESTROY, WNDCLASSW,
        },
    },
    core::{Error, PCWSTR, Result, w},
};

use crate::command::payload_for;

pub const WINDOW_CLASS: PCWSTR = w!("Configurations.Komorebi.Bridge.v1");
pub const WINDOW_TITLE: PCWSTR = w!("Configurations.Komorebi.Bridge.v1");
pub const MESSAGE_NAME: PCWSTR = w!("Configurations.Komorebi.Bridge.Command.v1");
const MUTEX_NAME: PCWSTR = w!("Local\\Configurations.Komorebi.Bridge.v1");

static COMMAND_MESSAGE: OnceLock<u32> = OnceLock::new();
static COMMAND_SENDER: OnceLock<SyncSender<u32>> = OnceLock::new();

#[derive(Debug, Eq, PartialEq)]
pub enum QueueResult {
    Queued,
    Unknown,
    Full,
    Disconnected,
}

pub fn queue_command(sender: &SyncSender<u32>, id: u32) -> QueueResult {
    if payload_for(id).is_none() {
        return QueueResult::Unknown;
    }

    match sender.try_send(id) {
        Ok(()) => QueueResult::Queued,
        Err(TrySendError::Full(_)) => QueueResult::Full,
        Err(TrySendError::Disconnected(_)) => QueueResult::Disconnected,
    }
}

pub fn log(message: &str) {
    let wide: Vec<u16> = message.encode_utf16().chain(std::iter::once(0)).collect();
    unsafe { OutputDebugStringW(PCWSTR(wide.as_ptr())) };
}

pub struct Instance(HANDLE);

impl Drop for Instance {
    fn drop(&mut self) {
        unsafe {
            let _ = CloseHandle(self.0);
        }
    }
}

pub fn acquire_instance() -> Result<Option<Instance>> {
    let handle = unsafe { CreateMutexW(None, false, MUTEX_NAME)? };
    if unsafe { GetLastError() } == ERROR_ALREADY_EXISTS {
        unsafe {
            let _ = CloseHandle(handle);
        }
        return Ok(None);
    }

    Ok(Some(Instance(handle)))
}

pub fn register_message() -> Result<u32> {
    let id = unsafe { RegisterWindowMessageW(MESSAGE_NAME) };
    if id == 0 {
        Err(Error::from_thread())
    } else {
        Ok(id)
    }
}

pub fn initialize(message: u32, sender: SyncSender<u32>) -> Result<()> {
    COMMAND_MESSAGE
        .set(message)
        .map_err(|_| Error::from_hresult(E_UNEXPECTED))?;
    COMMAND_SENDER
        .set(sender)
        .map_err(|_| Error::from_hresult(E_UNEXPECTED))?;
    Ok(())
}

unsafe extern "system" fn window_proc(
    hwnd: HWND,
    message: u32,
    wparam: WPARAM,
    lparam: LPARAM,
) -> LRESULT {
    catch_unwind(AssertUnwindSafe(|| unsafe {
        window_proc_inner(hwnd, message, wparam, lparam)
    }))
    .unwrap_or_else(|_| {
        log("window procedure panic");
        LRESULT(0)
    })
}

unsafe fn window_proc_inner(hwnd: HWND, message: u32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    if COMMAND_MESSAGE.get().is_some_and(|id| *id == message) {
        if lparam.0 != 0 || wparam.0 > u32::MAX as usize {
            log("invalid bridge command parameters");
            return LRESULT(0);
        }

        match COMMAND_SENDER.get() {
            Some(sender) => {
                let id = wparam.0 as u32;
                let result = queue_command(sender, id);
                if result != QueueResult::Queued {
                    log(&format!("command {id} queue result: {result:?}"));
                }
            }
            None => log("bridge command sender is not initialized"),
        }
        return LRESULT(0);
    }

    match message {
        WM_CLOSE => {
            let _ = unsafe { DestroyWindow(hwnd) };
            LRESULT(0)
        }
        WM_DESTROY => {
            unsafe { PostQuitMessage(0) };
            LRESULT(0)
        }
        _ => unsafe { DefWindowProcW(hwnd, message, wparam, lparam) },
    }
}

pub fn create_hidden_window() -> Result<HWND> {
    let module = unsafe { GetModuleHandleW(None)? };
    let instance = HINSTANCE(module.0);
    let class = WNDCLASSW {
        lpfnWndProc: Some(window_proc),
        hInstance: instance,
        lpszClassName: WINDOW_CLASS,
        ..Default::default()
    };

    if unsafe { RegisterClassW(&class) } == 0 {
        return Err(Error::from_thread());
    }

    unsafe {
        CreateWindowExW(
            WINDOW_EX_STYLE::default(),
            WINDOW_CLASS,
            WINDOW_TITLE,
            WINDOW_STYLE::default(),
            0,
            0,
            0,
            0,
            None,
            None,
            Some(instance),
            None,
        )
    }
}

pub fn message_loop() -> Result<()> {
    let mut message = MSG::default();
    loop {
        let status = unsafe { GetMessageW(&mut message, None, 0, 0) }.0;
        if status == -1 {
            return Err(Error::from_thread());
        }
        if status == 0 {
            return Ok(());
        }

        unsafe {
            let _ = TranslateMessage(&message);
            DispatchMessageW(&message);
        }
    }
}

#[cfg(test)]
mod tests {
    use std::sync::mpsc::sync_channel;

    use super::*;
    use crate::command::CLOSE;

    #[test]
    fn queues_first_command_and_reports_full_for_capacity_one() {
        let (sender, _receiver) = sync_channel(1);

        assert_eq!(queue_command(&sender, CLOSE), QueueResult::Queued);
        assert_eq!(queue_command(&sender, CLOSE), QueueResult::Full);
    }

    #[test]
    fn reports_unknown_and_disconnected() {
        let (sender, receiver) = sync_channel(1);

        assert_eq!(queue_command(&sender, u32::MAX), QueueResult::Unknown);
        drop(receiver);
        assert_eq!(queue_command(&sender, CLOSE), QueueResult::Disconnected);
    }
}
