import CoreAudio
import Testing
@testable import audioctrl

// MARK: - fourCC

@Suite("fourCC") struct FourCCTests {
    @Test func printableASCII() {
        #expect(fourCC(0x6D737274) == "'msrt'")
    }

    @Test func nonPrintableFallsBackToHex() {
        #expect(fourCC(0x00000001) == "0x00000001")
    }

    @Test func edgeCaseAllSpaces() {
        // 0x20202020 = four spaces — printable ASCII, should format as FourCC
        #expect(fourCC(0x20202020) == "'    '")
    }
}

// MARK: - parseSelector

@Suite("parseSelector") struct ParseSelectorTests {
    @Test func fourCharCode() {
        #expect(parseSelector("nsrt") == 0x6E737274)
    }

    @Test func hexPrefix() {
        #expect(parseSelector("0x6E737274") == 0x6E737274)
        #expect(parseSelector("0X6E737274") == 0x6E737274)
    }

    @Test func decimal() {
        #expect(parseSelector("1853059700") == 0x6E737274)
    }

    @Test func tooShortReturnsNil() {
        #expect(parseSelector("abc") == nil)
    }

    @Test func tooLongReturnsNil() {
        #expect(parseSelector("abcde") == nil)
    }

    @Test func invalidHexReturnsNil() {
        #expect(parseSelector("0xZZZZ") == nil)
    }
}

// MARK: - transportTypeName

@Suite("transportTypeName") struct TransportTypeNameTests {
    @Test func knownTypes() {
        #expect(transportTypeName(kAudioDeviceTransportTypeBuiltIn)     == "Built-in")
        #expect(transportTypeName(kAudioDeviceTransportTypeBluetooth)   == "Bluetooth")
        #expect(transportTypeName(kAudioDeviceTransportTypeBluetoothLE) == "Bluetooth LE")
        #expect(transportTypeName(kAudioDeviceTransportTypeUSB)         == "USB")
        #expect(transportTypeName(kAudioDeviceTransportTypeVirtual)     == "Virtual")
        #expect(transportTypeName(kAudioDeviceTransportTypeAggregate)   == "Aggregate")
        #expect(transportTypeName(kAudioDeviceTransportTypeHDMI)        == "HDMI")
        #expect(transportTypeName(kAudioDeviceTransportTypeAirPlay)     == "AirPlay")
        #expect(transportTypeName(kAudioDeviceTransportTypeContinuityCaptureWired)    == "Continuity (Wired)")
        #expect(transportTypeName(kAudioDeviceTransportTypeContinuityCaptureWireless) == "Continuity (Wireless)")
    }

    @Test func unknownFallsBackToHex() {
        #expect(transportTypeName(0xDEADBEEF) == "0xDEADBEEF")
    }
}

// MARK: - transportSortOrder

@Suite("transportSortOrder") struct TransportSortOrderTests {
    @Test func ordering() {
        let builtIn   = transportSortOrder(kAudioDeviceTransportTypeBuiltIn)
        let bluetooth = transportSortOrder(kAudioDeviceTransportTypeBluetooth)
        let usb       = transportSortOrder(kAudioDeviceTransportTypeUSB)
        let hdmi      = transportSortOrder(kAudioDeviceTransportTypeHDMI)
        let virtual   = transportSortOrder(kAudioDeviceTransportTypeVirtual)
        let aggregate = transportSortOrder(kAudioDeviceTransportTypeAggregate)
        let unknown   = transportSortOrder(0xDEADBEEF)

        #expect(builtIn < bluetooth)
        #expect(bluetooth < usb)
        #expect(usb < hdmi)
        #expect(hdmi < virtual)
        #expect(virtual < aggregate)
        #expect(aggregate < unknown)
    }

    @Test func bluetoothVariantsHaveSameOrder() {
        #expect(transportSortOrder(kAudioDeviceTransportTypeBluetooth)
             == transportSortOrder(kAudioDeviceTransportTypeBluetoothLE))
        #expect(transportSortOrder(kAudioDeviceTransportTypeBluetooth)
             == transportSortOrder(kAudioDeviceTransportTypeContinuityCaptureWired))
    }

    @Test func hdmiVariantsHaveSameOrder() {
        #expect(transportSortOrder(kAudioDeviceTransportTypeHDMI)
             == transportSortOrder(kAudioDeviceTransportTypeDisplayPort))
        #expect(transportSortOrder(kAudioDeviceTransportTypeHDMI)
             == transportSortOrder(kAudioDeviceTransportTypeThunderbolt))
    }
}

// MARK: - AudioObjectPropertyScope

@Suite("AudioObjectPropertyScope") struct ScopeTests {
    @Test func fromValidStrings() throws {
        #expect(try AudioObjectPropertyScope.from("global") == kAudioObjectPropertyScopeGlobal)
        #expect(try AudioObjectPropertyScope.from("input")  == kAudioObjectPropertyScopeInput)
        #expect(try AudioObjectPropertyScope.from("output") == kAudioObjectPropertyScopeOutput)
    }

