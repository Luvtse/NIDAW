import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/repositories/document_repository.dart';
import '../../domain/entities/driver_document.dart';

class DocumentsPage extends StatefulWidget {
  const DocumentsPage({super.key});

  @override
  State<DocumentsPage> createState() => _DocumentsPageState();
}

class _DocumentsPageState extends State<DocumentsPage> {
  final ImagePicker _picker = ImagePicker();
  late final DocumentRepository _repository = GetIt.I<DocumentRepository>();
  List<DriverDocument> _documents = const [];
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _onboarding;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  Future<void> _loadDocuments() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _repository.getDocuments(),
        _repository.getOnboardingStatus(),
      ]);
      if (!mounted) return;
      setState(() {
        _documents = results[0] as List<DriverDocument>;
        _onboarding = results[1] as Map<String, dynamic>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Documents could not be loaded. Check your connection and retry.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        title: const Text('Documents'),
        titleTextStyle: const TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w800),
        actions: [
          IconButton(
            onPressed: _loading || _uploading ? null : _loadDocuments,
            tooltip: 'Refresh documents',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        ElevatedButton(onPressed: _loadDocuments, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : _documents.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(22)),
                              child: const Icon(Icons.folder_open_rounded, size: 38, color: AppColors.primary),
                            ),
                            const SizedBox(height: 18),
                            const Text('Your documents start here', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                            const SizedBox(height: 6),
                            const Text('No documents submitted yet.'),
                            const SizedBox(height: 8),
                            const Text('Upload a clear photo of a required document to begin review.', textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.center,
                              children: [
                                _uploadButton('drivers_license', 'Driver license'),
                                _uploadButton('vehicle_registration', 'Vehicle registration'),
                                _uploadButton('insurance', 'Insurance'),
                                _uploadButton('background_check', 'Background check'),
                                _uploadButton('vehicle_inspection', 'Vehicle inspection'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadDocuments,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          if (_uploading) const LinearProgressIndicator(),
                          if (_onboarding != null) _buildOnboardingStatus(),
                          ..._documents.map(_buildDocumentCard),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _uploadButton('drivers_license', 'Driver license'),
                              _uploadButton('vehicle_registration', 'Vehicle registration'),
                              _uploadButton('insurance', 'Insurance'),
                              _uploadButton('background_check', 'Background check'),
                              _uploadButton('vehicle_inspection', 'Vehicle inspection'),
                            ],
                          ),
                        ],
                      ),
                    ),
    );
  }

  Widget _buildOnboardingStatus() {
    final status = _onboarding?['status'] as String? ?? 'unknown';
    final missing = (_onboarding?['missing_documents'] as List?)?.cast<String>() ?? const <String>[];
    final reason = _onboarding?['suspension_reason'] as String?;
    final statusColor = switch (status) {
      'approved' || 'verified' => AppColors.success,
      'rejected' || 'suspended' => AppColors.error,
      _ => AppColors.warning,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(13)),
                child: const Icon(Icons.verified_user_outlined, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              const Expanded(child: Text('Driver application', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: statusColor.withOpacity(.12), borderRadius: BorderRadius.circular(30)),
                child: Text(status.toUpperCase(), style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          if (missing.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('Still needed', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 5),
            Text(missing.join(' · '), style: const TextStyle(color: AppColors.textSecondary)),
          ],
          if (reason != null && reason.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(reason, style: const TextStyle(color: AppColors.textSecondary)),
          ],
          if (status == 'rejected' || status == 'suspended') ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _uploading ? null : _submitAppeal,
              icon: const Icon(Icons.gavel_rounded),
              label: const Text('Submit appeal'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _submitAppeal() async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Appeal onboarding decision'),
        content: TextField(controller: controller, maxLines: 4, maxLength: 2000, decoration: const InputDecoration(hintText: 'Explain why the decision should be reviewed.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Submit')),
        ],
      ),
    );
    if (reason == null || reason.trim().isEmpty || !mounted) return;
    setState(() => _uploading = true);
    try {
      await _repository.submitAppeal(reason.trim());
      await _loadDocuments();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Appeal submitted for review.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Appeal could not be submitted.')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Widget _buildDocumentCard(DriverDocument doc) {
    final statusColor = switch (doc.status) {
      'verified' => AppColors.success,
      'pending' => AppColors.warning,
      _ => AppColors.error,
    };
    final expiry = doc.expiryDate == null
        ? 'Expiry date not provided'
        : 'Expires: ${doc.expiryDate!.toLocal().toIso8601String().split("T").first}';
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.description, color: AppColors.primary, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(doc.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text('${doc.type} · $expiry', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: statusColor.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                  child: Text(doc.status.toUpperCase(), style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            if (doc.verificationNotes != null && doc.verificationNotes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(doc.verificationNotes!),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: OutlinedButton.icon(onPressed: () => _viewDocument(doc), icon: const Icon(Icons.visibility), label: const Text('View'))),
                const SizedBox(width: 12),
                Expanded(child: OutlinedButton.icon(onPressed: doc.status == 'verified' ? null : () => _uploadDocument(doc.type), icon: const Icon(Icons.upload), label: const Text('Replace'))),
              ],
            ),
          ],
      ),
    );
  }

  Widget _uploadButton(String type, String label) => OutlinedButton.icon(
        onPressed: _uploading ? null : () => _uploadDocument(type),
        icon: const Icon(Icons.upload),
        label: Text(label),
      );

  Future<void> _viewDocument(DriverDocument document) async {
    try {
      final bytes = await _repository.downloadDocument(document.id);
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: InteractiveViewer(
            child: Image.memory(bytes, errorBuilder: (context, error, stack) => const Padding(
              padding: EdgeInsets.all(24),
              child: Text('This document format cannot be previewed in the app.'),
            )),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Document could not be opened.')));
    }
  }

  Future<void> _uploadDocument(String type) async {
    if (_uploading) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add document photo',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 6),
              const Text('Use a clear, well-lit photo with all document edges visible.'),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined, color: AppColors.primary),
                title: const Text('Take a photo'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined, color: AppColors.primary),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null || !mounted) return;
    final image = await _picker.pickImage(
      source: source,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 88,
    );
    if (image == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      await _repository.uploadDocument(type, File(image.path), const {});
      await _loadDocuments();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Document submitted for review.'), backgroundColor: AppColors.success));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload failed. Please retry on a stable connection.'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }
}
