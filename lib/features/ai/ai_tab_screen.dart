import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/constants.dart';
import '../../core/widgets/status_banner.dart';
import '../../models/ai_subscription.dart';
import '../../services/api_service.dart';
import 'ai_chat_screen.dart';
import 'ai_subscribe_screen.dart';

class AiTabScreen extends StatefulWidget {
  const AiTabScreen({super.key});

  @override
  State<AiTabScreen> createState() => _AiTabScreenState();
}

class _AiTabScreenState extends State<AiTabScreen> {
  AiSubscription? _subscription;
  bool _isLoading = true;
  String? _error;
  String _storeId = 'store_001';
  final TextEditingController _chatController = TextEditingController();
  List<Map<String, dynamic>> _recentMessages = [];

  @override
  void initState() {
    super.initState();
    _loadAiStatus();
  }

  Future<void> _loadAiStatus() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final apiService = context.read<ApiService>();
      final sub = await apiService.checkAiStatus(_storeId);
      final history = await apiService.getAiChatHistory(_storeId);

      if (mounted) {
        setState(() {
          _subscription = sub;
          _recentMessages = history.take(3).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load AI status';
          _isLoading = false;
        });
      }
    }
  }

  void _navigateToChat() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const AiChatScreen(),
      ),
    );
  }

  void _navigateToSubscribe() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const AiSubscribeScreen(),
      ),
    ).then((_) => _loadAiStatus());
  }

  @override
  void dispose() {
    _chatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _subscription == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off, size: 64, color: JawakiTheme.textSecondary),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(
                  fontSize: 16,
                  color: JawakiTheme.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadAiStatus,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(160, 44),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final isSubscribed = _subscription != null && _subscription!.isActive;
    final status = _getStatus();
    final daysRemaining = _subscription?.daysRemaining ?? 0;

    return RefreshIndicator(
      onRefresh: _loadAiStatus,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // AI Status Banner
            if (status != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: StatusBanner(
                  status: status,
                  daysRemaining: daysRemaining,
                  onTap: status == 'expired' ? _navigateToSubscribe : null,
                ),
              ),

            if (!isSubscribed)
              _buildFreeTrialCard()
            else
              _buildSubscribedContent(),

            const SizedBox(height: 24),

            // Quick Actions
            _buildQuickActions(isSubscribed),

            const SizedBox(height: 24),

            // Recent AI Messages
            if (_recentMessages.isNotEmpty) ...[
              const Text(
                'Recent Activity',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: JawakiTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              ..._recentMessages.map((msg) => _buildMessageCard(msg)),
            ],
          ],
        ),
      ),
    );
  }

  String? _getStatus() {
    if (_subscription == null) return null;
    if (_subscription!.status == 'trial') return 'trial';
    if (_subscription!.status == 'active') return 'active';
    if (_subscription!.status == 'expired') return 'expired';
    return null;
  }

  Widget _buildFreeTrialCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      color: JawakiTheme.primaryDeepBlue,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [
              JawakiTheme.primaryDeepBlue,
              Color(0xFF1565C0),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Jawaki AI Assistant',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'KES ${ApiConstants.aiPrice}/month',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              '✨ Sales insights & reports\n'
              '📦 Inventory alerts & forecasting\n'
              '👥 Customer behavior analysis\n'
              '💰 Profit margin tracking',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _navigateToSubscribe,
                style: ElevatedButton.styleFrom(
                  backgroundColor: JawakiTheme.accentOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Try AI Free for 7 Days',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubscribedContent() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.auto_awesome, color: JawakiTheme.primaryTeal, size: 22),
                SizedBox(width: 8),
                Text(
                  'AI Assistant',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: JawakiTheme.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _chatController,
              decoration: InputDecoration(
                hintText: 'Ask about sales, inventory...',
                prefixIcon: const Icon(Icons.chat_bubble_outline, size: 20),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.send, color: JawakiTheme.primaryTeal),
                  onPressed: _sendQuickMessage,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendQuickMessage(),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: _navigateToChat,
                  icon: const Icon(Icons.open_in_full, size: 18),
                  label: const Text('Open Full Chat'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _sendQuickMessage() {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    _chatController.clear();
    _navigateToChat();
  }

  Widget _buildQuickActions(bool isSubscribed) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: JawakiTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _actionCard(
                icon: Icons.chat,
                label: 'Full Chat',
                color: JawakiTheme.primaryTeal,
                onTap: isSubscribed ? _navigateToChat : _navigateToSubscribe,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _actionCard(
                icon: Icons.history,
                label: 'History',
                color: JawakiTheme.primaryDeepBlue,
                onTap: isSubscribed ? _navigateToChat : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _actionCard(
                icon: isSubscribed ? Icons.settings : Icons.shopping_cart,
                label: isSubscribed ? 'Manage' : 'Subscribe',
                color: isSubscribed ? JawakiTheme.textSecondary : JawakiTheme.accentOrange,
                onTap: isSubscribed ? null : _navigateToSubscribe,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _actionCard({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageCard(Map<String, dynamic> msg) {
    final isUser = msg['role'] == 'user';
    final message = msg['message'] as String? ?? '';
    final time = msg['timestamp'] as String? ?? '';
    final displayTime = time.isNotEmpty && time.length >= 16
        ? time.substring(11, 16)
        : '';

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isUser
                    ? JawakiTheme.primaryDeepBlue.withValues(alpha: 0.1)
                    : JawakiTheme.primaryTeal.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isUser ? Icons.person : Icons.auto_awesome,
                size: 18,
                color: isUser
                    ? JawakiTheme.primaryDeepBlue
                    : JawakiTheme.primaryTeal,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isUser ? 'You' : 'Jawaki AI',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: JawakiTheme.textPrimary,
                        ),
                      ),
                      if (displayTime.isNotEmpty)
                        Text(
                          displayTime,
                          style: const TextStyle(
                            fontSize: 11,
                            color: JawakiTheme.textSecondary,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message.length > 100
                        ? '${message.substring(0, 100)}...'
                        : message,
                    style: const TextStyle(
                      fontSize: 13,
                      color: JawakiTheme.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
