import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../utils/error_utils.dart';
import 'package:flutter/services.dart';
import '../services/attendance_service.dart';
import '../services/face_service.dart';
import '../services/job_service.dart';
import '../services/location_service.dart';
import '../utils/app_notifier.dart';
import 'face_capture_camera_screen.dart';
import 'face_registration_employees_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  final Map<String, dynamic> data;

  const HomeScreen({super.key, required this.data});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const String unknownJobId = 'unknown';
  static const String unknownJobTitle = 'Unknown';

  String? _processingAction;
  List<Map<String, dynamic>> _jobs = [];
  String? _selectedJobId = unknownJobId;
  String? _selectedJobTitle = unknownJobTitle;
  bool _isLoadingJobs = true;
  String? _jobsError;

  @override
  void initState() {
    super.initState();
    _loadJobs();
  }

  String _asString(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    return value.toString();
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  dynamic _firstNonNull(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      if (map[key] != null) return map[key];
    }
    return null;
  }

  String _jobId(Map<String, dynamic> job, int index) {
    final value = _firstNonNull(job, ['job_id', 'id', 'jobId', 'job_code']);
    return value != null ? value.toString() : 'job_$index';
  }

  String _jobTitle(Map<String, dynamic> job, String fallback) {
    final value = _firstNonNull(job, [
      'job_title',
      'title',
      'job_name',
      'name',
    ]);
    return value != null ? value.toString() : fallback;
  }

  Future<void> _loadJobs() async {
    setState(() {
      _isLoadingJobs = true;
      _jobsError = null;
    });

    try {
      final jobs = await JobService.getJobsByCompany(
        _asString(widget.data['company_code']),
      );
      setState(() => _jobs = jobs);
    } on JobException catch (e) {
      setState(() => _jobsError = e.message);
    } catch (e) {
      setState(() => _jobsError = friendlyError(
            e,
            fallback: "Couldn't load the job list. Please try again.",
          ));
    } finally {
      if (mounted) setState(() => _isLoadingJobs = false);
    }
  }

  Future<({String employeeId, String employeeName, File image})?>
  _verifyFace() async {
    final image = await Navigator.of(context).push<File>(
      MaterialPageRoute(
        builder: (_) => const FaceCaptureCameraScreen(title: 'Verify Face'),
      ),
    );

    if (image == null) return null;

    final result = await FaceService.groupVerify(
      companyCode: _asString(widget.data['company_code']),
      image: image,
    );

    final success = result['success'] == true;
    if (!success) {
      _showError(_asString(result['message'], 'Face not recognized.'));
      return null;
    }

    return (
      employeeId: _asString(result['employee_id']),
      employeeName: _asString(result['employee_name']),
      image: image,
    );
  }

  Future<void> _handleAttendance(String action) async {
    final jobTitle = _selectedJobTitle ?? unknownJobTitle;

    HapticFeedback.mediumImpact();
    setState(() => _processingAction = action);

    try {
      // Location and zone first, so nobody verifies their face only to be
      // told they're outside the work zone (zone control).
      final position = await LocationService.getCurrentPosition();
      final zoneMatch = await LocationService.resolveZone(
        companyCode: _asString(widget.data['company_code']),
        latitude: position.latitude,
        longitude: position.longitude,
      );
      final zoneProblem = zoneMatch.zoneProblem;
      if (zoneProblem != null) throw LocationException(zoneProblem);

      final verifiedEmployee = await _verifyFace();
      if (verifiedEmployee == null) return;

      final now = DateTime.now();
      final attendanceDate = '${now.year}-${_pad(now.month)}-${_pad(now.day)}';
      final attendanceTime =
          '${_pad(now.hour)}:${_pad(now.minute)}:${_pad(now.second)}';

      final selfieBytes = await verifiedEmployee.image.readAsBytes();

      final payload = {
        'company_code': _asString(widget.data['company_code']),
        'employee_id': verifiedEmployee.employeeId,
        'employee_name': verifiedEmployee.employeeName,
        'manager_id': _asString(
          widget.data['manager_id'] ?? widget.data['employee_id'],
        ),
        'manager_name': _asString(
          widget.data['manager_name'] ?? widget.data['employee_name'],
        ),
        'zone_name': zoneMatch.zoneName,
        if (zoneMatch.projectName != null) 'project_name': zoneMatch.projectName,
        'attendance_date': attendanceDate,
        'attendance_time': attendanceTime,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'selfie_img': base64Encode(selfieBytes),
        'employee_domain': jobTitle,
      };

      final result = action == 'CHECK_IN'
          ? await AttendanceService.checkIn(payload)
          : await AttendanceService.checkOut(payload);

      if (!mounted) return;

      final workingHours = result['total_working_hours'];
      final breakHours = result['total_break_hours'];
      final extra = [
        if (workingHours != null) 'Worked: $workingHours',
        if (breakHours != null) 'Break: $breakHours',
      ].join(' · ');

      final message = '${verifiedEmployee.employeeName}: ${result['message']}';

      AppNotifier.success(
        context,
        extra.isEmpty ? message : '$message ($extra)',
      );
    } on FaceException catch (e) {
      _showError(e.message);
    } on LocationException catch (e) {
      _showError(e.message);
    } on AttendanceException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError(friendlyError(e));
    } finally {
      if (mounted) setState(() => _processingAction = null);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    AppNotifier.error(context, message);
  }

  Widget _attendanceButton({
    required String action,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    final isProcessing = _processingAction == action;
    final isEnabled = _processingAction == null;

    return Expanded(
      child: FilledButton.icon(
        onPressed: isEnabled ? () => _handleAttendance(action) : null,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          backgroundColor: color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: isProcessing
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(icon),
        label: Text(label),
      ),
    );
  }

  Widget _sectionHeader(
    BuildContext context, {
    required IconData icon,
    required String title,
    Widget? trailing,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        ?trailing,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_asString(widget.data['company_name'], 'Home')),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Profile',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProfileScreen(
                    companyCode: _asString(widget.data['company_code']),
                    employeeId: _asString(widget.data['employee_id']),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadJobs,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [colorScheme.primary, colorScheme.tertiary],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    child: const Icon(
                      Icons.badge_outlined,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome, ${_asString(widget.data['employee_name'], 'Manager')}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _asString(
                            widget.data['company_name'],
                            'Manager dashboard',
                          ),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionHeader(
                      context,
                      icon: Icons.fingerprint,
                      title: 'Mark Attendance',
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Select a job, then verify an employee\'s face to mark their attendance.',
                      style: TextStyle(color: colorScheme.outline),
                    ),
                    const SizedBox(height: 12),
                    if (_isLoadingJobs)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          ),
                        ),
                      )
                    else if (_jobsError != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.errorContainer.withValues(
                            alpha: 0.5,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  size: 18,
                                  color: colorScheme.error,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _jobsError!,
                                    style: TextStyle(color: colorScheme.error),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: _loadJobs,
                                child: const Text('Retry'),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      DropdownButtonFormField<String>(
                        initialValue: _selectedJobId,
                        decoration: const InputDecoration(
                          labelText: 'Job',
                          prefixIcon: Icon(Icons.work_outline),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: unknownJobId,
                            child: Text(unknownJobTitle),
                          ),
                          for (var i = 0; i < _jobs.length; i++)
                            DropdownMenuItem(
                              value: _jobId(_jobs[i], i),
                              child: Text(
                                _jobTitle(_jobs[i], _jobId(_jobs[i], i)),
                              ),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == unknownJobId) {
                            setState(() {
                              _selectedJobId = unknownJobId;
                              _selectedJobTitle = unknownJobTitle;
                            });
                            return;
                          }

                          Map<String, dynamic>? job;
                          for (var i = 0; i < _jobs.length; i++) {
                            if (_jobId(_jobs[i], i) == value) {
                              job = _jobs[i];
                              break;
                            }
                          }
                          setState(() {
                            _selectedJobId = value;
                            _selectedJobTitle = job != null
                                ? _jobTitle(job, value ?? '')
                                : value;
                          });
                        },
                      ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withValues(
                          alpha: 0.4,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.work_outline,
                            size: 16,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Marking attendance for: ${_selectedJobTitle ?? unknownJobTitle}',
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _attendanceButton(
                          action: 'CHECK_IN',
                          label: 'Check In',
                          icon: Icons.login,
                          color: Colors.green,
                        ),
                        const SizedBox(width: 12),
                        _attendanceButton(
                          action: 'CHECK_OUT',
                          label: 'Check Out',
                          icon: Icons.logout,
                          color: Colors.red,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                leading: CircleAvatar(
                  backgroundColor: colorScheme.primaryContainer,
                  child: Icon(
                    Icons.face_retouching_natural,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                title: const Text(
                  'Face Registration',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text('Register employee faces for attendance'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => FaceRegistrationEmployeesScreen(
                        companyCode: _asString(widget.data['company_code']),
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
}
