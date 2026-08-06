import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/design_system.dart';
import '../../data/services/invitation_cache_service.dart';

/// Displays all staff invitations with their status (PENDING / ACCEPTED /
/// EXPIRED) and who created them.  Lets the admin track who has accepted
/// and who still needs to act.
///
/// The list is loaded from a lightweight local [InvitationCacheService]
/// first so the screen renders instantly, then a background fetch refreshes
/// the data from the backend.  Any successful mutation on the invitation
/// list invalidates the cache so the next visit starts fresh.
class InvitationListScreen extends StatefulWidget {
  const InvitationListScreen({super.key});

  @override
  State<InvitationListScreen> createState() => _InvitationListScreenState();
}

class _InvitationListScreenState extends State<InvitationListScreen> {
  ApiClient get _api => getIt<ApiClient>();
  InvitationCacheService get _cache => getIt<InvitationCacheService>();

  List<Map<String, dynamic>> _invitations = [];
  bool _isLoading = true;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _load(showCacheFirst: true);
  }

  Future<void> _load({bool showCacheFirst = false}) async {
    try {
      if (showCacheFirst) {
        final cached = _cache.getInvitations();
        if (cached != null && cached.isNotEmpty && mounted) {
          setState(() {
            _invitations = cached;
            _isLoading = false;
          });
        }
      }

      final data = await _api.getStaffInvitations();
      final invitations = data
          .whereType<Map<String, dynamic>>()
          .map(Map<String, dynamic>.from)
          .toList();

      await _cache.saveInvitations(invitations);

      if (!mounted) return;
      setState(() {
        _invitations = invitations;
        _isLoading = false;
        _loadError = null;
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? DesignColors.darkBg : DesignColors.surface;
    final surface = isDark ? DesignColors.darkSurface : Colors.white;
    final textPrimary =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final textSecondary =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Invitations',
          style: TextStyle(
            color: textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: Icon(Icons.refresh_rounded, color: textSecondary),
            onPressed: () => _load(showCacheFirst: false),
          ),
        ],
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      body: _buildBody(isDark, textPrimary, textSecondary),
    );
  }

  Widget _buildBody(bool isDark, Color textPrimary, Color textSecondary) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: DesignColors.accent),
      );
    }
    if (_loadError != null && _invitations.isEmpty) {
      return _loadFailure(isDark, textPrimary, textSecondary);
    }
    if (_invitations.isEmpty) {
      return _emptyState(isDark, textPrimary, textSecondary);
    }
    return RefreshIndicator(
      onRefresh: () => _load(showCacheFirst: false),
      color: DesignColors.accent,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: _invitations.length,
        itemBuilder: (context, index) => _InvitationCard(
          invitation: _invitations[index],
          isDark: isDark,
        ),
      ),
    );
  }

  Widget _loadFailure(bool isDark, Color textPrimary, Color textSecondary) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined,
                color: DesignColors.warning, size: 48),
            const SizedBox(height: 16),
            Text(
              'Could not load invitations',
              style: TextStyle(
                color: textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Please check your connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: textSecondary),
            ),
            const SizedBox(height: 20),
            GradientButton(
              label: 'Retry',
              icon: Icons.refresh_rounded,
              onPressed: () => _load(showCacheFirst: false),
              height: 48,
              borderRadius: 12,
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(bool isDark, Color textPrimary, Color textSecondary) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mail_outline_rounded,
                color: textSecondary, size: 48),
            const SizedBox(height: 16),
            Text(
              'No invitations sent yet',
              style: TextStyle(
                color: textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Invite staff members to join your company.',
              textAlign: TextAlign.center,
              style: TextStyle(color: textSecondary),
            ),
            const SizedBox(height: 20),
            GradientButton(
              label: 'Invite Staff',
              icon: Icons.person_add_alt_1_rounded,
              onPressed: () => _goToInviteStaff(),
              height: 48,
              borderRadius: 12,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _goToInviteStaff() async {
    final didCreate = await context.push<bool>('/invite-staff');
    if (didCreate == true) {
      await _cache.invalidate();
      if (mounted) {
        _load(showCacheFirst: false);
      }
    }
  }
}

class _InvitationCard extends StatelessWidget {
  final Map<String, dynamic> invitation;
  final bool isDark;
  const _InvitationCard({required this.invitation, required this.isDark});

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

    final surface = isDark ? DesignColors.darkSurface : Colors.white;
    final border = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final textPrimary =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final textSecondary =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
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
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (name.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          email,
                          style: TextStyle(
                            color: textSecondary,
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
            _detailRow(Icons.badge_outlined, 'Role', roleName, textSecondary,
                textPrimary),
            const SizedBox(height: 6),
            _detailRow(Icons.store_outlined, 'Branch', branchName, textSecondary,
                textPrimary),
            const SizedBox(height: 6),
            _detailRow(Icons.person_outline, 'Invited by', createdByName,
                textSecondary, textPrimary),
            if (createdAt.isNotEmpty) ...[
              const SizedBox(height: 6),
              _detailRow(Icons.calendar_today_outlined, 'Sent',
                  _formatDate(createdAt), textSecondary, textPrimary),
            ],
            if (acceptedAt != null && acceptedAt.isNotEmpty) ...[
              const SizedBox(height: 6),
              _detailRow(Icons.check_circle_outline, 'Accepted',
                  _formatDate(acceptedAt), textSecondary, textPrimary),
            ],
            if (expiresAt.isNotEmpty && status == 'PENDING') ...[
              const SizedBox(height: 6),
              _detailRow(Icons.schedule_outlined, 'Expires',
                  _formatDate(expiresAt), textSecondary, textPrimary),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value,
      Color textSecondary, Color textPrimary) {
    return Row(
      children: [
        Icon(icon, size: 14, color: textSecondary),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            color: textSecondary,
            fontSize: 13,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: textPrimary,
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
