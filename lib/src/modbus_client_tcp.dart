import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:modbus_client/modbus_client.dart';
import 'package:synchronized/synchronized.dart';

/// The Modbus TCP client class.
class ModbusClientTcp extends ModbusClient {
  final String serverAddress;
  final int serverPort;
  final Duration connectionTimeout;
  final Duration? delayAfterConnect;

  @override
  bool get isConnected => _socket != null;

  int _lastTransactionId = 0;
  Socket? _socket;
  final Lock _lock = Lock();
  _TcpResponse? _currentResponse;

  ModbusClientTcp(this.serverAddress,
      {this.serverPort = 502,
      super.connectionMode = ModbusConnectionMode.autoConnectAndKeepConnected,
      this.connectionTimeout = const Duration(seconds: 3),
      super.responseTimeout = const Duration(seconds: 3),
      this.delayAfterConnect,
      super.unitId});

  /// This is an easy server address discovery.
  ///
  /// The discovery starts from the fourth digit of the [startIpAddress] and
  /// only checks address of fourth digit.
  /// Example:
  ///   // This checks addresses from '192.168.0.10' to '192.168.0.255'
  ///   var serverAddress = await ModbusClientTcp.discover("192.168.0.10");
  static Future<String?> discover(String startIpAddress,
      {int serverPort = 502,
      Duration connectionTimeout = const Duration(milliseconds: 10)}) async {
    var serverAddress = InternetAddress.tryParse(startIpAddress);
    if (serverAddress == null) {
      throw ModbusException(
          context: "ModbusClientTcp.discover",
          msg: "[$startIpAddress] Invalid address!");
    }
    for (var i = serverAddress.rawAddress[3]; i < 256; i++) {
      var ip = serverAddress!.rawAddress;
      ip[3] = i;
      serverAddress = InternetAddress.fromRawAddress(ip);
      try {
        var socket = await Socket.connect(serverAddress, serverPort,
            timeout: connectionTimeout);
        socket.destroy();
        ModbusAppLogger.finest(
            "[${serverAddress.address}] Modbus server found!");
        return serverAddress.address;
      } catch (_) {}
    }
    ModbusAppLogger.finest("[$startIpAddress] Modbus server not found!");
    return null;
  }

  @override
  Future<ModbusResponseCode> send(ModbusRequest request) async {
    var res = await _lock.synchronized(() async {
      // Connect if needed
      try {
        if (connectionMode != ModbusConnectionMode.doNotConnect) {
          await connect();
        }
        if (!isConnected) {
          return ModbusResponseCode.connectionFailed;
        }
      } catch (ex) {
        ModbusAppLogger.severe(
            "Unexpected exception in sending TCP message", ex);
        return ModbusResponseCode.connectionFailed;
      }

      // Create the new response handler
      var transactionId = _lastTransactionId++;
      _currentResponse = _TcpResponse(request,
          transactionId: transactionId, timeout: getResponseTimeout(request));

      // Reset this request in case it was already used before
      request.reset();

      // Create request data
      int pduLen = request.protocolDataUnit.length;
      var header = Uint8List(pduLen + 7);
      ByteData.view(header.buffer)
        ..setUint16(0, transactionId) // Transaction ID
        ..setUint16(2, 0) // Protocol ID = 0
        ..setUint16(4, pduLen + 1) // PDU Length + Unit ID byte
        ..setUint8(6, getUnitId(request)); // Unit ID
      header.setAll(7, request.protocolDataUnit);

      // Send the request data
      _socket!.add(header);

      // Wait for the response code
      return await request.responseCode;
    });
    // Need to disconnect?
    if (connectionMode == ModbusConnectionMode.autoConnectAndDisconnect) {
      await disconnect();
    }
    return res;
  }

  /// Connect the socket if not already done or disconnected
  @override
  Future<bool> connect() async {
    if (isConnected) {
      return true;
    }
    ModbusAppLogger.fine("Connecting TCP socket...");
    // New connection
    _socket = await Socket.connect(serverAddress, serverPort,
        timeout: connectionTimeout);
    // listen to the received data event stream
    _socket!.listen((Uint8List data) {
      _onSocketData(data);
    },
        onError: (error) => _onSocketError(error),
        onDone: () => disconnect(),
        cancelOnError: true);

    // Is a delay requested?
    if (delayAfterConnect != null) {
      await Future.delayed(delayAfterConnect!);
    }
    ModbusAppLogger.fine("TCP socket${isConnected ? " " : " not "}connected");
    return isConnected;
  }

  /// Handle received data from the socket
  void _onSocketData(Uint8List data) {
    _currentResponse!.addResponseData(data);
  }

  /// Handle an error from the socket
  void _onSocketError(dynamic error) {
    ModbusAppLogger.severe("Unexpected error from TCP socket", error);
    disconnect();
  }

  /// Handle socket being closed
  @override
  Future<void> disconnect() async {
    ModbusAppLogger.fine("Disconnecting TCP socket...");
    if (_socket != null) {
      _socket!.destroy();
      _socket = null;
    }
  }
}

class _TcpResponse {
  final ModbusRequest request;
  final int transactionId;
  final Duration timeout;

  final Completer _timeout = Completer();
  List<int> _data = Uint8List(0);
  int? _resDataLen;

  _TcpResponse(this.request,
      {required this.timeout, required this.transactionId}) {
    _timeout.future.timeout(timeout, onTimeout: () {
      request.setResponseCode(ModbusResponseCode.requestTimeout);
    });
  }

  void addResponseData(Uint8List data) {
    _data += data;
    // Still need the TCP header?
    if (_resDataLen == null && _data.length >= 6) {
      var resView = ByteData.view(Uint8List.fromList(_data).buffer, 0, 6);
      if (transactionId != resView.getUint16(0)) {
        ModbusAppLogger.warning("Invalid TCP transaction id",
            "$transactionId != ${resView.getUint16(0)}");
        _timeout.complete();
        request.setResponseCode(ModbusResponseCode.requestRxFailed);
        return;
      }
      if (0 != resView.getUint16(2)) {
        ModbusAppLogger.warning(
            "Invalid TCP transaction id", "${resView.getUint16(2) != 0}");
        _timeout.complete();
        request.setResponseCode(ModbusResponseCode.requestRxFailed);
        return;
      }
      _resDataLen = resView.getUint16(4);
    }
    // Got all data
    if (_resDataLen != null && _data.length >= _resDataLen!) {
      _timeout.complete();
      request.setFromPduResponse(data.sublist(7));
    }
  }
}
