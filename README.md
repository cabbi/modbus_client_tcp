# Introduction
This is a set of three packages implementing Modbus Client sending requests to a remote device (i.e. Modbus Server).

- [Modbus Client](https://pub.dev/packages/modbus_client) is the base implementation for the **TCP** and **Serial** packages.
- [Modbus Client TCP](https://pub.dev/packages/modbus_client_tcp) implements the **TCP** protocol to send requests via **ethernet networks**.
- [Modbus Client Serial](https://pub.dev/packages/modbus_client_serial) implements the **ASCII** and **RTU** protocols to send requests via **Serial Port**


The split of the packages is done to minimize dependencies on your project.

# Usage

Using modbus client is simple. You define your elements, create a read or write request out of them and use the client to send the request. 

## Read Request

```dart
import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';

void main() async {
  // Create a modbus int16 register element
  var batteryTemperature = ModbusInt16Register(
      name: "BatteryTemperature",
      type: ModbusElementType.inputRegister,
      address: 22,
      uom: "°C",
      multiplier: 0.1,
      onUpdate: (self) => print(self));

  // Create the modbus client.
  var modbusClient = ModbusClientTcp("127.0.0.1", unitId: 1);

  // Send a read request from the element
  await modbusClient.send(batteryTemperature.getReadRequest());

  // Ending here
  modbusClient.disconnect();
}
```

## Write Request

```dart
import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';

enum BatteryStatus implements ModbusIntEnum {
  offline(0),
  standby(1),
  running(2),
  fault(3),
  sleepMode(4);

  const BatteryStatus(this.intValue);

  @override
  final int intValue;

  @override
  String toString() {
    return name;
  }
}

void main() async {
  var batteryStatus = ModbusEnumRegister(
      name: "BatteryStatus",
      address: 11,
      type: ModbusElementType.holdingRegister,
      enumValues: BatteryStatus.values,
      onUpdate: (self) => print(self));

  var modbusClient = ModbusClientTcp("127.0.0.1", unitId: 1);

  var req = batteryStatus.getWriteRequest(BatteryStatus.running);
  var res = await modbusClient.send(req);
  print(res.name);

  modbusClient.disconnect();
}
```

# Modbus Elements

This library has a wide range of defined modbus elements having a __name__, a __description__, a modbus __address__ and an __update callback__ you can use in case the element value has been updated. 

## Bit and Numeric Elements

Typical elements are simple bit and numeric values:
- **ModbusDiscreteInput**
- **ModbusCoil**
- **ModbusInt16Register**
- **ModbusUint16Register**
- **ModbusInt32Register**
- **ModbusUint32Register**

Numeric elements have an **uom** (i.e. unit of measure), a **multiplier** and **offset** to make conversion from raw to engineering values (i.e. value = read_value*multiplier + offset), and **viewDecimalPlaces** to print out only needed decimals.

## Enum Element
To read and write an enum as an element you can use a **ModbusEnumRegister**

```dart
/// Implement [ModbusIntEnum] to use it with a [ModbusEnumRegister]
enum BatteryStatus implements ModbusIntEnum {
  offline(0),
  standby(1),
  running(2),
  fault(3),
  sleepMode(4);

  const BatteryStatus(this.intValue);

  @override
  final int intValue;

  @override
  String toString() {
    return name;
  }
}


void main() async {
  ModbusAppLogger(Level.FINEST);

  var batteryStatus = ModbusEnumRegister(
      name: "BatteryStatus",
      address: 11,
      type: ModbusElementType.holdingRegister,
      enumValues: BatteryStatus.values);

  var modbusClient = ModbusClientTcp("127.0.0.1", unitId: 1);
  await modbusClient.send(batteryStatus.getReadRequest());
  modbusClient.disconnect();
}
```

## Status Element

Similar to enum is a status element. Within a **ModbusStatusRegister** you can define all the possible statues (i.e. numeric <-> string pairs) for the element.

```dart
ModbusStatusRegister(
    name: "Device status",
    type: ModbusElementType.holdingRegister,
    address: 32089,
    statusValues: [
      ModbusStatus(0x0000, "Standby: initializing"),
      ModbusStatus(0x0001, "Standby: detecting insulation resistance"),
      ModbusStatus(0x0002, "Standby: detecting irradiation"),
      ModbusStatus(0x0003, "Standby: drid detecting"),
      ModbusStatus(0x0100, "Starting"),
      ModbusStatus(0x0200, "On-grid (Off-grid mode: running)"),
      ModbusStatus(0x0201,
          "Grid connection: power limited (Off-grid mode: running: power limited)"),
      ModbusStatus(0x0202,
          "Grid connection: selfderating (Off-grid mode: running: selfderating)"),
      ModbusStatus(0x0203, "Off-grid Running"),
      ModbusStatus(0x0300, "Shutdown: fault"),
      ModbusStatus(0x0301, "Shutdown: command"),
      ModbusStatus(0x0302, "Shutdown: OVGR"),
      ModbusStatus(0x0303, "Shutdown: communication disconnected"),
      ModbusStatus(0x0304, "Shutdown: power limited"),
      ModbusStatus(0x0305, "Shutdown: manual startup required"),
      ModbusStatus(0x0306, "Shutdown: DC switches disconnected"),
      ModbusStatus(0x0307, "Shutdown: rapid cutoff"),
      ModbusStatus(0x0308, "Shutdown: input underpower"),
      ModbusStatus(0x0401, "Grid scheduling: cosφ-P curve"),
      ModbusStatus(0x0402, "Grid scheduling: Q-U curve"),
      ModbusStatus(0x0403, "Grid scheduling: PF-U curve"),
      ModbusStatus(0x0404, "Grid scheduling: dry contact"),
      ModbusStatus(0x0405, "Grid scheduling: Q-P curve"),
      ModbusStatus(0x0500, "Spotcheck ready"),
      ModbusStatus(0x0501, "Spotchecking"),
      ModbusStatus(0x0600, "Inspecting"),
      ModbusStatus(0X0700, "AFCI self check"),
      ModbusStatus(0X0800, "I-V scanning"),
      ModbusStatus(0X0900, "DC input detection"),
      ModbusStatus(0X0A00, "Running: off-grid charging"),
      ModbusStatus(0xA000, "Standby: no irradiation"),
    ]),
```

## Bit Mask Element

Use **ModbusBitMaskRegister** if your device has registers where each bit value has a special meaning. You can define both an active and inactive value for each **ModbusBitMask** object.

```dart
ModbusBitMaskRegister(
    name: "Alarm 1",
    type: ModbusElementType.holdingRegister,
    address: 32008,
    bitMasks: [
      ModbusBitMask(0, "High String Input Voltage [2001 Major]"),
      ModbusBitMask(1, "DC Arc Fault [2002 Major]"),
      ModbusBitMask(2, "String Reverse Connection [2011 Major]"),
      ModbusBitMask(3, "String Current Backfeed [2012 Warning]"),
      ModbusBitMask(4, "Abnormal String Power [2013 Warning]"),
      ModbusBitMask(5, "AFCI Self-Check Fail. [2021 Major]"),
      ModbusBitMask(6, "Phase Wire Short-Circuited to PE [2031 Major]"),
      ModbusBitMask(7, "Grid Loss [2032 Major]"),
      ModbusBitMask(8, "Grid Undervoltage [2033 Major]"),
      ModbusBitMask(9, "Grid Overvoltage [2034 Major]"),
      ModbusBitMask(10, "Grid Volt. Imbalance [2035 Major]"),
      ModbusBitMask(11, "Grid Overfrequency [2036 Major]"),
      ModbusBitMask(12, "Grid Underfrequency [2037 Major]"),
      ModbusBitMask(13, "Unstable Grid Frequency [2038 Major]"),
      ModbusBitMask(14, "Output Overcurrent [2039 Major]"),
      ModbusBitMask(15, "Output DC Component Overhigh [2040 Major]"),
    ]),
```

## Epoch/DateTime Element

Use **ModbusEpochRegister** if your device holds timestamp values as epoch.
The epoch might be represented both in seconds or milliseconds.

``` dart
ModbusEpochRegister(
    name: "Startup time",
    type: ModbusElementType.holdingRegister,
    address: 32091,
    epochType: ModbusEpochType.seconds,
    isUtc: false);
```

## Element Group

You can define a **ModbusElementsGroup** to optimize the elements reading.
The most the element addresses are contiguous the most performant is the request. The address range limit for bits is 2000 and 125 for registers.
You can use the **ModbusElementsGroup** object as a kind of list of element.

``` dart
import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';

enum BatteryStatus implements ModbusIntEnum {
  offline(0),
  standby(1),
  running(2),
  fault(3),
  sleepMode(4);

  const BatteryStatus(this.intValue);

  @override
  final int intValue;
}

void main() async {
  // Create a modbus elements group
  var batteryRegs = ModbusElementsGroup([
    ModbusEnumRegister(
        name: "BatteryStatus",
        type: ModbusElementType.holdingRegister,
        address: 37000,
        enumValues: BatteryStatus.values),
    ModbusInt32Register(
        name: "BatteryChargingPower",
        type: ModbusElementType.holdingRegister,
        address: 37001,
        uom: "W",
        description: "> 0: charging - < 0: discharging"),
    ModbusUint16Register(
        name: "BatteryCharge",
        type: ModbusElementType.holdingRegister,
        address: 37004,
        uom: "%",
        multiplier: 0.1),
    ModbusUint16Register(
        name: "BatteryTemperature",
        type: ModbusElementType.holdingRegister,
        address: 37022,
        uom: "°C",
        multiplier: 0.1),
  ]);

  // Create the modbus client.
  var modbusClient = ModbusClientTcp("127.0.0.1", unitId: 1);

  // Send a read request from the group
  await modbusClient.send(batteryRegs.getReadRequest());
  print(batteryRegs[0]);
  print(batteryRegs[1]);
  print(batteryRegs[2]);
  print(batteryRegs[3]);

  // Ending here
  modbusClient.disconnect();
}
```
