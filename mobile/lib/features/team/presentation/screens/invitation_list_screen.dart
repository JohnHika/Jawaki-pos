import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/design_system.dart';

/// Displays all staff invitations with their status (PENDING / ACCEPTED /
/// EXPIRED) and who created them.  Lets the admin track who has accepted
/// and who still needs to act.
class InvitationListScreen extends StatefulWidget {
  const InvitationListScreen({super.key});

  @override
  State<InvitationListScreen> createState() => _InvitationListScreenState();
}

class _InvitationListScreenState extends State<InvitationListScreen> {
  ApiClient get _api => getIt<ApiClient>();

  List<Map<String, dynamic>> _invitations = [];
  bool _isLoading = true;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final data = await _api.getStaffInvitations();
      if (!mounted) return;
      setState(() {
        _invitations = data
            .whereType<Map>()
            .map(Map<String, dynamic>.from)
            .toList();
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignColors.darkBg,
      appBar: AppBar(
        backgroundColor: DesignColors.darkSurface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: DesignColors.darkTextPrimary),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Invitations',
          style: TextStyle(
            color: DesignColors.darkTextPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded,
                color: DesignColors.darkTextSecondary),
            onPressed: _load,
          ),
        ],
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: DesignColors.accent),
      );
    }
    if (_loadError != null) {
      return _loadFailure();
    }
    if (_invitations.isEmpty) {
      return _emptyState();
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: DesignColors.accent,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: _invitations.length,
        itemBuilder: (context, index) =>
            _InvitationCard(invitation: _invitations[index]),
      ),
    );
  }

  Widget _loadFailure() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined,
                color: DesignColors.warning, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Could not load invitations',
              style: TextStyle(
                color: DesignColors.darkTextPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please check your connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: DesignColors.darkTextSecondary),
            ),
            const SizedBox(height: 20),
            GradientButton(
              label: 'Retry',
              icon: Icons.refresh_rounded,
              onPressed: _load,
              height: 48,
              borderRadius: 12,
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.mail_outline_rounded,
                color: DesignColors.darkTextSecondary, size: 48),
            const SizedBox(height: 16),
            const Text(
              'No invitations sent yet',
              style: TextStyle(
                color: DesignColors.darkTextPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Invite staff members to join your company.',
              textAlign: TextAlign.center,
              style: TextStyle(color: DesignColors.darkTextSecondary),
            ),
            const SizedBox(height: 20),
            GradientButton(
              label: 'Invite Staff',
              icon: Icons.person_add_alt_1_rounded,
              onPressed: () => context.push('/invite-staff'),
              height: 48,
              borderRadius: 12,
            ),
          ],
        ),
      ),
    );
  }
}

class _InvitationCard extends StatelessWidget {
  final Map<String, dynamic> invitation;
  const _InvitationCard({required this.invitation});

  @override
  Widget build(BuildContext context) {
    final status = invitation['status'] as String? ?? 'PENDING';
    final firstName = invitation['firstName'] as String? ?? '';
    final lastName = invitation['lastName'] as String? ?? '';
    final email = invitation['email'] as String? ?? '';
    final name = '$firstName $lastName'.trim();
    final role = invitation['role'] as Map<String, dynamic>?;
    final roleName = role?['name'] as String? ?? '—';
    final branch = invitation['branch'] as Map<String, dynamic>?;
    final branchName = branch?['name'] as String? ?? '—';
    final createdBy = invitation['createdBy'] as Map<String, dynamic>?;
    final createdByName = createdBy != null
        ? '${createdBy['firstName'] ?? ''} ${createdBy['lastName'] ?? ''}'.trim()
        : '—';
    final createdAt = invitation['createdAt'] as String? ?? '';
    final acceptedAt = invitation['acceptedAt'] as String?;
    final expiresAt = invitation['expiresAt'] as String? ?? '';

    final (Color statusColor, IconData statusIcon, String statusLabel) =
        switch (status) {
      'ACCEPTED' => (DesignColors.success, Icons.check_circle_rounded, 'Accepted'),
      'EXPIRED' => (DesignColors.error, Icons.timer_off_rounded, 'Expired'),
      _ => (DesignColors.warning, Icons.hourglass_empty_rounded, 'Pending'),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: DesignColors.darkSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DesignColors.darkBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: name + status badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty ? email : name,
                        style: const TextStyle(
                          color: DesignColors.darkTextPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (name.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          email,
                          style: const TextStyle(
                            color: DesignColors.darkTextSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 14, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Details grid
            _detailRow(Icons.badge_outlined, 'Role', roleName),
            const SizedBox(height: 6),
            _detailRow(Icons.store_outlined, 'Branch', branchName),
            const SizedBox(height: 6),
            _detailRow(Icons.person_outline, 'Invited by', createdByName),
            if (createdAt.isNotEmpty) ...[
              const SizedBox(height: 6),
              _detailRow(Icons.calendar_today_outlined, 'Sent',
                  _formatDate(createdAt)),
            ],
            if (acceptedAt != null && acceptedAt.isNotEmpty) ...[
              const SizedBox(height: 6),
              _detailRow(Icons.check_circle_outline, 'Accepted',
                  _formatDate(acceptedAt)),
            ],
            if (expiresAt.isNotEmpty && status == 'PENDING') ...[
              const SizedBox(height: 6),
              _detailRow(Icons.schedule_outlined, 'Expires',
                  _formatDate(expiresAt)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 14, color: DesignColors.darkTextSecondary),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(
            color: DesignColors.darkTextSecondary,
            fontSize: 13,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: DesignColors.darkTextPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      final months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      final day = dt.day.toString().padLeft(2, '0');
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final amPm = dt.hour >= 12 ? 'PM' : 'AM';
      final min = dt.minute.toString().padLeft(2, '0');
      return '${months[dt.month - 1]} $day, ${dt.year} $hour:$min $amPm';
    } catch (_) {
      return iso;
    }
  }
}
