import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:dio/dio.dart';

import '../../../../core/network/api_client.dart';
import '../../domain/entities/driver_document.dart';

abstract class DocumentRepository {
  Future<List<DriverDocument>> getDocuments();
  Future<DriverDocument> uploadDocument(String type, File file, Map<String, dynamic> metadata);
  Future<void> deleteDocument(String documentId);
  Future<Uint8List> downloadDocument(String documentId);
  Future<Map<String, dynamic>> getOnboardingStatus();
  Future<void> submitAppeal(String reason);
}

class DocumentRepositoryImpl implements DocumentRepository {
  final ApiClient _apiClient;

  DocumentRepositoryImpl({required ApiClient apiClient}) : _apiClient = apiClient;

  @override
  Future<List<DriverDocument>> getDocuments() async {
    try {
      final response = await _apiClient.get('/api/v1/nidus/drivers/documents');
      final data = response.data as Map<String, dynamic>;
      final documents = data['documents'] as List;
      return documents
          .map((e) => DriverDocument.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw Exception('Failed to get documents: ${e.toString()}');
    }
  }

  @override
  Future<DriverDocument> uploadDocument(
    String type,
    File file,
    Map<String, dynamic> metadata,
  ) async {
    try {
      final formData = {
        'type': type,
        'content_base64': base64Encode(await file.readAsBytes()),
        'name': file.path.split(Platform.pathSeparator).last,
        ...metadata,
      };

      final response = await _apiClient.post(
        '/api/v1/nidus/drivers/documents/upload',
        data: formData,
      );
      final data = response.data as Map<String, dynamic>;
      return DriverDocument.fromJson(data);
    } catch (e) {
      throw Exception('Failed to upload document: ${e.toString()}');
    }
  }

  @override
  Future<void> deleteDocument(String documentId) async {
    try {
      await _apiClient.delete('/api/v1/nidus/drivers/documents/$documentId');
    } catch (e) {
      throw Exception('Failed to delete document: ${e.toString()}');
    }
  }

  @override
  Future<Map<String, dynamic>> getOnboardingStatus() async {
    final response = await _apiClient.get('/api/v1/nidus/drivers/onboarding');
    return Map<String, dynamic>.from(response.data as Map);
  }

  @override
  Future<void> submitAppeal(String reason) async {
    await _apiClient.post('/api/v1/nidus/drivers/appeal', data: {'reason': reason});
  }

  @override
  Future<Uint8List> downloadDocument(String documentId) async {
    try {
      final response = await _apiClient.get<List<int>>(
        '/api/v1/nidus/drivers/documents/$documentId/content',
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Document content is empty');
      }
      return Uint8List.fromList(bytes);
    } catch (e) {
      throw Exception('Failed to download document: ${e.toString()}');
    }
  }
}