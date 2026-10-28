#include "T300USB.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/usb/IOUSBLib.h>
#include <mach/mach_error.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

enum {
    t300VendorID = 0x044f,
    genericProductID = 0xb65d,
    nativeProductID = 0xb66e,
};

static const UInt8 preparationPackets[][9] = {
    {0x42, 0x01, 0, 0, 0, 0, 0, 0, 0},
    {0x0a, 0x04, 0x90, 0x03, 0, 0, 0, 0, 0},
    {0x0a, 0x04, 0x00, 0x0c, 0, 0, 0, 0, 0},
    {0x0a, 0x04, 0x12, 0x10, 0, 0, 0, 0, 0},
    {0x0a, 0x04, 0x00, 0x06, 0, 0, 0, 0, 0},
};
static const UInt32 preparationPacketLengths[] = {9, 8, 8, 8, 8};

static void setMessage(char *message, size_t capacity, const char *format, ...) {
    if (message == NULL || capacity == 0) return;
    va_list arguments;
    va_start(arguments, format);
    vsnprintf(message, capacity, format, arguments);
    va_end(arguments);
}

static UInt16 registryNumber(io_service_t service, CFStringRef key) {
    CFTypeRef property = IORegistryEntryCreateCFProperty(
        service,
        key,
        kCFAllocatorDefault,
        0
    );
    if (property == NULL) return 0;
    SInt32 value = 0;
    if (CFGetTypeID(property) == CFNumberGetTypeID()) {
        CFNumberGetValue((CFNumberRef)property, kCFNumberSInt32Type, &value);
    }
    CFRelease(property);
    return (UInt16)value;
}

static UInt32 registryLocation(io_service_t service) {
    CFTypeRef property = IORegistryEntryCreateCFProperty(
        service,
        CFSTR("locationID"),
        kCFAllocatorDefault,
        0
    );
    if (property == NULL) return 0;
    SInt32 value = 0;
    if (CFGetTypeID(property) == CFNumberGetTypeID()) {
        CFNumberGetValue((CFNumberRef)property, kCFNumberSInt32Type, &value);
    }
    CFRelease(property);
    return (UInt32)value;
}

static IOReturn findTargetDevice(
    io_service_t *genericService,
    UInt32 *genericCount,
    bool *nativePresent,
    bool *unsupportedPresent
) {
    *genericService = IO_OBJECT_NULL;
    *genericCount = 0;
    *nativePresent = false;
    *unsupportedPresent = false;

    CFMutableDictionaryRef matching = IOServiceMatching("IOUSBDevice");
    if (matching == NULL) return kIOReturnNoMemory;
    io_iterator_t iterator = IO_OBJECT_NULL;
    IOReturn result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator);
    if (result != kIOReturnSuccess) return result;

    io_service_t service;
    while ((service = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
        UInt16 vendor = registryNumber(service, CFSTR("idVendor"));
        UInt16 product = registryNumber(service, CFSTR("idProduct"));
        if (vendor == t300VendorID) {
            if (product == genericProductID) {
                (*genericCount)++;
                if (*genericService == IO_OBJECT_NULL) {
                    *genericService = service;
                    continue;
                }
            } else if (product == nativeProductID) {
                *nativePresent = true;
            } else if (product == 0xb66d || product == 0xb66f) {
                *unsupportedPresent = true;
            }
        }
        IOObjectRelease(service);
    }
    IOObjectRelease(iterator);
    return kIOReturnSuccess;
}

static IOReturn createDeviceInterface(
    io_service_t service,
    IOUSBDeviceInterface650 ***device
) {
    IOCFPlugInInterface **plugin = NULL;
    SInt32 score = 0;
    IOReturn result = IOCreatePlugInInterfaceForService(
        service,
        kIOUSBDeviceUserClientTypeID,
        kIOCFPlugInInterfaceID,
        &plugin,
        &score
    );
    if (plugin == NULL) return result;
    if (result != kIOReturnSuccess) {
        (*plugin)->Release(plugin);
        return result;
    }

    HRESULT queryResult = (*plugin)->QueryInterface(
        plugin,
        CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID650),
        (LPVOID *)device
    );
    (*plugin)->Release(plugin);
    return (IOReturn)queryResult;
}

static IOReturn createInterface(
    io_service_t service,
    IOUSBInterfaceInterface800 ***interface
) {
    IOCFPlugInInterface **plugin = NULL;
    SInt32 score = 0;
    IOReturn result = IOCreatePlugInInterfaceForService(
        service,
        kIOUSBInterfaceUserClientTypeID,
        kIOCFPlugInInterfaceID,
        &plugin,
        &score
    );
    if (plugin == NULL) return result;
    if (result != kIOReturnSuccess) {
        (*plugin)->Release(plugin);
        return result;
    }

    HRESULT queryResult = (*plugin)->QueryInterface(
        plugin,
        CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID800),
        (LPVOID *)interface
    );
    (*plugin)->Release(plugin);
    return (IOReturn)queryResult;
}

