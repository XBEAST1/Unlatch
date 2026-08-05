import Foundation
import AppKit
import CoreGraphics
import os

typealias MTDeviceRef = OpaquePointer
typealias MTContactCallbackFunction = @convention(c) (MTDeviceRef, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
typealias MTDeviceCreateDefaultFunction = @convention(c) () -> MTDeviceRef?
typealias MTDeviceCreateListFunction = @convention(c) () -> Unmanaged<CFArray>?
typealias MTRegisterContactFrameCallbackFunction = @convention(c) (MTDeviceRef, MTContactCallbackFunction) -> Int32
typealias MTDeviceStartFunction = @convention(c) (MTDeviceRef, Int32) -> Int32
typealias MTDeviceStopFunction = @convention(c) (MTDeviceRef) -> Int32

struct DeviceState {
    var device: MTDeviceRef
    var maxContacts: Int32
}

final class MultitouchEngine {
    static let shared = MultitouchEngine()

    private var multitouchHandle: UnsafeMutableRawPointer?
    private var deviceList: Unmanaged<CFArray>?

    private var registerCallback: MTRegisterContactFrameCallbackFunction?
    private var startDevice: MTDeviceStartFunction?
    private var stopDevice: MTDeviceStopFunction?

    private var isEnabled: Bool = true
    private var lastPostMillis: Int64 = 0
    private var lock = os_unfair_lock()
    private var deviceStates: [DeviceState] = []

    private init() {}

    func setEnabled(_ enabled: Bool) {
        os_unfair_lock_lock(&lock)
        isEnabled = enabled
        os_unfair_lock_unlock(&lock)
    }

    func getEnabled() -> Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return isEnabled
    }

    func start() -> Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return setupMultitouch()
    }

    func stop() {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        cleanup()
    }

    func reconnect() {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        cleanup()
        _ = setupMultitouch()
    }

    private func cleanup() {
        if let stopDevice = stopDevice {
            for state in deviceStates {
                _ = stopDevice(state.device)
            }
        }
        deviceStates.removeAll()

        if let deviceList = deviceList {
            deviceList.release()
            self.deviceList = nil
        }

        if let handle = multitouchHandle {
            dlclose(handle)
            self.multitouchHandle = nil
        }
    }

    private func setupMultitouch() -> Bool {
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/Versions/A/MultitouchSupport"
        guard let handle = dlopen(path, RTLD_LAZY) else {
            NSLog("[Unlatch] Failed to load MultitouchSupport: %s", dlerror())
            return false
        }
        self.multitouchHandle = handle

        guard let createDefaultSym = dlsym(handle, "MTDeviceCreateDefault"),
              let registerCallbackSym = dlsym(handle, "MTRegisterContactFrameCallback"),
              let startDeviceSym = dlsym(handle, "MTDeviceStart") else {
            NSLog("[Unlatch] Failed to resolve MultitouchSupport symbols")
            return false
        }

        let createDefault = unsafeBitCast(createDefaultSym, to: MTDeviceCreateDefaultFunction.self)
        let registerCallback = unsafeBitCast(registerCallbackSym, to: MTRegisterContactFrameCallbackFunction.self)
        let startDevice = unsafeBitCast(startDeviceSym, to: MTDeviceStartFunction.self)

        self.registerCallback = registerCallback
        self.startDevice = startDevice

        if let stopDeviceSym = dlsym(handle, "MTDeviceStop") {
            self.stopDevice = unsafeBitCast(stopDeviceSym, to: MTDeviceStopFunction.self)
        }

        var devices: [MTDeviceRef] = []

        if let createListSym = dlsym(handle, "MTDeviceCreateList") {
            let createList = unsafeBitCast(createListSym, to: MTDeviceCreateListFunction.self)
            if let listUnmanaged = createList() {
                self.deviceList = listUnmanaged
                let cfArray = listUnmanaged.takeUnretainedValue()
                let count = CFArrayGetCount(cfArray)
                for i in 0..<count {
                    if let ptr = CFArrayGetValueAtIndex(cfArray, i) {
                        let dev = unsafeBitCast(ptr, to: MTDeviceRef.self)
                        devices.append(dev)
                    }
                }
            }
        }

        if devices.isEmpty {
            if let defaultDev = createDefault() {
                devices.append(defaultDev)
            }
        }

        if devices.isEmpty {
            NSLog("[Unlatch] No multitouch devices detected.")
            return false
        }

        deviceStates = devices.map { DeviceState(device: $0, maxContacts: 0) }

        for dev in devices {
            _ = registerCallback(dev, globalContactFrameCallback)
            _ = startDevice(dev, 0)
        }

        NSLog("[Unlatch] Successfully started multitouch listener on %d device(s).", devices.count)
        return true
    }

    fileprivate func handleCallback(device: MTDeviceRef, contactCount: Int32) {
        os_unfair_lock_lock(&lock)

        guard isEnabled else {
            if let idx = deviceStates.firstIndex(where: { $0.device == device }) {
                deviceStates[idx].maxContacts = 0
            }
            os_unfair_lock_unlock(&lock)
            return
        }

        guard let idx = deviceStates.firstIndex(where: { $0.device == device }) else {
            os_unfair_lock_unlock(&lock)
            return
        }

        if contactCount > 0 {
            deviceStates[idx].maxContacts = max(deviceStates[idx].maxContacts, contactCount)
            os_unfair_lock_unlock(&lock)
            return
        }

        let shouldPost = (deviceStates[idx].maxContacts == 3)
        deviceStates[idx].maxContacts = 0

        if !shouldPost {
            os_unfair_lock_unlock(&lock)
            return
        }

        let now = Int64(CFAbsoluteTimeGetCurrent() * 1000.0)
        if now - lastPostMillis < 80 {
            os_unfair_lock_unlock(&lock)
            return
        }
        lastPostMillis = now
        os_unfair_lock_unlock(&lock)

        EventDispatcher.postLeftMouseUp()
    }
}

private func globalContactFrameCallback(device: MTDeviceRef, contacts: UnsafeMutableRawPointer?, contactCount: Int32, timestamp: Double, frame: Int32) -> Int32 {
    MultitouchEngine.shared.handleCallback(device: device, contactCount: contactCount)
    return 0
}