    @Test func fromShortForms() throws {
        #expect(try AudioObjectPropertyScope.from("g") == kAudioObjectPropertyScopeGlobal)
        #expect(try AudioObjectPropertyScope.from("i") == kAudioObjectPropertyScopeInput)
        #expect(try AudioObjectPropertyScope.from("o") == kAudioObjectPropertyScopeOutput)
    }

    @Test func fromCaseInsensitive() throws {
        #expect(try AudioObjectPropertyScope.from("INPUT")  == kAudioObjectPropertyScopeInput)
        #expect(try AudioObjectPropertyScope.from("Output") == kAudioObjectPropertyScopeOutput)
    }

    @Test func fromInvalidThrows() {
        #expect(throws: (any Error).self) { try AudioObjectPropertyScope.from("sideways") }
    }

    @Test func valueProperty() {
        #expect(kAudioObjectPropertyScopeGlobal.value == "global")
        #expect(kAudioObjectPropertyScopeInput.value  == "input")
        #expect(kAudioObjectPropertyScopeOutput.value == "output")
    }
}

// MARK: - AudioClassID.controlClassName

@Suite("controlClassName") struct ControlClassNameTests {
    @Test func knownClasses() {
        #expect(kAudioVolumeControlClassID.controlClassName    == "volume")
        #expect(kAudioMuteControlClassID.controlClassName      == "mute")
        #expect(kAudioStereoPanControlClassID.controlClassName == "stereo-pan")
        #expect(kAudioClockSourceControlClassID.controlClassName == "clock-source")
    }

    @Test func unknownFallsBackToFourCC() {
        // kAudioDeviceClassID is not a control class — should format as FourCC
        #expect(kAudioDeviceClassID.controlClassName == fourCC(kAudioDeviceClassID))
    }
}

// MARK: - CoreAudio constant assumptions
//
// These tests document and verify our assumptions about CoreAudio FourCC values.
// A failure here means either Apple changed a constant (very unlikely) or we used
// the wrong code somewhere in the codebase.

@Suite("CoreAudio constants") struct CoreAudioConstantTests {
    @Test func propertySelectorFourCCs() {
        #expect(fourCC(kAudioDevicePropertyNominalSampleRate) == "'nsrt'")
        #expect(fourCC(kAudioDevicePropertyBufferFrameSize)   == "'fsiz'")
        #expect(fourCC(kAudioDevicePropertyTransportType)     == "'tran'")
        #expect(fourCC(kAudioDevicePropertyDeviceIsRunning)   == "'goin'")
        #expect(fourCC(kAudioDevicePropertyIsHidden)          == "'hidn'")
        #expect(fourCC(kAudioObjectPropertyName)              == "'lnam'")
        #expect(fourCC(kAudioDevicePropertyDeviceUID)         == "'uid '")
    }

    @Test func controlScopeSelector() {
        // kAudioControlPropertyScopeSelector is not exported by CoreAudio headers
        // so we hardcode it in defs.swift. Verify our value matches 'cscp'.
        #expect(fourCC(kAudioControlPropertyScopeSelector) == "'cscp'")
    }

    @Test func transportTypeValues() {
        #expect(fourCC(kAudioDeviceTransportTypeBuiltIn)   == "'bltn'")
        #expect(fourCC(kAudioDeviceTransportTypeBluetooth) == "'blue'")
        #expect(fourCC(kAudioDeviceTransportTypeUSB)       == "'usb '")
        #expect(fourCC(kAudioDeviceTransportTypeVirtual)   == "'virt'")
        #expect(fourCC(kAudioDeviceTransportTypeAggregate) == "'grup'")
    }

    @Test func selectorRoundTrip() {
        // parseSelector("nsrt") must produce kAudioDevicePropertyNominalSampleRate
        #expect(parseSelector("nsrt") == kAudioDevicePropertyNominalSampleRate)
        #expect(parseSelector("tran") == kAudioDevicePropertyTransportType)
        #expect(parseSelector("fsiz") == kAudioDevicePropertyBufferFrameSize)
    }
}

// MARK: - ljust / rjust

@Suite("Formatting") struct FormattingTests {
    @Test func ljustPads() {
        #expect(ljust("hi", 5) == "hi   ")
    }

    @Test func ljustExactFit() {
        #expect(ljust("hi", 2) == "hi")
    }

    @Test func ljustTruncates() {
        #expect(ljust("hello", 3) == "hel")
    }

    @Test func rjustPads() {
        #expect(rjust("hi", 5) == "   hi")
    }

    @Test func rjustExactFit() {
        #expect(rjust("hi", 2) == "hi")
    }

    @Test func rjustNoTruncation() {
        // rjust does not truncate — longer strings pass through
        #expect(rjust("hello", 3) == "hello")
    }
}