static IOReturn ensureConfiguration(IOUSBDeviceInterface650 **device) {
    UInt8 activeConfiguration = 0;
    IOReturn result = (*device)->GetConfiguration(device, &activeConfiguration);
    if (result == kIOReturnSuccess && activeConfiguration != 0) return kIOReturnSuccess;
    if (result != kIOReturnSuccess && result != kIOReturnNotFound) return result;

    UInt8 configurationCount = 0;
    result = (*device)->GetNumberOfConfigurations(device, &configurationCount);
    if (result != kIOReturnSuccess) return result;
    for (UInt8 index = 0; index < configurationCount; index++) {
        IOUSBConfigurationDescriptorPtr descriptor = NULL;
        result = (*device)->GetConfigurationDescriptorPtr(device, index, &descriptor);
        if (result == kIOReturnSuccess && descriptor != NULL) {
            return (*device)->SetConfiguration(device, descriptor->bConfigurationValue);
        }
    }
    return kIOReturnNotFound;
}

static IOReturn findInterruptOutput(
    IOUSBDeviceInterface650 **device,
    IOUSBInterfaceInterface800 ***selectedInterface,
    UInt8 *selectedPipe,
    UInt16 *selectedPacketSize,
    char *diagnostic,
    size_t diagnosticCapacity
) {
    IOUSBFindInterfaceRequest request = {
        .bInterfaceClass = kIOUSBFindInterfaceDontCare,
        .bInterfaceSubClass = kIOUSBFindInterfaceDontCare,
        .bInterfaceProtocol = kIOUSBFindInterfaceDontCare,
        .bAlternateSetting = kIOUSBFindInterfaceDontCare,
    };
    io_iterator_t iterator = IO_OBJECT_NULL;
    IOReturn result;
    result = (*device)->CreateInterfaceIterator(device, &request, &iterator);
    if (result != kIOReturnSuccess) {
        setMessage(diagnostic, diagnosticCapacity, "CreateInterfaceIterator: %s", mach_error_string(result));
        return result;
    }

    UInt32 interfaceCount = 0;
    UInt32 openedCount = 0;
    UInt32 endpointCount = 0;
    IOReturn lastOpenError = kIOReturnNotFound;
    io_service_t service;
    while ((service = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
        interfaceCount++;
        IOUSBInterfaceInterface800 **interface = NULL;
        result = createInterface(service, &interface);
        IOObjectRelease(service);
        if (result != kIOReturnSuccess || interface == NULL) {
            lastOpenError = result;
            continue;
        }

        result = (*interface)->USBInterfaceOpen(interface);
        if (result != kIOReturnSuccess) {
            lastOpenError = result;
            (*interface)->Release(interface);
            continue;
        }
        openedCount++;

        UInt8 interfaceEndpointCount = 0;
        result = (*interface)->GetNumEndpoints(interface, &interfaceEndpointCount);
        if (result == kIOReturnSuccess) {
            endpointCount += interfaceEndpointCount;
            for (UInt8 pipe = 1; pipe <= interfaceEndpointCount; pipe++) {
                UInt8 direction = 0;
                UInt8 number = 0;
                UInt8 transferType = 0;
                UInt8 interval = 0;
                UInt16 packetSize = 0;
                result = (*interface)->GetPipeProperties(
                    interface,
                    pipe,
                    &direction,
                    &number,
                    &transferType,
                    &packetSize,
                    &interval
                );
                if (result == kIOReturnSuccess && direction == 0 && transferType == 3) {
                    *selectedInterface = interface;
                    *selectedPipe = pipe;
                    *selectedPacketSize = packetSize;
                    IOObjectRelease(iterator);
                    return kIOReturnSuccess;
                }
            }
        }

        (*interface)->USBInterfaceClose(interface);
        (*interface)->Release(interface);
    }
    IOObjectRelease(iterator);
    if (interfaceCount == 0) {
        setMessage(diagnostic, diagnosticCapacity, "No interfaces matched the active USB configuration");
    } else if (openedCount == 0) {
        if (lastOpenError == kIOReturnExclusiveAccess) {
            setMessage(
                diagnostic,
                diagnosticCapacity,
                "macOS HID driver owns the T300 interface; a privileged helper is required"
            );
        } else {
            setMessage(
                diagnostic,
                diagnosticCapacity,
                "Could not open any of %u interfaces: %s",
                interfaceCount,
                mach_error_string(lastOpenError)
            );
        }
        return lastOpenError;
    } else {
        setMessage(
            diagnostic,
            diagnosticCapacity,
            "Opened %u interfaces and found %u endpoints, but none was an interrupt OUT endpoint",
            openedCount,
            endpointCount
        );
    }
    return kIOReturnNotFound;
}

static IOReturn controlRequest(
    IOUSBDeviceInterface650 **device,
    UInt8 requestType,
    UInt8 request,
    UInt16 value,
    void *data,
    UInt16 length,
    UInt32 *transferred
) {
    IOUSBDevRequestTO usbRequest = {
        .bmRequestType = requestType,
        .bRequest = request,
        .wValue = value,
        .wIndex = 0,
        .wLength = length,
        .pData = data,
        .wLenDone = 0,
        .noDataTimeout = 2000,
        .completionTimeout = 2000,
    };
    IOReturn result = (*device)->DeviceRequestTO(device, &usbRequest);
    if (transferred != NULL) *transferred = usbRequest.wLenDone;
    return result;
}

typedef struct {
    bool complete;
    IOReturn result;
} InterruptWriteResult;

static void interruptWriteCompleted(void *refcon, IOReturn result, void *arg0) {
    (void)arg0;
    InterruptWriteResult *writeResult = (InterruptWriteResult *)refcon;
    writeResult->result = result;
    writeResult->complete = true;
    CFRunLoopStop(CFRunLoopGetCurrent());
}

static IOReturn writeInterruptPacket(
    IOUSBInterfaceInterface800 **interface,
    UInt8 pipe,
    const UInt8 *packet,
    UInt32 length
) {
    InterruptWriteResult writeResult = {false, kIOReturnSuccess};
    IOReturn result = (*interface)->WritePipeAsync(
        interface,
        pipe,
        (void *)packet,
        length,
        interruptWriteCompleted,
        &writeResult
    );
    if (result != kIOReturnSuccess) return result;

    while (!writeResult.complete) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 1.0, true);
    }
    return writeResult.result;
}

