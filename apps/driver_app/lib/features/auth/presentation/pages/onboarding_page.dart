import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:get_it/get_it.dart';

import '../../../documents/data/repositories/document_repository.dart';

import '../../../../core/theme/app_colors.dart';


class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _picker = ImagePicker();
  int _currentStep = 0;
  
  File? _licenseFile;
  File? _insuranceFile;
  File? _vehicleFile;
  File? _profileFile;
  File? _backgroundFile;
  File? _inspectionFile;
  bool _submitting = false;

  final List<String> _steps = [
    'Driver License',
    'Insurance',
    'Vehicle Registration',
    'Background Check',
    'Vehicle Inspection',
    'Profile Photo',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        title: const Text('Driver Onboarding'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/login'),
        ),
      ),
      body: Column(
        children: [
          // Progress Indicator
          LinearProgressIndicator(
            value: (_currentStep + 1) / _steps.length,
            backgroundColor: Colors.grey[200],
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
          
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Step Indicator
                  Text(
                    'Step ${_currentStep + 1} of ${_steps.length}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _steps[_currentStep],
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _getDescription(),
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  // Upload Area
                  _buildUploadArea(),
                  
                  const SizedBox(height: 32),
                  
                  // Navigation Buttons
                  Row(
                    children: [
                      if (_currentStep > 0)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setState(() => _currentStep--);
                            },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: const Text('Previous'),
                          ),
                        ),
                      if (_currentStep > 0) const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _canContinue() && !_submitting ? _nextStep : null,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: Text(
                            _currentStep == _steps.length - 1
                                ? 'Submit documents'
                                : 'Next',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getDescription() {
    switch (_currentStep) {
      case 0:
        return 'Upload a clear photo of your valid driver license';
      case 1:
        return 'Upload your current vehicle insurance document';
      case 2:
        return 'Upload your vehicle registration certificate';
      case 3:
        return 'Upload the background-check document required for review';
      case 4:
        return 'Upload proof of the latest vehicle inspection';
      case 5:
        return 'Upload a clear driver profile photo';
      default:
        return '';
    }
  }

  Widget _buildUploadArea() {
    final file = _getCurrentFile();
    
    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        height: 250,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: file != null ? AppColors.success : Colors.grey[300]!,
            width: 2,
          ),
        ),
        child: file != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.file(
                  file,
                  fit: BoxFit.cover,
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.cloud_upload,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Tap to upload',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'JPG, PNG up to 10MB',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  File? _getCurrentFile() {
    switch (_currentStep) {
      case 0:
        return _licenseFile;
      case 1:
        return _insuranceFile;
      case 2:
        return _vehicleFile;
      case 3:
        return _backgroundFile;
      case 4:
        return _inspectionFile;
      case 5:
        return _profileFile;
      default:
        return null;
    }
  }

  void _setCurrentFile(File? file) {
    setState(() {
      switch (_currentStep) {
        case 0:
          _licenseFile = file;
          break;
        case 1:
          _insuranceFile = file;
          break;
        case 2:
          _vehicleFile = file;
          break;
        case 3:
          _backgroundFile = file;
          break;
        case 4:
          _inspectionFile = file;
          break;
        case 5:
          _profileFile = file;
          break;
      }
    });
  }

  bool _canContinue() {
    return _getCurrentFile() != null;
  }

  Future<void> _pickImage() async {
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );

    if (image != null) {
      _setCurrentFile(File(image.path));
    }
  }

  void _nextStep() {
    if (_submitting) return;
    if (_currentStep < _steps.length - 1) {
      setState(() => _currentStep++);
    } else {
      _completeOnboarding();
    }
  }

  Future<void> _completeOnboarding() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final repository = GetIt.I<DocumentRepository>();
    Future<void> submit(String type, File? file, void Function() clear) async {
      if (file == null) return;
      await repository.uploadDocument(type, file, const {});
      if (mounted) setState(clear);
    }
    try {
      await submit('drivers_license', _licenseFile, () => _licenseFile = null);
      await submit('insurance', _insuranceFile, () => _insuranceFile = null);
      await submit('vehicle_registration', _vehicleFile, () => _vehicleFile = null);
      await submit('background_check', _backgroundFile, () => _backgroundFile = null);
      await submit('vehicle_inspection', _inspectionFile, () => _inspectionFile = null);
      await submit('profile_photo', _profileFile, () => _profileFile = null);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Documents submitted for review. Your account stays offline until approval.'), backgroundColor: AppColors.success),
      );
      context.go('/profile/vehicle');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Some documents could not be uploaded. Retry to submit the remaining documents.'), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}