import 'package:url_launcher/url_launcher.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';

class MaskedCallRepository {
  Future<void> callRideParticipant(String rideId) async {
    final response = await getIt<ApiClient>().get<Map<String, dynamic>>(
      '/api/v1/telephony/rides/$rideId/contact',
    );
    final payload = response.data;
    final number = payload?['proxy_number'] as String?;
    final active = payload?['active'] as bool? ?? false;
    if (response.statusCode != 200 || number == null || number.trim().isEmpty || !active) {
      throw const MaskedCallException('Masked calling is not available for this ride yet.');
    }
    final launched = await launchUrl(
      Uri(scheme: 'tel', path: number),
      mode: LaunchMode.externalApplication,
    );
    if (!launched) throw const MaskedCallException('Could not open the phone dialer.');
  }
}

class MaskedCallException implements Exception {
  final String message;
  const MaskedCallException(this.message);
  @override
  String toString() => message;
}
