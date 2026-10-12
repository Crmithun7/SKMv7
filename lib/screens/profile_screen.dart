import 'dart:convert';
import 'package:flutter/material.dart';
import '../utils/error_utils.dart';
import '../services/employee_service.dart';
import '../services/session_service.dart';
import '../utils/app_notifier.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String companyCode;
  final String employeeId;

  const ProfileScreen({
    super.key,
    required this.companyCode,
    required this.employeeId,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _employee;
  String? _errorMessage;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final employee = await EmployeeService.getEmployeeSolo(
        companyCode: widget.companyCode,
        employeeId: widget.employeeId,
      );
      setState(() => _employee = employee);
    } on EmployeeException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(
        () => _errorMessage = friendlyError(
          e,
          fallback: "Couldn't load your profile. Please try again.",
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _asString(dynamic value, [String fallback = '-']) {
    if (value == null || value.toString().isEmpty) return fallback;
    return value.toString();
  }

  ImageProvider? _imageFromBase64(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    final base64Part = value.contains(',') ? value.split(',').last : value;
    try {
      return MemoryImage(base64Decode(base64Part));
    } catch (_) {
      return null;
    }
  }

  Future<void> _logout() async {
    await SessionService.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _openChangePasswordDialog() {
    showDialog(
      context: context,
      builder: (_) => _ChangePasswordDialog(
        companyCode: widget.companyCode,
        employeeId: widget.employeeId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _loadProfile, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final emp = _employee!;
    final image = _imageFromBase64(emp['employee_img']);
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [colorScheme.primary, colorScheme.tertiary],
            ),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(28),
              bottomRight: Radius.circular(28),
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: [
              CircleAvatar(
                radius: 48,
                backgroundColor: Colors.white,
                backgroundImage: image,
                child: image == null
                    ? Icon(
                        Icons.person,
                        size: 48,
                        color: colorScheme.onSurfaceVariant,
                      )
                    : null,
              ),
              const SizedBox(height: 12),
              Text(
                _asString(emp['employee_name']),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                _asString(emp['job_name']),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Line Manager',
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Card(
                child: Column(
                  children: [
                    _ProfileRow(
                      label: 'Employee ID',
                      value: _asString(emp['employee_id']),
                      icon: Icons.badge_outlined,
                    ),
                    _ProfileRow(
                      label: 'Login Code',
                      value: _asString(emp['login_code']),
                      icon: Icons.key_outlined,
                    ),
                    _ProfileRow(
                      label: 'Job Code',
                      value: _asString(emp['job_code']),
                      icon: Icons.work_outline,
                    ),
                    _ProfileRow(
                      label: 'Email',
                      value: _asString(emp['mail']),
                      icon: Icons.email_outlined,
                    ),
                    _ProfileRow(
                      label: 'Phone',
                      value: _asString(emp['phone_no']),
                      icon: Icons.phone_outlined,
                    ),
                    _ProfileRow(
                      label: 'Gender',
                      value: _asString(emp['gender']),
                    ),
                    _ProfileRow(
                      label: 'Date of Join',
                      value: _asString(emp['date_of_join']),
                      icon: Icons.calendar_today_outlined,
                    ),
                    _ProfileRow(label: 'Grade', value: _asString(emp['grade'])),
                    _ProfileRow(
                      label: 'Nationality',
                      value: _asString(emp['employee_nationality']),
                    ),
                    _ProfileRow(
                      label: 'Blood Group',
                      value: _asString(emp['employee_blood_group']),
                      icon: Icons.bloodtype_outlined,
                    ),
                    _ProfileRow(
                      label: 'Marital Status',
                      value: _asString(emp['marital_status']),
                    ),
                    _ProfileRow(
                      label: 'Religion',
                      value: _asString(emp['religion']),
                    ),
                    _ProfileRow(
                      label: 'Address',
                      value: _asString(emp['address']),
                      icon: Icons.location_on_outlined,
                    ),
                    _ProfileRow(
                      label: 'Reporting Manager',
                      value: _asString(emp['reporting_manager']),
                      icon: Icons.supervisor_account_outlined,
                    ),
                    _ProfileRow(
                      label: 'Salary',
                      value: _asString(emp['salary']),
                      icon: Icons.payments_outlined,
                      isLast: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(
                        Icons.lock_outline,
                        color: colorScheme.primary,
                      ),
                      title: const Text('Change Password'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _openChangePasswordDialog,
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      leading: Icon(Icons.logout, color: colorScheme.error),
                      title: Text(
                        'Logout',
                        style: TextStyle(color: colorScheme.error),
                      ),
                      onTap: _logout,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  final String companyCode;
  final String employeeId;

  const _ChangePasswordDialog({
    required this.companyCode,
    required this.employeeId,
  });

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await EmployeeService.changePassword(
        companyCode: widget.companyCode,
        employeeId: widget.employeeId,
        oldPassword: _oldPasswordController.text,
        newPassword: _newPasswordController.text,
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      AppNotifier.success(context, 'Password changed successfully');
    } on EmployeeException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = friendlyError(e));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change Password'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _oldPasswordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Old Password'),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Old password is required' : null,
            ),
            TextFormField(
              controller: _newPasswordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New Password'),
              validator: (v) {
                if (v == null || v.isEmpty) return 'New password is required';
                if (v.length < 4) return 'Must be at least 4 characters';
                return null;
              },
            ),
            TextFormField(
              controller: _confirmPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirm New Password',
              ),
              validator: (v) => (v != _newPasswordController.text)
                  ? 'Passwords do not match'
                  : null,
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Submit'),
        ),
      ],
    );
  }
}

class _ProfileRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final bool isLast;

  const _ProfileRow({
    required this.label,
    required this.value,
    this.icon,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 140,
                child: Row(
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 16, color: colorScheme.primary),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        label,
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: colorScheme.outline),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: Text(value)),
            ],
          ),
        ),
        if (!isLast) const Divider(height: 1),
      ],
    );
  }
}
