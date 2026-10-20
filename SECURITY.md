# Security

## Reporting a vulnerability

Please report vulnerabilities privately through GitHub: open the repository's **Security** tab and
choose **Report a vulnerability**. Do not open a public issue. You will get a reply within a week.

## What runs with elevated privileges

macOS only lets administrators read the CPU time of processes owned by other users (such as
`WindowServer` or `kernel_task`). To show a system-wide top-10 list, the installer adds a small
helper that runs as root:

| | |
|---|---|
| Binary | `/Library/PrivilegedHelperTools/io.github.arrrlo.macos-processor-monitor.helper` (root:wheel, 755) |
| Launchd job | `/Library/LaunchDaemons/io.github.arrrlo.macos-processor-monitor.helper.plist` |
| Lifetime | Started by launchd on the first request; exits after 30 s without requests |
| Interface | One XPC method on its Mach service: `topProcesses(limit)` |

Design decisions that keep the attack surface small:

- **Read-only, one method.** The helper reads the process table (`proc_listallpids`,
  `proc_pidinfo`) and returns PID, process name and CPU percentage for at most 50 processes. It
  writes nothing, runs no commands, opens no files or network connections, and takes no input
  other than an integer, which is clamped to 1–50.
- **Same information as `ps`.** Every local user can already see this through `ps` and `top`, so
  connections are not authenticated. Pinning the client's code signature would not add protection
  for ad-hoc signed builds anyway.
- **Not inside the app bundle.** A root daemon whose binary lives in `/Applications` could be
  swapped by any admin user without a password prompt. The helper and its plist are owned by root
  and not writable by other users.
- **No sandbox for the app.** The menu bar app needs `host_processor_info`, the HID temperature
  sensors, the SMC and the process table, which the App Sandbox blocks. It makes no network connections and
  stores a single preference (the refresh interval).

The temperature readings use the private `IOHIDEventSystemClient` API. It is read-only and needs no
special privileges. The GPU temperature comes from the AppleSMC user client, which any user may
open. The app only sends its read commands (list keys, key info, read a key), never a write.
