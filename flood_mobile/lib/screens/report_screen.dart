import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../models/prediction_model.dart';
import '../services/api_exception.dart';
import '../services/api_service.dart';
import '../services/photo_service.dart';
import '../widgets/error_state.dart';
import 'report_detail_screen.dart';

/// P4 citizen reporting — full flow on top of the existing
/// POST/GET /api/v1/complaints endpoints (no endpoint changes).
///
/// Spec categories (UI) → backend categories (wire) mapping keeps the
/// existing backend untouched:
///   Waterlogging → Waterlogging
///   Blocked road → Road closure
///   Damaged infrastructure → House/Property damage
///   Other → Other
class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _locationController = TextEditingController();
  final _descriptionController = TextEditingController();

  // P4 spec categories (UI).
  static const _uiCategories = [
    'Waterlogging',
    'Blocked road',
    'Damaged infrastructure',
    'Other',
  ];
  static const _toBackend = {
    'Waterlogging': 'Waterlogging',
    'Blocked road': 'Road closure',
    'Damaged infrastructure': 'House/Property damage',
    'Other': 'Other',
  };

  String _uiCategory = 'Waterlogging';
  bool _submitting = false;
  String? _submitError;
  double _uploadProgress = 0;

  // Photo waiting for a (re)try upload after its report already exists on
  // the backend. Kept — together with the local file — so nothing is lost.
  int? _pendingPhotoReportId;
  bool _retryingPhoto = false;

  // Location: GPS default + manual pin on small map.
  Position? _position;
  LatLng? _pickedPin;
  String? _locationError;
  final MapController _miniMap = MapController();

  // Optional photo (local-only preview; backend row has no photo column,
  // so the file is kept in-session and shown in the detail view).
  XFile? _photo;
  final _picker = ImagePicker();
  final Map<int, String> _localPhotoPaths = {};

  List<Complaint> _complaints = [];
  bool _loadingComplaints = true;
  String? _listError;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadComplaints();
    _initGps();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _locationController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _initGps() async {
    try {
      bool enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (mounted) {
          setState(
              () => _locationError = 'Location services disabled — enter area manually.');
        }
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() =>
              _locationError = 'Location permission denied — enter area manually.');
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      setState(() {
        _position = pos;
        _pickedPin ??= LatLng(pos.latitude, pos.longitude);
        _locationController.text = _locationController.text.isEmpty
            ? '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}'
            : _locationController.text;
      });
      try {
        _miniMap.move(_pickedPin!, 14);
      } catch (_) {}
    } catch (e) {
      if (mounted) {
        setState(() => _locationError = 'GPS unavailable: $e');
      }
    }
  }

  Future<void> _loadComplaints() async {
    if (mounted) {
      setState(() {
        _loadingComplaints = true;
        _listError = null;
      });
    }
    try {
      final items = await ApiService.withRetry(
        () => ApiService.fetchComplaints(),
        label: 'reports/list',
      );
      if (!mounted) return;
      setState(() {
        _complaints = items; // backend returns most-recent-first
        _loadingComplaints = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingComplaints = false;
        _listError = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingComplaints = false;
        _listError = e.toString();
      });
    }
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final file = await _picker.pickImage(source: source, maxWidth: 1600);
      if (file != null && mounted) {
        setState(() => _photo = file);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Photo picker failed: $e')),
        );
      }
    }
  }

  Future<void> _submitReport() async {
    if (!_formKey.currentState!.validate()) return;
    if (mounted) {
      setState(() {
        _submitting = true;
        _submitError = null;
      });
    }
    final complaint = Complaint(
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim().isEmpty
          ? null
          : _phoneController.text.trim(),
      location: _locationController.text.trim(),
      lat: _pickedPin?.latitude ?? _position?.latitude,
      lon: _pickedPin?.longitude ?? _position?.longitude,
      category: _toBackend[_uiCategory] ?? 'Other',
      description: _descriptionController.text.trim(),
    );
    try {
      // Step 1 — text report FIRST (photo trouble can never block it).
      final created =
          await ApiService.withRetry(
        () => ApiService.submitComplaint(complaint),
        label: 'reports/submit',
      );
      // Step 2 — photo to Firebase, URL back to Render (both best-effort).
      String? photoMessage;
      if (_photo != null && created.id != null) {
        _localPhotoPaths[created.id!] = _photo!.path;
        if (PhotoService.isAvailable) {
          try {
            if (mounted) setState(() => _uploadProgress = 0);
            final url = await PhotoService.uploadReportPhoto(
              reportId: created.id!,
              localPath: _photo!.path,
              onProgress: (p) {
                if (mounted) setState(() => _uploadProgress = p);
              },
            );
            await ApiService.updateComplaintPhoto(created.id!, url);
            _localPhotoPaths.remove(created.id!);
            photoMessage = 'Photo uploaded ☁️';
          } catch (e) {
            // Report is SAFE on the backend; photo stays local for retry.
            if (mounted) {
              setState(() => _pendingPhotoReportId = created.id!);
            }
            photoMessage =
                'Report saved, but photo upload failed — retry below';
            debugPrint('[Report] photo step failed: $e');
          }
        } else {
          photoMessage = 'Report saved (photo kept on device — Firebase not configured)';
        }
      }
      if (!mounted) return;
      final hadPhoto = _photo != null;
      setState(() {
        _submitting = false;
        _uploadProgress = 0;
        if (_pendingPhotoReportId == null) _photo = null;
      });
      _nameController.clear();
      _phoneController.clear();
      _locationController.clear();
      _descriptionController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '✅ Report submitted${photoMessage != null ? ' — $photoMessage' : hadPhoto ? '!' : '!'}'),
            backgroundColor:
                _pendingPhotoReportId != null ? Colors.orange : Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
        _tabs.animateTo(1);
      }
      await _loadComplaints();
    } on ApiException catch (e) {
      // FAILURE: keep every entered field + photo so nothing is lost.
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = e.toString();
      });
    }
  }

  /// Retry a failed Firebase photo upload for an already-saved report.
  Future<void> _retryPendingPhoto() async {
    final reportId = _pendingPhotoReportId;
    final photo = _photo;
    if (reportId == null || photo == null || _retryingPhoto) return;
    if (mounted) {
      setState(() {
        _retryingPhoto = true;
        _submitError = null;
      });
    }
    try {
      final url = await PhotoService.uploadReportPhoto(
        reportId: reportId,
        localPath: photo.path,
      );
      await ApiService.updateComplaintPhoto(reportId, url);
      if (!mounted) return;
      setState(() {
        _retryingPhoto = false;
        _pendingPhotoReportId = null;
        _photo = null;
        _localPhotoPaths.remove(reportId);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Photo uploaded and attached!'),
            backgroundColor: Colors.green,
          ),
        );
      }
      await _loadComplaints();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _retryingPhoto = false;
        _submitError = 'Photo retry failed: $e';
      });
    }
  }

  String _timeAgo(String? iso) {
    if (iso == null || iso.isEmpty) return 'unknown time';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return iso;
    }
  }

  String _distanceLabel(Complaint c) {
    if (_position == null || c.lat == null || c.lon == null) {
      return 'distance unknown';
    }
    final m = Geolocator.distanceBetween(
      _position!.latitude,
      _position!.longitude,
      c.lat!,
      c.lon!,
    );
    if (m < 1000) return '${m.toStringAsFixed(0)} m away';
    return '${(m / 1000).toStringAsFixed(1)} km away';
  }

  IconData _categoryIcon(String backendCategory) {
    switch (backendCategory) {
      case 'Waterlogging':
        return Icons.water_drop;
      case 'Road closure':
        return Icons.block;
      case 'House/Property damage':
        return Icons.home_repair_service;
      case 'Drainage blocked':
        return Icons.plumbing;
      case 'Power outage':
        return Icons.power_off;
      case 'River/Storm surge':
        return Icons.waves;
      default:
        return Icons.report;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📋 Report Issue'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Submit Report'),
            Tab(text: 'Reports'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildForm(),
          _buildList(),
        ],
      ),
    );
  }

  Widget _buildForm() {
    final pin = _pickedPin ??
        (_position != null
            ? LatLng(_position!.latitude, _position!.longitude)
            : const LatLng(13.0827, 80.2707));
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_submitError != null) ...[
              ConnectionFailedBanner(
                message: _submitError!,
                onRetryNow: _submitting ? null : _submitReport,
              ),
              const SizedBox(height: 4),
              const Text(
                'Your entries were kept — fix the connection and tap "Retry now".',
                style: TextStyle(fontSize: 12, color: Colors.red),
              ),
              const SizedBox(height: 12),
            ],
            // Photo uploaded to Firebase later / retry card.
            if (_pendingPhotoReportId != null) ...[
              Card(
                color: Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.cloud_upload,
                          color: Colors.orange.shade800),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Report is saved on the server — only its photo still needs uploading.',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                      FilledButton(
                        onPressed:
                            _retryingPhoto ? null : _retryPendingPhoto,
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.orange),
                        child: Text(_retryingPhoto
                            ? 'Uploading…'
                            : 'Retry photo'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Your Name *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Name is required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'Phone (optional)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _locationController,
              decoration: const InputDecoration(
                labelText: 'Location / Area *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.location_on),
              ),
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'Location is required'
                  : null,
            ),
            if (_locationError != null) ...[
              const SizedBox(height: 6),
              Text(_locationError!,
                  style: const TextStyle(fontSize: 12, color: Colors.orange)),
            ],
            const SizedBox(height: 12),
            // Small map: GPS default pin, tap to adjust.
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Pin location (tap map to adjust)',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 180,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: FlutterMap(
                          mapController: _miniMap,
                          options: MapOptions(
                            initialCenter: pin,
                            initialZoom: 13,
                            onTap: (_, latLng) {
                              setState(() {
                                _pickedPin = latLng;
                                _locationController.text =
                                    '${latLng.latitude.toStringAsFixed(4)}, ${latLng.longitude.toStringAsFixed(4)}';
                              });
                            },
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName:
                                  'com.example.chennai_flood',
                            ),
                            MarkerLayer(markers: [
                              Marker(
                                point: pin,
                                width: 40,
                                height: 40,
                                child: const Icon(Icons.location_pin,
                                    color: Colors.red, size: 36),
                              ),
                            ]),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Lat: ${pin.latitude.toStringAsFixed(4)}, Lon: ${pin.longitude.toStringAsFixed(4)}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _uiCategory,
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.category),
              ),
              items: _uiCategories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _uiCategory = v!),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Short description * (max 200 chars)',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
                helperText: 'Required — what do you see?',
              ),
              maxLines: 3,
              maxLength: 200,
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Description is required';
                }
                if (v.trim().length > 200) {
                  return 'Max 200 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 8),
            // Optional photo.
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Photo (optional)',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    if (_photo != null)
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(_photo!.path),
                              height: 160,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            right: 4,
                            top: 4,
                            child: IconButton(
                              icon: const Icon(Icons.close,
                                  color: Colors.white),
                              style: IconButton.styleFrom(
                                  backgroundColor: Colors.black54),
                              onPressed: () =>
                                  setState(() => _photo = null),
                            ),
                          ),
                        ],
                      )
                    else
                      const Text('No photo attached.',
                          style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _submitting
                                ? null
                                : () => _pickPhoto(ImageSource.camera),
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('Camera'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _submitting
                                ? null
                                : () => _pickPhoto(ImageSource.gallery),
                            icon: const Icon(Icons.photo),
                            label: const Text('Gallery'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_submitting && _uploadProgress > 0) ...[
              Row(
                children: [
                  const Icon(Icons.cloud_upload,
                      size: 18, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LinearProgressIndicator(value: _uploadProgress),
                  ),
                  const SizedBox(width: 8),
                  Text(
                      'Photo ${(_uploadProgress * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(fontSize: 12)),
                ],
              ),
              const SizedBox(height: 12),
            ],
            FilledButton.icon(
              onPressed: _submitting ? null : _submitReport,
              icon: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: Text(_submitting ? 'Submitting...' : 'Submit Report'),
            ),
            const SizedBox(height: 8),
            Text(
              PhotoService.isAvailable
                  ? '☁️ Photos upload to Cloudinary; report text + location go to the Render backend.'
                  : '⚠️ Photo upload is unavailable on this build — reports submit as text-only.',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_loadingComplaints) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_listError != null && _complaints.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ConnectionFailedBanner(
            message: _listError!,
            onRetryNow: _loadComplaints,
          ),
          const SizedBox(height: 16),
          ErrorState(
            title: 'Could not load reports',
            message: '$_listError\n(Fetch failure — not an empty list.)',
            icon: Icons.cloud_off,
            onRetry: _loadComplaints,
          ),
        ],
      );
    }
    if (_complaints.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No reports submitted yet'),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadComplaints,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _complaints.length + (_listError != null ? 1 : 0),
        itemBuilder: (context, index) {
          if (_listError != null && index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ConnectionFailedBanner(
                message: 'Refresh failed: $_listError (showing cached list)',
                onRetryNow: _loadComplaints,
              ),
            );
          }
          final c = _complaints[_listError != null ? index - 1 : index];
          final photoPath =
              c.id != null ? _localPhotoPaths[c.id!] : null;
          return Card(
            child: ListTile(
              leading: _reportThumbnail(c, photoPath),
              title: Text(
                c.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${c.category} • ${_distanceLabel(c)} • ${_timeAgo(c.createdAt)}\n${c.location}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              isThreeLine: true,
              trailing: Chip(
                label: Text(c.status.toUpperCase()),
                backgroundColor:
                    _getStatusColor(c.status).withValues(alpha: 0.1),
                labelStyle: TextStyle(
                  fontSize: 10,
                  color: _getStatusColor(c.status),
                ),
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ReportDetailScreen(
                      complaint: c,
                      distanceLabel: _distanceLabel(c),
                      timeAgo: _timeAgo(c.createdAt),
                      localPhotoPath: photoPath,
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  /// Thumbnail: Firebase photo URL first (cloud, all devices), then the
  /// session-local file, then the category icon.
  Widget _reportThumbnail(Complaint c, String? photoPath) {
    if (c.photoUrl != null && c.photoUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          c.photoUrl!,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              Icon(_categoryIcon(c.category), color: _getStatusColor(c.status)),
        ),
      );
    }
    if (photoPath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(photoPath),
          width: 44,
          height: 44,
          fit: BoxFit.cover,
        ),
      );
    }
    return Icon(_categoryIcon(c.category),
        color: _getStatusColor(c.status));
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'resolved':
        return Colors.green;
      case 'in_progress':
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }
}
