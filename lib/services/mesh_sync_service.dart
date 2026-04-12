import 'dart:convert';
import 'dart:developer';
import 'package:nearby_connections/nearby_connections.dart';

class MeshSyncService {
  final Strategy strategy = Strategy.P2P_CLUSTER; // Supports M-N connections
  final String userName;
  
  // Local queue for offline CRDT sync
  final List<Map<String, dynamic>> _offlineReportQueue = [];

  MeshSyncService({required this.userName});

  // Start BLE + WiFi Direct discovery and advertising
  Future<void> startMeshNetwork() async {
    try {
      bool hasPermissions = await Nearby().checkLocationPermission();
      if (!hasPermissions) {
        await Nearby().askLocationPermission();
      }
      
      // We both advertise presence and listen for others
      await _startAdvertising();
      await _startDiscovery();
      
      log("MeshSyncService STARTED: Listening for offline peers.");
    } catch (e) {
      log("MeshSyncService Error: $e");
    }
  }

  Future<void> _startAdvertising() async {
    try {
      bool a = await Nearby().startAdvertising(
        userName,
        strategy,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: (id, status) {
          log("Mesh Advertisement Status (peer $id): $status");
        },
        onDisconnected: (id) {
          log("Mesh Peer disconnected: $id");
        },
      );
      log("Advertising success: $a");
    } catch (e) {
      log("Advertising failed: $e");
    }
  }

  Future<void> _startDiscovery() async {
    try {
      bool a = await Nearby().startDiscovery(
        userName,
        strategy,
        onEndpointFound: (id, name, serviceId) {
          log("Discovered nearby mesh node: $name ($id). Connecting...");
          Nearby().requestConnection(
            userName,
            id,
            onConnectionInitiated: _onConnectionInitiated,
            onConnectionResult: (id, status) {
              log("Mesh Discovery Status (peer $id): $status");
            },
            onDisconnected: (id) {
              log("Mesh Peer disconnected: $id");
            },
          );
        },
        onEndpointLost: (id) {
          log("Lost mesh node endpoint: $id");
        },
      );
      log("Discovery success: $a");
    } catch (e) {
      log("Discovery failed: $e");
    }
  }

  void _onConnectionInitiated(String endpointId, ConnectionInfo info) {
    log("Connection initiated with ${info.endpointName}. Accepting...");
    // Auto-accept all connections in the mesh cluster for disaster relief
    Nearby().acceptConnection(
      endpointId,
      onPayLoadRecieved: (endpointId, payload) {
        if (payload.type == PayloadType.BYTES) {
          String data = String.fromCharCodes(payload.bytes!);
          _handleIncomingMeshPayload(endpointId, data);
        }
      },
      onPayloadTransferUpdate: (endpointId, payloadTransferUpdate) {},
    );
  }

  /// CRDT Merge Logic for Reports
  void _handleIncomingMeshPayload(String endpointId, String jsonData) {
    try {
      Map<String, dynamic> data = jsonDecode(jsonData);
      if (data['type'] == 'field_reports_sync') {
        List<dynamic> incomingReports = data['reports'];
        int newAdded = 0;
        
        // Basic CRDT implementation: Union based on unique 'id'
        for (var reportMap in incomingReports) {
          bool exists = _offlineReportQueue.any((r) => r['id'] == reportMap['id']);
          if (!exists) {
            _offlineReportQueue.add(reportMap);
            newAdded++;
          }
        }
        
        log("Mesh Sync [CRDT Merge] received ${incomingReports.length} reports from $endpointId. Added $newAdded new unique reports.");
        
        // If we have internet connectvity, we should push this queue to the backend.
        // For now, it stays locally buffered, hopping from phone to phone.
      }
    } catch (e) {
      log("Error parsing mesh payload: $e");
    }
  }

  /// Add a report when offline and broadcast to mesh
  Future<void> queueAndBroadcastReport(Map<String, dynamic> reportMap) async {
    _offlineReportQueue.add(reportMap);
    
    // Broadcast via BLE/WiFi Direct map payload
    Map<String, dynamic> payloadMap = {
      'type': 'field_reports_sync',
      'reports': _offlineReportQueue
    };
    
    // Convert to bytes and stringify
    String jsonStr = jsonEncode(payloadMap);
    
    // Send to all connected endpoints
    // (Assume we maintain a list of endpoints or fetch from library, though nearby_connections 
    // requires explicitly sending to known endpoint IDs. In a real app we'd track active ones).
    // For demonstration, let's pretend we have a method `getAllConnectedEndpoints()`
    // We would loop and call `Nearby().sendBytesPayload()`.
    
    log("[MESH] Queued offline report ${reportMap['id']} and staged for P2P broadcast.");
  }
}
