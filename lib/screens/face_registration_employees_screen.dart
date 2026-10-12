import 'dart:convert';
import 'package:flutter/material.dart';
import '../utils/error_utils.dart';
import '../services/employee_service.dart';
import 'face_registration_screen.dart';

class FaceRegistrationEmployeesScreen extends StatefulWidget {
  final String companyCode;

  const FaceRegistrationEmployeesScreen({super.key, required this.companyCode});

  @override
  State<FaceRegistrationEmployeesScreen> createState() =>
      _FaceRegistrationEmployeesScreenState();
}

class _FaceRegistrationEmployeesScreenState
    extends State<FaceRegistrationEmployeesScreen> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _employees = [];
  String _searchQuery = '';
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final employees = await EmployeeService.getEmployees(
        companyCode: widget.companyCode,
      );
      setState(() => _employees = employees);
    } on EmployeeException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(
        () => _errorMessage = friendlyError(
          e,
          fallback: "Couldn't load the employee list. Please try again.",
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _asString(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
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

  @override
  Widget build(BuildContext context) {
    final query = _searchQuery.trim().toLowerCase();
    final filtered = query.isEmpty
        ? <Map<String, dynamic>>[]
        : _employees.where((emp) {
            final name = _asString(emp['employee_name']).toLowerCase();
            final id = _asString(emp['employee_id']).toLowerCase();
            return name.contains(query) || id.contains(query);
          }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Select Employee')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name or employee ID',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      ),
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          Expanded(child: _buildBody(filtered)),
        ],
      ),
    );
  }

  Widget _buildBody(List<Map<String, dynamic>> filtered) {
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
              FilledButton(
                onPressed: _loadEmployees,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_searchQuery.trim().isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search,
                size: 48,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 12),
              Text(
                'Search for an employee by name or employee ID to register their face.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
            ],
          ),
        ),
      );
    }

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_off_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            const Text('No employees found'),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadEmployees,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: filtered.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
        itemBuilder: (context, index) {
          final emp = filtered[index];
          final image = _imageFromBase64(emp['employee_img']);

          return ListTile(
            leading: CircleAvatar(
              backgroundImage: image,
              child: image == null ? const Icon(Icons.person) : null,
            ),
            title: Text(
              _asString(emp['employee_name']),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${_asString(emp['employee_id'])} · ${_asString(emp['job_name'])}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => FaceRegistrationScreen(
                    companyCode: widget.companyCode,
                    employeeId: _asString(emp['employee_id']),
                    employeeName: _asString(emp['employee_name']),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
