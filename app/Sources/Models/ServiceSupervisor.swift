import Foundation

/// Spawns and supervises the sidecar + tunneld subprocesses for the app's
/// lifetime. Tunneld goes via `sudo -n`, which requires the sudoers entry
/// installed by `make sudoers-install`.
final class ServiceSupervisor: @unchecked Sendable {
    private let lock = NSLock()
    private var sidecar: Process?
    private var tunneld: Process?

    private let repoDir: String
    private let pythonPath: String
    private let logDir: String

    init() {
        let home = NSHomeDirectory()
        let envRepo = ProcessInfo.processInfo.environment["GPSMOCK_REPO"]
        let repo = envRepo ?? "\(home)/worksapce/gps"
        self.repoDir = repo
        self.pythonPath = "\(repo)/sidecar/.venv/bin/python"
        self.logDir = "\(home)/Library/Logs/GPSMock"
        try? FileManager.default.createDirectory(
            atPath: logDir, withIntermediateDirectories: true)
    }

    private func logHandle(_ name: String) -> FileHandle {
        let path = "\(logDir)/\(name)"
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        if let h = FileHandle(forWritingAtPath: path) {
            _ = try? h.seekToEnd()
            return h
        }
        return FileHandle.nullDevice
    }

    func start() {
        spawnTunneld()
        spawnSidecar()
    }

    func stop() {
        lock.lock()
        let s = sidecar
        let t = tunneld
        sidecar = nil
        tunneld = nil
        lock.unlock()
        s?.terminate()
        t?.terminate()
    }

    private func spawnSidecar() {
        lock.lock()
        guard sidecar == nil else { lock.unlock(); return }
        lock.unlock()

        let p = Process()
        p.executableURL = URL(fileURLWithPath: pythonPath)
        p.arguments = ["-m", "gpsmock_sidecar"]
        p.currentDirectoryURL = URL(fileURLWithPath: repoDir)
        p.standardOutput = logHandle("sidecar.log")
        p.standardError = logHandle("sidecar.err")
        try? p.run()

        lock.lock()
        sidecar = p
        lock.unlock()
    }

    private func spawnTunneld() {
        lock.lock()
        guard tunneld == nil else { lock.unlock(); return }
        lock.unlock()

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        // -n: non-interactive. Requires the sudoers entry for this exact command.
        p.arguments = ["-n", pythonPath, "-m", "pymobiledevice3", "remote", "tunneld"]
        p.standardOutput = logHandle("tunneld.log")
        p.standardError = logHandle("tunneld.err")
        try? p.run()

        lock.lock()
        tunneld = p
        lock.unlock()
    }
}