static bool supportedModelResponse(const UInt8 *response, UInt32 length) {
    if (length < 8) return false;
    UInt16 responseType = (UInt16)response[0] | ((UInt16)response[1] << 8);
    if (responseType != 0x0049 && responseType != 0x0047) return false;
    if (responseType == 0x0049 && length < 16) return false;
    UInt16 model = (UInt16)response[6] | ((UInt16)response[7] << 8);
    return model == 0x0204 || model == 0x0206 || model == 0x0209 || model == 0x020a;
}

static bool nativeModeAtLocation(UInt32 location) {
    CFMutableDictionaryRef matching = IOServiceMatching("IOUSBDevice");
    if (matching == NULL) return false;
    io_iterator_t iterator = IO_OBJECT_NULL;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) != kIOReturnSuccess) {
        return false;
    }

    bool found = false;
    io_service_t service;
    while ((service = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
        if (registryNumber(service, CFSTR("idVendor")) == t300VendorID &&
            registryNumber(service, CFSTR("idProduct")) == nativeProductID &&
            registryLocation(service) == location) {
            found = true;
        }
        IOObjectRelease(service);
        if (found) break;
    }
    IOObjectRelease(iterator);
    return found;
}

int t300_initialize(char *message, size_t message_capacity) {
    io_service_t service = IO_OBJECT_NULL;
    UInt32 genericCount = 0;
    bool nativePresent = false;
    bool unsupportedPresent = false;
    IOReturn result = findTargetDevice(
        &service,
        &genericCount,
        &nativePresent,
        &unsupportedPresent
    );
    if (result != kIOReturnSuccess) {
        setMessage(message, message_capacity, "USB scan failed: %s", mach_error_string(result));
        return 0;
    }
    if (genericCount == 0) {
        if (nativePresent) {
            setMessage(message, message_capacity, "T300 is already in PS3 / PC mode");
            return 2;
        }
        setMessage(
            message,
            message_capacity,
            unsupportedPresent
                ? "Set the T300 switch to PS3 / PC, reconnect it, and retry"
                : "No generic T300 found; connect the wheel in PS3 / PC mode"
        );
        return 0;
    }
    if (genericCount != 1) {
        IOObjectRelease(service);
        setMessage(message, message_capacity, "Connect exactly one generic T300 at a time");
        return 0;
    }

    UInt32 location = registryLocation(service);
    IOUSBDeviceInterface650 **device = NULL;
    result = createDeviceInterface(service, &device);
    IOObjectRelease(service);
    if (result != kIOReturnSuccess || device == NULL) {
        setMessage(message, message_capacity, "Could not open the T300 USB interface: %s", mach_error_string(result));
        return 0;
    }

    bool deviceOpened = false;
    bool switchRequested = false;
    IOUSBInterfaceInterface800 **interface = NULL;
    CFRunLoopSourceRef interfaceEventSource = NULL;
    UInt8 outputPipe = 0;
    UInt16 outputPacketSize = 0;
    result = (*device)->USBDeviceOpenSeize(device);
    if (result == kIOReturnSuccess) deviceOpened = true;
    if (result == kIOReturnSuccess) {
        result = (*device)->USBDeviceReEnumerate(device, kUSBReEnumerateCaptureDeviceMask);
        if (result != kIOReturnSuccess) {
            setMessage(message, message_capacity, "Could not capture the T300 from macOS HID: %s", mach_error_string(result));
        } else {
            (*device)->USBDeviceClose(device);
            deviceOpened = false;
            result = (*device)->USBDeviceOpenSeize(device);
            if (result == kIOReturnSuccess) deviceOpened = true;
            else setMessage(message, message_capacity, "Could not reopen the captured T300: %s", mach_error_string(result));
        }
    }
    if (result == kIOReturnSuccess) {
        result = ensureConfiguration(device);
        if (result != kIOReturnSuccess) {
            setMessage(message, message_capacity, "Could not activate the T300 USB configuration: %s", mach_error_string(result));
        }
    }
    if (result == kIOReturnSuccess) {
        char diagnostic[256] = {0};
        result = findInterruptOutput(
            device,
            &interface,
            &outputPipe,
            &outputPacketSize,
            diagnostic,
            sizeof(diagnostic)
        );
        if (result != kIOReturnSuccess) {
            setMessage(message, message_capacity, "%s", diagnostic);
        }
    }
    if (result != kIOReturnSuccess) {
        goto cleanup;
    }

    result = (*interface)->CreateInterfaceAsyncEventSource(interface, &interfaceEventSource);
    if (result != kIOReturnSuccess) {
        setMessage(message, message_capacity, "Could not create the interrupt event source: %s", mach_error_string(result));
        goto cleanup;
    }
    CFRunLoopAddSource(CFRunLoopGetCurrent(), interfaceEventSource, kCFRunLoopDefaultMode);

    for (size_t index = 0; index < sizeof(preparationPackets) / sizeof(preparationPackets[0]); index++) {
        result = writeInterruptPacket(
            interface,
            outputPipe,
            preparationPackets[index],
            preparationPacketLengths[index]
        );
        if (result != kIOReturnSuccess) {
            setMessage(
                message,
                message_capacity,
                "Preparation packet %u (%u bytes; endpoint max %u) failed: %s",
                (unsigned int)index,
                preparationPacketLengths[index],
                outputPacketSize,
                mach_error_string(result)
            );
            goto cleanup;
        }
    }

    UInt8 modelResponse[16] = {0};
    UInt32 responseLength = 0;
    result = controlRequest(device, 0xc1, 73, 0, modelResponse, sizeof(modelResponse), &responseLength);
    if (result != kIOReturnSuccess || !supportedModelResponse(modelResponse, responseLength)) {
        if (result == kIOReturnSuccess) {
            setMessage(message, message_capacity, "T300 model response was invalid; mode was not changed");
        } else {
            setMessage(message, message_capacity, "Could not verify the T300 model: %s", mach_error_string(result));
        }
        goto cleanup;
    }

    switchRequested = true;
    result = controlRequest(device, 0x41, 83, 0x0005, NULL, 0, NULL);
    if (result != kIOReturnSuccess && result != kIOReturnNoDevice &&
        result != kIOReturnNotResponding && result != kIOReturnAborted &&
        result != kIOUSBPipeStalled) {
        switchRequested = false;
        setMessage(message, message_capacity, "Could not request native USB mode: %s", mach_error_string(result));
        goto cleanup;
    }

cleanup:
    if (interfaceEventSource != NULL) {
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), interfaceEventSource, kCFRunLoopDefaultMode);
        CFRelease(interfaceEventSource);
    }
    if (interface != NULL) {
        (*interface)->USBInterfaceClose(interface);
        (*interface)->Release(interface);
    }
    if (deviceOpened) (*device)->USBDeviceClose(device);
    (*device)->Release(device);

    if (!switchRequested) return 0;
    if (location == 0) {
        setMessage(message, message_capacity, "Mode-switch requested; USB location could not be verified");
        return 0;
    }
    for (unsigned int attempt = 0; attempt < 40; attempt++) {
        if (nativeModeAtLocation(location)) {
            setMessage(message, message_capacity, "T300 initialized in PS3 / PC mode");
            return 1;
        }
        usleep(250000);
    }
    setMessage(message, message_capacity, "Mode switch was not confirmed; check the physical switch and retry");
    return 0;
}