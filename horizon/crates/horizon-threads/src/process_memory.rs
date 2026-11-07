//! Read-only process memory diagnostics.
/// The process's memory counters.
#[cfg(windows)]
fn counters() -> Option<windows_sys::Win32::System::ProcessStatus::PROCESS_MEMORY_COUNTERS_EX2> {
    use windows_sys::Win32::System::ProcessStatus::{
        K32GetProcessMemoryInfo, PROCESS_MEMORY_COUNTERS_EX2,
    };
    use windows_sys::Win32::System::Threading::GetCurrentProcess;
    let size = std::mem::size_of::<PROCESS_MEMORY_COUNTERS_EX2>() as u32;
    // SAFETY: all-zero is a valid value of this plain C struct, which starts with the fields of the
    // one the call is declared with, and the call writes at most `size` bytes into it; the current
    // process's pseudo-handle needs no closing.
    unsafe {
        let mut counters: PROCESS_MEMORY_COUNTERS_EX2 = std::mem::zeroed();
        counters.cb = size;
        (K32GetProcessMemoryInfo(GetCurrentProcess(), (&raw mut counters).cast(), size) != 0)
            .then_some(counters)
    }
}

/// The memory this process holds in RAM, in bytes.
#[cfg(windows)]
pub fn resident_bytes() -> Option<u64> {
    Some(counters()?.WorkingSetSize as u64)
}

/// The private memory this process holds in RAM, all it holds in RAM and the machine's RAM, in
/// bytes.
#[cfg(windows)]
pub fn usage() -> Option<[u64; 3]> {
    use windows_sys::Win32::System::SystemInformation::{GlobalMemoryStatusEx, MEMORYSTATUSEX};
    let counters = counters()?;
    let resident = counters.WorkingSetSize as u64;
    let private = match counters.PrivateWorkingSetSize {
        // Windows before 10 22H2 leaves it empty: the private commit is the nearest it has.
        0 => (counters.PrivateUsage as u64).min(resident),
        bytes => bytes as u64,
    };
    // SAFETY: all-zero is a valid value of this plain C struct, its length is set as the call
    // requires, and the call only writes into it.
    let ram = unsafe {
        let mut status: MEMORYSTATUSEX = std::mem::zeroed();
        status.dwLength = std::mem::size_of::<MEMORYSTATUSEX>() as u32;
        (GlobalMemoryStatusEx(&mut status) != 0).then_some(status.ullTotalPhys)
    }?;
    Some([private, resident, ram])
}

/// [`usage`]'s counters: not read on this system.
#[cfg(not(windows))]
pub fn usage() -> Option<[u64; 3]> {
    None
}

/// The memory this process holds in RAM, in bytes.
#[cfg(any(target_os = "linux", target_os = "android"))]
pub fn resident_bytes() -> Option<u64> {
    let statm = std::fs::read_to_string("/proc/self/statm").ok()?;
    let pages: u64 = statm.split_whitespace().nth(1)?.parse().ok()?;
    // SAFETY: reads one system constant.
    let page = unsafe { libc::sysconf(libc::_SC_PAGESIZE) };
    Some(pages * u64::try_from(page).ok()?)
}

/// The first part of `task_vm_info` (`<mach/task_info.h>`), up to and including
/// `phys_footprint`: revision 1, which every OS version that has `TASK_VM_INFO` fills in.
/// Later revisions only append, so asking for this many words is stable.
#[cfg(target_vendor = "apple")]
#[repr(C)]
#[derive(Clone, Copy)]
struct TaskVmInfo {
    virtual_size: u64,
    region_count: i32,
    page_size: i32,
    resident_size: u64,
    resident_size_peak: u64,
    device: u64,
    device_peak: u64,
    internal: u64,
    internal_peak: u64,
    external: u64,
    external_peak: u64,
    reusable: u64,
    reusable_peak: u64,
    purgeable_volatile_pmap: u64,
    purgeable_volatile_resident: u64,
    purgeable_volatile_virtual: u64,
    compressed: u64,
    compressed_peak: u64,
    compressed_lifetime: u64,
    phys_footprint: u64,
}

// The offsets and size the iOS 18.5 SDK reports for `task_vm_info_data_t`
// (`offsetof`, and `TASK_VM_INFO_REV1_COUNT` = 38 words = 152 bytes).
#[cfg(target_vendor = "apple")]
const _: () = {
    assert!(std::mem::offset_of!(TaskVmInfo, resident_size) == 16);
    assert!(std::mem::offset_of!(TaskVmInfo, internal) == 48);
    assert!(std::mem::offset_of!(TaskVmInfo, compressed) == 120);
    assert!(std::mem::offset_of!(TaskVmInfo, phys_footprint) == 144);
    assert!(std::mem::size_of::<TaskVmInfo>() == 152);
};

