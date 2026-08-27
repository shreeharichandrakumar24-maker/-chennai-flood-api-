import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

class FloodMapScreen extends StatefulWidget {
  const FloodMapScreen({super.key});

  @override
  State<FloodMapScreen> createState() => _FloodMapScreenState();
}

class _FloodMapScreenState extends State<FloodMapScreen> {
  final MapController _mapController = MapController();
  String _selectedLayer = 'inundation_zones';
  Position? _currentPosition;
  bool _locationLoading = false;
  String? _locationError;

  // Chennai center
  static const LatLng _chennaiCenter = LatLng(13.0827, 80.2707);

  final List<Map<String, dynamic>> _floodZones = [
    // High-risk zones (demo data - replace with real KML data)
    {'name': 'T. Nagar', 'lat': 13.0410, 'lng': 80.2340, 'risk': 'HIGH'},
    {'name': 'Adyar', 'lat': 13.0062, 'lng': 80.2574, 'risk': 'HIGH'},
    {'name': 'Velachery', 'lat': 12.9815, 'lng': 80.2180, 'risk': 'HIGH'},
    {'name': 'Chromepet', 'lat': 12.9516, 'lng': 80.1416, 'risk': 'MODERATE'},
    {'name': 'Anna Nagar', 'lat': 13.0850, 'lng': 80.2100, 'risk': 'MODERATE'},
    {'name': 'Mylapore', 'lat': 13.0340, 'lng': 80.2700, 'risk': 'LOW'},
    {'name': 'Tondiarpet', 'lat': 13.1100, 'lng': 80.2700, 'risk': 'HIGH'},
    {'name': 'Sholinganallur', 'lat': 12.9010, 'lng': 80.2270, 'risk': 'MODERATE'},
  ];

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    if (!mounted) return;
    setState(() {
      _locationLoading = true;
      _locationError = null;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        setState(() {
          _locationError = 'Location services are disabled.';
          _locationLoading = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (!mounted) return;
          setState(() {
            _locationError = 'Location permission denied.';
            _locationLoading = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() {
          _locationError = 'Location permissions permanently denied.';
          _locationLoading = false;
        });
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (!mounted) return;
      setState(() {
        _currentPosition = position;
        _locationLoading = false;
      });

      // Move map to current location
      _mapController.move(
        LatLng(position.latitude, position.longitude),
        14.0,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _locationError = 'Failed to get location: $e';
        _locationLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🗺️ Flood Risk Map'),
        actions: [
          // Location button
          IconButton(
            icon: _locationLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location),
            onPressed: _getCurrentLocation,
            tooltip: 'My Location',
          ),
          PopupMenuButton<String>(
            onSelected: (value) => setState(() => _selectedLayer = value),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'inundation_zones', child: Text('Risk Zones')),
              const PopupMenuItem(value: 'shelters', child: Text('Shelters')),
              const PopupMenuItem(value: 'both', child: Text('Both')),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _chennaiCenter,
              initialZoom: 12.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.chennai_flood',
              ),
              MarkerLayer(markers: _buildMarkers()),
            ],
          ),

          // Location error banner
          if (_locationError != null)
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange.shade700, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _locationError!,
                          style: TextStyle(
                            color: Colors.orange.shade900,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _locationError = null),
                        child: Icon(Icons.close, size: 16, color: Colors.orange.shade700),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Legend
          Positioned(
            bottom: 16,
            left: 16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Legend', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    _legendItem(Colors.red, 'HIGH Risk'),
                    _legendItem(Colors.orange, 'MODERATE Risk'),
                    _legendItem(Colors.green, 'LOW Risk'),
                    _legendItem(Colors.teal, 'Shelter'),
                    if (_currentPosition != null)
                      _legendItem(Colors.blue, 'Your Location'),
                  ],
                ),
              ),
            ),
          ),

          // Zoom controls
          Positioned(
            bottom: 16,
            right: 16,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'zoom_in',
                  onPressed: () {
                    final currentZoom = _mapController.camera.zoom;
                    _mapController.move(
                      _mapController.camera.center,
                      currentZoom + 1,
                    );
                  },
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'zoom_out',
                  onPressed: () {
                    final currentZoom = _mapController.camera.zoom;
                    _mapController.move(
                      _mapController.camera.center,
                      currentZoom - 1,
                    );
                  },
                  child: const Icon(Icons.remove),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    // Current location marker
    if (_currentPosition != null) {
      markers.add(
        Marker(
          point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          width: 40,
          height: 40,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withValues(alpha: 0.4),
                  blurRadius: 8,
                ),
              ],
            ),
            child: const Icon(Icons.person, color: Colors.white, size: 20),
          ),
        ),
      );
    }

    if (_selectedLayer == 'inundation_zones' || _selectedLayer == 'both') {
      for (final zone in _floodZones) {
        markers.add(
          Marker(
            point: LatLng((zone['lat'] as num).toDouble(), (zone['lng'] as num).toDouble()),
            width: 40,
            height: 40,
            child: GestureDetector(
              onTap: () => _showZoneInfo(zone),
              child: Container(
                decoration: BoxDecoration(
                  color: _getRiskColor(zone['risk']),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(Icons.location_on, color: Colors.white, size: 20),
              ),
            ),
          ),
        );
      }
    }

    if (_selectedLayer == 'shelters' || _selectedLayer == 'both') {
      final shelters = [
        {'name': 'Teynampet Relief Camp', 'lat': 13.0350, 'lng': 80.2450},
        {'name': 'Anna Nagar Community Hall', 'lat': 13.0850, 'lng': 80.2100},
        {'name': 'Adyar Relief Center', 'lat': 13.0010, 'lng': 80.2570},
        {'name': 'Velachery Relief Camp', 'lat': 12.9815, 'lng': 80.2180},
      ];

      for (final shelter in shelters) {
        markers.add(
          Marker(
            point: LatLng((shelter['lat'] as num).toDouble(), (shelter['lng'] as num).toDouble()),
            width: 40,
            height: 40,
            child: GestureDetector(
              onTap: () => _showShelterInfo(shelter),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.teal,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(Icons.home, color: Colors.white, size: 20),
              ),
            ),
          ),
        );
      }
    }

    return markers;
  }

  Widget _legendItem(Color color, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Color _getRiskColor(String risk) {
    switch (risk) {
      case 'HIGH':
        return Colors.red;
      case 'MODERATE':
        return Colors.orange;
      default:
        return Colors.green;
    }
  }

  void _showZoneInfo(Map<String, dynamic> zone) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(zone['name'], style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Chip(
              label: Text(zone['risk']),
              backgroundColor: _getRiskColor(zone['risk']).withValues(alpha: 0.2),
            ),
            const SizedBox(height: 8),
            Text('Coordinates: ${zone['lat']}, ${zone['lng']}'),
          ],
        ),
      ),
    );
  }

  void _showShelterInfo(Map<String, dynamic> shelter) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(shelter['name'], style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Chip(
              label: Text('🏠 Emergency Shelter'),
              backgroundColor: Colors.teal,
              labelStyle: TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 8),
            const Text('Demo/prototype location for UI development'),
          ],
        ),
      ),
    );
  }
}
