import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/l10n.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _notificationsEnabled = true;
  bool _emailNotifications = true;
  bool _pushNotifications = true;
  bool _darkMode = false;

  /// Phase 4 (ETB-only standardization): NIDAW prices, books and settles every
  /// fare in ETB. The old currency dropdown offered USD/EUR/GBP/JPY, none of
  /// which the backend accepts — selecting one changed nothing but implied a
  /// live multi-currency capability. It is replaced with an honest read-only
  /// display backed by AppConstants.supportedCurrencies (exactly ['ETB']).
  String get _currency => AppConstants.defaultCurrency;

  /// Currently persisted locale code ('en'/'am'/'om') or null for system
  /// default (§4.3). Read once at build from Hive via LocaleController so the
  /// switcher reflects what main.dart is actually applying.
  String? get _languageCode => LocaleController.readSavedCode();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Notifications section
          _buildSectionTitle('Notifications'),
          _buildSwitchTile(
            icon: Icons.notifications,
            title: 'Enable Notifications',
            subtitle: 'Receive notifications from NIDAW',
            value: _notificationsEnabled,
            onChanged: (value) => setState(() => _notificationsEnabled = value),
          ),
          _buildSwitchTile(
            icon: Icons.email,
            title: 'Email Notifications',
            subtitle: 'Receive email updates',
            value: _emailNotifications,
            onChanged: (value) => setState(() => _emailNotifications = value),
          ),
          _buildSwitchTile(
            icon: Icons.push_pin,
            title: 'Push Notifications',
            subtitle: 'Receive push notifications',
            value: _pushNotifications,
            onChanged: (value) => setState(() => _pushNotifications = value),
          ),

          const SizedBox(height: 24),

          // Appearance section
          _buildSectionTitle('Appearance'),
          _buildSwitchTile(
            icon: Icons.dark_mode,
            title: 'Dark Mode',
            subtitle: 'Use dark theme',
            value: _darkMode,
            onChanged: (value) => setState(() => _darkMode = value),
          ),

          const SizedBox(height: 24),

          // §4.3 Language switcher — real, persisted, live-applying. The old
          // dropdown listed Spanish/French/German which the app does not ship;
          // showing unimplemented locales would be a placeholder surface, so
          // it is replaced with the three locales backed by ARB files.
          _buildSectionTitle('Language'),
          _buildLanguageRadioTiles(),

          const SizedBox(height: 24),

          // Regional
          _buildSectionTitle('Regional'),
          // Phase 4: read-only ETB display. A selector offering currencies the
          // platform does not support was removed; AppConstants
          // .supportedCurrencies is exactly ['ETB'] and the backend rejects
          // any other currency code fail-closed.
          _buildCurrencyTile(),

          const SizedBox(height: 24),

          // Account section
          _buildSectionTitle('Account'),
          _buildSettingsTile(
            icon: Icons.lock,
            title: 'Change Password',
            onTap: () {},
          ),
          _buildSettingsTile(
            icon: Icons.phone,
            title: 'Change Phone Number',
            onTap: () {},
          ),
          _buildSettingsTile(
            icon: Icons.email,
            title: 'Change Email',
            onTap: () {},
          ),

          const SizedBox(height: 24),

          // Privacy section
          _buildSectionTitle('Privacy & Security'),
          _buildSettingsTile(
            icon: Icons.privacy_tip,
            title: 'Privacy Settings',
            onTap: () => context.push('/settings/consent'),
          ),
          _buildSettingsTile(
            icon: Icons.security,
            title: 'Two-Factor Authentication',
            onTap: () {},
          ),
          _buildSettingsTile(
            icon: Icons.data_usage,
            title: 'Data Usage',
            onTap: () {},
          ),

          const SizedBox(height: 24),

          // About section
          _buildSectionTitle('About'),
          _buildSettingsTile(
            icon: Icons.info,
            title: 'About NIDAW',
            onTap: () {},
          ),
          _buildSettingsTile(
            icon: Icons.description,
            title: 'Terms of Service',
            onTap: () => context.push('/legal/terms_of_service'),
          ),
          _buildSettingsTile(
            icon: Icons.privacy_tip,
            title: 'Privacy Policy',
            onTap: () => context.push('/legal/privacy_policy'),
          ),

          const SizedBox(height: 24),

          // Danger zone
          _buildSectionTitle('Danger Zone'),
          _buildSettingsTile(
            icon: Icons.delete_forever,
            title: 'Delete Account',
            onTap: () => _showDeleteAccountDialog(),
            color: AppColors.error,
          ),
        ],
      ),
    );
  }

  /// §4.3 Language switcher rows. Each choice persists via
  /// LocaleController.saveCode() (Hive 'settings' box) and immediately
  /// rebuilds the MaterialApp through the LocaleController.apply notifier —
  /// no restart required, no dead dropdown.
  Widget _buildLanguageRadioTiles() {
    final String? selected = _languageCode;
    return Column(
      children: [
        for (final LocaleChoice choice in LocaleController.choices)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: RadioListTile<String?>(
              secondary: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.language, color: AppColors.primary),
              ),
              title: Text(
                choice.nativeLabel,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: choice.code == null
                  ? Text(
                      'Follow the device language',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    )
                  : null,
              value: choice.code,
              groupValue: selected,
              onChanged: (code) async {
                await LocaleController.saveCode(code);
                if (mounted) setState(() {});
              },
            ),
          ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: SwitchListTile(
        secondary: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppColors.primary),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        value: value,
        onChanged: onChanged,
        activeColor: AppColors.primary,
      ),
    );
  }

  /// Read-only currency row (Phase 4, ETB-only). Shows the single supported
  /// currency and its unit ("Ethiopian Birr — santim minor units") instead of
  /// offering a picker for currencies the platform rejects.
  Widget _buildCurrencyTile() {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.attach_money, color: AppColors.primary),
        ),
        title: const Text('Currency',
            style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${AppConstants.defaultCurrency} — Ethiopian Birr '
          '(supported: ${AppConstants.supportedCurrencies.join(', ')})',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        trailing: Text(
          _currency,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? color,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (color ?? AppColors.primary).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color ?? AppColors.primary),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: color ?? AppColors.textPrimary,
          ),
        ),
        trailing: Icon(Icons.chevron_right, color: color ?? Colors.grey),
        onTap: onTap,
      ),
    );
  }

  void _showDeleteAccountDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'Are you sure you want to delete your account? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: Implement account deletion
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}