/// `TASK_VM_INFO`, and `TASK_VM_INFO_REV1_COUNT` (the size above in 32-bit words).
#[cfg(target_vendor = "apple")]
const TASK_VM_INFO: libc::task_flavor_t = 22;
#[cfg(target_vendor = "apple")]
const TASK_VM_INFO_REV1_COUNT: libc::mach_msg_type_number_t = 38;

/// This process's virtual memory counters, from the kernel.
#[cfg(target_vendor = "apple")]
fn task_vm_info() -> Option<TaskVmInfo> {
    unsafe extern "C" {
        // What `<mach/mach_init.h>`'s `mach_task_self()` macro reads: the calling process's
        // task port. `libc` declares it for macOS only, and deprecated.
        static mach_task_self_: libc::mach_port_t;
    }
    // SAFETY: all-zero is a valid `TaskVmInfo` (plain integers). `task_info` writes at most
    // `count` 32-bit words into it, and `count` is its size in words; the task port of the
    // calling process is set before `main` and needs no releasing.
    unsafe {
        let mut info: TaskVmInfo = std::mem::zeroed();
        let mut count = TASK_VM_INFO_REV1_COUNT;
        let status = libc::task_info(
            mach_task_self_,
            TASK_VM_INFO,
            (&raw mut info).cast(),
            &mut count,
        );
        (status == 0 && count >= TASK_VM_INFO_REV1_COUNT).then_some(info)
    }
}

/// The memory this process holds in RAM, in bytes.
#[cfg(target_vendor = "apple")]
pub fn resident_bytes() -> Option<u64> {
    Some(task_vm_info()?.resident_size)
}

/// The process's physical footprint, in bytes: the figure iOS and macOS charge a process
/// for (Xcode's memory gauge, and what the system weighs when it ends an app for memory).
/// It counts dirty and compressed memory and memory graphics drivers hold for the process,
/// which the resident size misses, and leaves out clean pages that can be dropped.
#[cfg(target_vendor = "apple")]
pub fn footprint_bytes() -> Option<u64> {
    Some(task_vm_info()?.phys_footprint)
}

/// How much more memory this app may use before the system ends it, in bytes
/// (`os_proc_available_memory`, iOS 13 and later). A moving figure: it shrinks as the app
/// and the other apps grow.
#[cfg(target_os = "ios")]
pub fn available_bytes() -> Option<u64> {
    unsafe extern "C" {
        fn os_proc_available_memory() -> usize;
    }
    // SAFETY: a call with no arguments that reads a kernel counter.
    let bytes = unsafe { os_proc_available_memory() };
    // It returns 0 when the limit cannot be known (an app with no memory limit, the simulator).
    (bytes != 0).then_some(bytes as u64)
}

/// The footprint, where this system has a counter for it.
#[cfg(not(target_vendor = "apple"))]
pub fn footprint_bytes() -> Option<u64> {
    None
}

/// How much more memory this app may use: only iOS says.
#[cfg(not(target_os = "ios"))]
pub fn available_bytes() -> Option<u64> {
    None
}

/// The memory this process holds in RAM, in bytes: not known on this system.
#[cfg(not(any(
    windows,
    target_os = "linux",
    target_os = "android",
    target_vendor = "apple"
)))]
pub fn resident_bytes() -> Option<u64> {
    None
}

#[cfg(all(test, any(windows, target_os = "linux", target_vendor = "apple")))]
mod tests {
    use super::*;

    #[cfg(target_vendor = "apple")]
    #[test]
    fn touched_memory_counts_in_the_footprint() {
        const SIZE: usize = 256 << 20;
        let before = footprint_bytes().unwrap();
        let block = vec![1u8; SIZE];
        let during = footprint_bytes().unwrap();
        std::hint::black_box(&block);
        assert!(
            during >= before + SIZE as u64 / 2,
            "{before} then {during} bytes"
        );
        drop(block);
    }

    #[cfg(target_vendor = "apple")]
    #[test]
    fn the_footprint_is_a_plausible_size() {
        let footprint = footprint_bytes().unwrap();
        // More than a megabyte, and not past the machine's address space: catches a misread struct.
        assert!((1 << 20..1 << 44).contains(&footprint), "{footprint}");
    }

    #[test]
    fn touched_memory_counts_as_resident() {
        const SIZE: usize = 256 << 20;
        let before = resident_bytes().unwrap();
        let block = vec![1u8; SIZE];
        let during = resident_bytes().unwrap();
        std::hint::black_box(&block);
        assert!(
            during >= before + SIZE as u64 / 2,
            "{before} then {during} bytes"
        );
    }
}
