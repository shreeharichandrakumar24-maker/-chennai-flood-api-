import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/prediction_model.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _locationController = TextEditingController();
  final _descriptionController = TextEditingController();

  String _category = 'Waterlogging';
  bool _submitting = false;
  List<Complaint> _complaints = [];
  bool _loadingComplaints = true;

  final List<String> _categories = [
    'Waterlogging',
    'Drainage blocked',
    'River/Storm surge',
    'Road closure',
    'House/Property damage',
    'Power outage',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _loadComplaints();
  }

  Future<void> _loadComplaints() async {
    setState(() => _loadingComplaints = true);
    final complaints = await ApiService.fetchComplaints();
    setState(() {
      _complaints = complaints;
      _loadingComplaints = false;
    });
  }

  Future<void> _submitReport() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);

    final complaint = Complaint(
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      location: _locationController.text.trim(),
      category: _category,
      description: _descriptionController.text.trim(),
    );

    final result = await ApiService.submitComplaint(complaint);

    setState(() => _submitting = false);

    if (result != null) {
      _formKey.currentState!.reset();
      _nameController.clear();
      _phoneController.clear();
      _locationController.clear();
      _descriptionController.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Report submitted successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      _loadComplaints();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Failed to submit report. Try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('📋 Report Issue'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Submit Report'),
              Tab(text: 'My Reports'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Submit Form
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Name
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Your Name *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Name is required' : null,
                    ),
                    const SizedBox(height: 12),

                    // Phone
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

                    // Location
                    TextFormField(
                      controller: _locationController,
                      decoration: const InputDecoration(
                        labelText: 'Location / Area *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.location_on),
                      ),
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Location is required' : null,
                    ),
                    const SizedBox(height: 12),

                    // Category
                    DropdownButtonFormField<String>(
                      initialValue: _category,
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.category),
                      ),
                      items: _categories
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) => setState(() => _category = v!),
                    ),
                    const SizedBox(height: 12),

                    // Description
                    TextFormField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Description *',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                      maxLines: 4,
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Description is required' : null,
                    ),
                    const SizedBox(height: 16),

                    // Submit Button
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
                    const Text(
                      '⚠️ This is a demo complaint system. In production, reports would be sent to the Greater Chennai Corporation.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),

            // My Reports
            _loadingComplaints
                ? const Center(child: CircularProgressIndicator())
                : _complaints.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inbox, size: 64, color: Colors.grey),
                            SizedBox(height: 16),
                            Text('No reports submitted yet'),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadComplaints,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _complaints.length,
                          itemBuilder: (context, index) {
                            final c = _complaints[index];
                            return Card(
                              child: ListTile(
                                leading: Icon(
                                  _getStatusIcon(c.status),
                                  color: _getStatusColor(c.status),
                                ),
                                title: Text(c.location),
                                subtitle: Text(
                                  '${c.category} • ${c.description}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Chip(
                                  label: Text(c.status.toUpperCase()),
                                  backgroundColor:
                                      _getStatusColor(c.status).withValues(alpha: 0.1),
                                  labelStyle: TextStyle(
                                    fontSize: 10,
                                    color: _getStatusColor(c.status),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ],
        ),
      ),
    );
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'resolved':
        return Icons.check_circle;
      case 'in_progress':
        return Icons.hourglass_empty;
      default:
        return Icons.pending;
    }
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
