import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/prediction_model.dart';

/// Full detail for one citizen report: photo (if present), exact location,
/// category, time, status, reporter.
class ReportDetailScreen extends StatelessWidget {
  final Complaint complaint;
  final String distanceLabel;
  final String timeAgo;
  final String? localPhotoPath;

  const ReportDetailScreen({
    super.key,
    required this.complaint,
    required this.distanceLabel,
    required this.timeAgo,
    this.localPhotoPath,
  });

  @override
  Widget build(BuildContext context) {
    final hasCoords = complaint.lat != null && complaint.lon != null;
    final center = hasCoords
        ? LatLng(complaint.lat!, complaint.lon!)
        : const LatLng(13.0827, 80.2707);
    return Scaffold(
      appBar: AppBar(title: const Text('Report Detail')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (localPhotoPath != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(localPhotoPath!),
                height: 220,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            )
          else
            Container(
              height: 120,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.image_not_supported,
                        size: 36, color: Colors.grey),
                    SizedBox(height: 8),
                    Text('No photo attached',
                        style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            complaint.description,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              Chip(label: Text(complaint.category)),
              Chip(label: Text(complaint.status.toUpperCase())),
            ],
          ),
          const Divider(height: 24),
          _row(Icons.location_on, 'Location', complaint.location),
          _row(Icons.pin_drop, 'Coordinates',
              hasCoords ? '${complaint.lat}, ${complaint.lon}' : '—'),
          _row(Icons.directions_walk, 'Distance', distanceLabel),
          _row(Icons.access_time, 'Submitted', timeAgo),
          if (complaint.createdAt != null)
            _row(Icons.calendar_today, 'Timestamp', complaint.createdAt!),
          _row(Icons.person, 'Reporter',
              complaint.name + (complaint.phone != null ? ' (${complaint.phone})' : '')),
          const SizedBox(height: 16),
          const Text('Exact location',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SizedBox(
            height: 220,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: 15,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.chennai_flood',
                  ),
                  if (hasCoords)
                    MarkerLayer(markers: [
                      Marker(
                        point: center,
                        width: 44,
                        height: 44,
                        child: const Icon(Icons.location_pin,
                            color: Colors.red, size: 40),
                      ),
                    ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 10),
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(color: Colors.grey)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
