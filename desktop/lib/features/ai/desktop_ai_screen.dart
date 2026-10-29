import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/desktop_axon_gateway.dart';
import '../../core/desktop_workspace.dart';
import '../../theme/counterbase_theme.dart';

class DesktopAiScreen extends StatefulWidget {
  const DesktopAiScreen({
    required this.session,
    required this.onOpenGatewaySettings,
    super.key,
  });

  final DesktopSession session;
  final Future<void> Function() onOpenGatewaySettings;

  @override
  State<DesktopAiScreen> createState() => _DesktopAiScreenState();
}

class _DesktopAiScreenState extends State<DesktopAiScreen> {
  static const _tools = <Map<String, dynamic>>[
    {
      'name': 'get_today_summary',
      'description': 'Read this device’s saved sales totals for today.',
      'input_schema': {
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
    },
    {
      'name': 'get_low_stock',
      'description': 'List active products at or below their reorder level.',
      'input_schema': {
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
    },
    {
      'name': 'get_top_products',
      'description':
          'Read the ten best-selling products on this device for a bounded period.',
      'input_schema': {
        'type': 'object',
        'properties': {
          'days': {
            'type': 'integer',
            'minimum': 1,
            'maximum': 30,
            'description':
                'Number of recent calendar days, from 1 to 30. Defaults to 7.',
          },
        },
        'additionalProperties': false,
      },
    },
    {
      'name': 'search_products',
      'description':
          'Search the local product catalog by name or SKU. Do not search for people.',
      'input_schema': {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'minLength': 1, 'maxLength': 80},
        },
        'required': ['query'],
        'additionalProperties': false,
      },
    },
  ];

  final _composer = TextEditingController();
  final _scroll = ScrollController();
  final List<_ChatLine> _visibleMessages = [];
  final List<Map<String, dynamic>> _history = [];
  late final DesktopAxonGatewayClient _gateway;
  bool _busy = false;
  bool _loadingImage = false;
  bool _configured = false;
  String? _configurationError;
  Uint8List? _selectedImageBytes;
  String? _selectedImageName;

  @override
  void initState() {
    super.initState();
    _gateway = DesktopAxonGatewayClient(widget.session);
    unawaited(_refreshConfiguration());
  }

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refreshConfiguration() async {
    try {
      final configured = await widget.session.hasAxonGatewayKey();
      if (mounted) {
        setState(() {
          _configured = configured;
          _configurationError = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _configured = false;
          _configurationError = 'Secure credential storage is unavailable.';
        });
      }
    }
  }

  Future<void> _send() async {
    final prompt = _composer.text.trim();
    if (prompt.isEmpty || _busy) return;
    if (!_configured) {
      await _openGatewaySettings();
      return;
    }
    _composer.clear();
    setState(() {
      _visibleMessages.add(_ChatLine(text: prompt, fromUser: true));
      _busy = true;
    });
    _history.add({'role': 'user', 'content': prompt});
    _scrollToBottom();

    int? streamingLineIndex;
    var receivedText = false;
    try {
      final answer = await _runAgentTurn(
        onText: (text) {
          if (!mounted) return;
          setState(() {
            if (text.isEmpty) {
              if (streamingLineIndex != null &&
                  streamingLineIndex! < _visibleMessages.length) {
                _visibleMessages.removeAt(streamingLineIndex!);
              }
              streamingLineIndex = null;
              return;
            }
            receivedText = true;
            if (streamingLineIndex == null) {
              _visibleMessages.add(_ChatLine(text: text));
              streamingLineIndex = _visibleMessages.length - 1;
            } else {
              _visibleMessages[streamingLineIndex!] = _ChatLine(text: text);
            }
          });
          _scrollToBottom();
        },
      );
      if (!mounted) return;
      _history.add({'role': 'assistant', 'content': answer});
      _trimHistory();
      setState(() {
        if (receivedText && streamingLineIndex != null) {
          _visibleMessages[streamingLineIndex!] = _ChatLine(text: answer);
        } else {
          _visibleMessages.add(_ChatLine(text: answer));
        }
      });
    } on DesktopAxonGatewayFailure catch (error) {
      _history.add({'role': 'assistant', 'content': error.message});
      _trimHistory();
      if (!mounted) return;
      setState(() {
        if (streamingLineIndex != null &&
            streamingLineIndex! < _visibleMessages.length) {
          _visibleMessages.removeAt(streamingLineIndex!);
        }
        _visibleMessages.add(_ChatLine(text: error.message));
      });
    } catch (_) {
      const message =
          'Axon AI could not complete this request. No changes were made.';
      _history.add({'role': 'assistant', 'content': message});
      _trimHistory();
      if (!mounted) return;
      setState(() {
        if (streamingLineIndex != null &&
            streamingLineIndex! < _visibleMessages.length) {
          _visibleMessages.removeAt(streamingLineIndex!);
        }
        _visibleMessages.add(const _ChatLine(text: message));
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _scrollToBottom();
      }
    }
  }

  Future<void> _selectImage() async {
    if (_busy || _loadingImage) return;
    if (!_configured) {
      await _openGatewaySettings();
      if (!_configured || !mounted) return;
    }

    try {
      final selected = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      );
      if (selected == null || !mounted) return;
      final path = selected.path;
      if (path == null || path.isEmpty) {
        _showInlineMessage('This image could not be opened on this computer.');
        return;
      }

      setState(() => _loadingImage = true);
      final file = File(path);
      final length = await file.length();
      if (length <= 0 ||
          length > DesktopAxonGatewayClient.maxVisionImageBytes) {
        throw const DesktopAxonGatewayFailure(
          'Choose an image smaller than 12 MB.',
        );
      }
      final bytes = await file.readAsBytes();
      if (bytes.length != length || !_hasSupportedImageSignature(bytes)) {
        throw const DesktopAxonGatewayFailure(
          'Choose a valid JPG, PNG, or WebP image.',
        );
      }
      if (!mounted) return;
      setState(() {
        _selectedImageBytes = bytes;
        _selectedImageName = selected.name;
        _loadingImage = false;
      });
    } on DesktopAxonGatewayFailure catch (error) {
      if (mounted) {
        setState(() => _loadingImage = false);
        _showInlineMessage(error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingImage = false);
        _showInlineMessage('Could not read that image. Choose another file.');
      }
    }
  }

  bool _hasSupportedImageSignature(Uint8List bytes) {
    bool startsWith(List<int> signature) =>
        bytes.length >= signature.length &&
        List<int>.generate(
              signature.length,
              (index) => bytes[index],
            ).join(',') ==
            signature.join(',');

    final isPng = startsWith(const [
      0x89,
      0x50,
      0x4e,
      0x47,
      0x0d,
      0x0a,
      0x1a,
      0x0a,
    ]);
    final isJpeg = startsWith(const [0xff, 0xd8, 0xff]);
    final isWebp =
        bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP';
    return isPng || isJpeg || isWebp;
  }

  Future<void> _analyzeSelectedImage() async {
    final bytes = _selectedImageBytes;
    final name = _selectedImageName;
    if (bytes == null || name == null || _busy) return;
    if (!_configured) {
      await _openGatewaySettings();
      if (!_configured || !mounted) return;
    }

    const prompt =
        'Describe the visible contents of this image and transcribe '
        'any readable text. Be clear about uncertainty. Do not infer details '
        'that are not visible.';
    final userMessage = 'Analyze image: $name';
    setState(() {
      _visibleMessages.add(_ChatLine(text: userMessage, fromUser: true));
      _busy = true;
    });
    _history.add({'role': 'user', 'content': userMessage});
    _scrollToBottom();

    try {
      final answer = await _gateway.vision(
        prompt: prompt,
        imageBase64: base64Encode(bytes),
      );
      if (!mounted) return;
      _history.add({'role': 'assistant', 'content': answer});
      _trimHistory();
      setState(() {
        _visibleMessages.add(_ChatLine(text: answer));
        _selectedImageBytes = null;
        _selectedImageName = null;
      });
    } on DesktopAxonGatewayFailure catch (error) {
      _history.add({'role': 'assistant', 'content': error.message});
      _trimHistory();
      if (!mounted) return;
      setState(() => _visibleMessages.add(_ChatLine(text: error.message)));
    } catch (_) {
      const message = 'Axon AI could not analyze this image. Please try again.';
      if (!mounted) return;
      setState(() => _visibleMessages.add(const _ChatLine(text: message)));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _scrollToBottom();
      }
    }
  }

  void _showInlineMessage(String message) {
    if (!mounted) return;
    setState(() {
      _visibleMessages.add(_ChatLine(text: message));
    });
  }

  Future<String> _runAgentTurn({
    void Function(String accumulatedText)? onText,
  }) async {
    final requestMessages = List<Map<String, dynamic>>.from(_history);
    const system =
        'You are Axon AI, a concise assistant inside Counterbase. '
        'You may use the supplied read-only tools to answer questions about this shop. '
        'The tools read local records from this computer; those tool results are sent '
        'to the owner’s Axon Gateway to generate your answer. Use tools only when '
        'the user asks about shop data. Never expose customer personal details. '
        'Never claim to edit products, stock, prices, payments, staff, or settings. '
        'You cannot execute business actions. Be clear when local records may be '
        'incomplete or unsynced. If a tool is unavailable, say so plainly.';
    for (var round = 0; round < 4; round++) {
      final turn = await _gateway.chatTurnStream(
        system: system,
        messages: requestMessages,
        tools: _tools,
        maxTokens: 1200,
        onText: onText,
      );
      final blocks = turn['content'];
      final content = blocks is List
          ? blocks
                .whereType<Map>()
                .map((block) => Map<String, dynamic>.from(block))
                .toList()
          : <Map<String, dynamic>>[];
      final toolCalls = content
          .where((block) => block['type'] == 'tool_use')
          .toList();
      if (turn['stop_reason'] != 'tool_use' || toolCalls.isEmpty) {
        final text = content
            .where((block) => block['type'] == 'text')
            .map((block) => (block['text'] ?? '').toString())
            .where((part) => part.trim().isNotEmpty)
            .join('\n')
            .trim();
        if (text.isEmpty) {
          throw const DesktopAxonGatewayFailure(
            'Axon AI returned an empty reply. Please try again.',
          );
        }
        return text;
      }

      requestMessages.add({'role': 'assistant', 'content': content});
      onText?.call('');
      final results = <Map<String, dynamic>>[];
      for (var index = 0; index < toolCalls.length; index++) {
        final call = toolCalls[index];
        final name = (call['name'] ?? '').toString();
        final id = (call['id'] ?? '').toString();
        if (id.isEmpty) {
          throw const DesktopAxonGatewayFailure(
            'Axon AI returned an invalid lookup request. Please try again.',
          );
        }
        if (index >= 4) {
          results.add({
            'type': 'tool_result',
            'tool_use_id': id,
            'is_error': true,
            'content': 'The safe lookup limit for this turn was reached.',
          });
          continue;
        }
        final args = call['input'] is Map
            ? Map<String, dynamic>.from(call['input'] as Map)
            : <String, dynamic>{};
        try {
          final result = await _runReadOnlyTool(name, args);
          results.add({
            'type': 'tool_result',
            'tool_use_id': id,
            'content': jsonEncode(result),
          });
        } catch (_) {
          results.add({
            'type': 'tool_result',
            'tool_use_id': id,
            'is_error': true,
            'content': 'This read-only lookup failed. No changes were made.',
          });
        }
      }
      requestMessages.add({'role': 'user', 'content': results});
    }
    throw const DesktopAxonGatewayFailure(
      'Axon AI reached its safe lookup limit. Ask a shorter question.',
    );
  }

  Future<Map<String, dynamic>> _runReadOnlyTool(
    String name,
    Map<String, dynamic> args,
  ) async {
    final workspace = widget.session.workspace;
    switch (name) {
      case 'get_today_summary':
        return await workspace.getDashboard(branchId: widget.session.branchId);
      case 'get_low_stock':
        final rows = await workspace.getLowStock(widget.session.branchId);
        return {
          'items': rows
              .take(30)
              .map(
                (row) => {
                  'product': row['productName'],
                  'quantity': row['quantity'],
                  'reorderAt': row['lowStockThreshold'],
                  'unit': row['unit'],
                },
              )
              .toList(),
          'totalReturned': rows.length.clamp(0, 30),
          'truncated': rows.length > 30,
        };
      case 'get_top_products':
        final days = (args['days'] as num?)?.toInt().clamp(1, 30).toInt() ?? 7;
        final now = DateTime.now();
        final from = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(Duration(days: days - 1));
        final rows = await workspace.getTopProductsForPeriod(
          from: from,
          to: DateTime(
            now.year,
            now.month,
            now.day,
          ).add(const Duration(days: 1)),
          limit: 10,
        );
        return {
          'days': days,
          'items': rows
              .take(10)
              .map(
                (row) => {
                  'product': row['name'],
                  'quantity': row['quantity'],
                  'revenue': row['revenue'],
                },
              )
              .toList(),
        };
      case 'search_products':
        final query = (args['query'] ?? '').toString().trim();
        if (query.isEmpty || query.length > 80) {
          throw const DesktopAxonGatewayFailure('Invalid product search.');
        }
        final rows = await workspace.getProducts(
          branchId: widget.session.branchId,
          search: query,
        );
        return {
          'items': rows
              .take(20)
              .map(
                (row) => {
                  'product': row['name'],
                  'sku': row['sku'],
                  'category': row['categoryName'] ?? row['category_name'],
                  'price': row['price'],
                },
              )
              .toList(),
          'truncated': rows.length > 20,
        };
      default:
        throw const DesktopAxonGatewayFailure('Unsupported lookup.');
    }
  }

  void _trimHistory() {
    if (_history.length > 24) {
      _history.removeRange(0, _history.length - 24);
    }
  }

  Future<void> _openGatewaySettings() async {
    await widget.onOpenGatewaySettings();
    await _refreshConfiguration();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(28, 24, 28, 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: CbInk.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: CbInk.hairline),
          ),
          child: Row(
            children: [
              const Icon(Icons.lock_outline_rounded, size: 18, color: CbInk.ok),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Questions go to Axon Gateway. Local sales and product details are shared only when a read-only lookup is needed to answer your question. Customer personal data and write actions are not available to the assistant.',
                  style: TextStyle(color: CbInk.ink2, fontSize: 13),
                ),
              ),
              if (!_configured)
                TextButton.icon(
                  onPressed: _openGatewaySettings,
                  icon: const Icon(Icons.key_rounded, size: 18),
                  label: const Text('Add Gateway key'),
                ),
            ],
          ),
        ),
        if (_configurationError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 6),
            child: Text(
              _configurationError!,
              style: const TextStyle(color: CbInk.warn),
            ),
          ),
        Expanded(
          child: _visibleMessages.isEmpty
              ? Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.auto_awesome_outlined,
                          size: 38,
                          color: CbInk.action,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Your shop assistant',
                          style: CbText.display.copyWith(fontSize: 26),
                        ),
                        const SizedBox(height: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: const Text(
                            'Ask for help with sales, stock, or product lookup. The assistant only reads local shop data and cannot change it.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: CbInk.ink2),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(28, 12, 28, 20),
                  itemCount: _visibleMessages.length,
                  itemBuilder: (context, index) {
                    final message = _visibleMessages[index];
                    return Align(
                      alignment: message.fromUser
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 760),
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: message.fromUser
                              ? CbInk.navy
                              : CbInk.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: message.fromUser
                              ? null
                              : Border.all(color: CbInk.hairline),
                        ),
                        child: SelectableText(
                          message.text,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: CbInk.ink,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.fromLTRB(28, 0, 28, 12),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text(
                  'Axon is checking the local records…',
                  style: TextStyle(color: CbInk.ink2),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_loadingImage)
                const LinearProgressIndicator(minHeight: 2)
              else if (_selectedImageBytes != null)
                _SelectedImageCard(
                  bytes: _selectedImageBytes!,
                  name: _selectedImageName ?? 'Selected image',
                  onRemove: _busy
                      ? null
                      : () => setState(() {
                          _selectedImageBytes = null;
                          _selectedImageName = null;
                        }),
                  onAnalyze: _busy ? null : _analyzeSelectedImage,
                ),
              if (_selectedImageBytes != null || _loadingImage)
                const Padding(
                  padding: EdgeInsets.only(top: 8, bottom: 8),
                  child: Text(
                    'The image stays on this computer until you choose Analyze image. Then it is sent to gateway.archeaxon.com.',
                    style: TextStyle(color: CbInk.ink2, fontSize: 12),
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton.filledTonal(
                    tooltip: 'Choose an image to analyze',
                    onPressed: _busy || _loadingImage ? null : _selectImage,
                    icon: const Icon(Icons.image_search_rounded),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _composer,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 2000,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Ask Axon about your shop…',
                        counterText: '',
                        prefixIcon: Icon(Icons.chat_bubble_outline_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _busy ? null : _send,
                    icon: const Icon(Icons.arrow_upward_rounded),
                    label: const Text('Send'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(108, 54),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SelectedImageCard extends StatelessWidget {
  const _SelectedImageCard({
    required this.bytes,
    required this.name,
    required this.onRemove,
    required this.onAnalyze,
  });

  final Uint8List bytes;
  final String name;
  final VoidCallback? onRemove;
  final VoidCallback? onAnalyze;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 560),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: CbInk.surface,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: CbInk.hairline),
    ),
    child: Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.memory(
            bytes,
            width: 76,
            height: 62,
            fit: BoxFit.cover,
            cacheWidth: 240,
            cacheHeight: 200,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13.5,
              color: CbInk.ink,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Remove image',
          onPressed: onRemove,
          icon: const Icon(Icons.close_rounded),
        ),
        FilledButton.icon(
          onPressed: onAnalyze,
          icon: const Icon(Icons.auto_awesome_rounded),
          label: const Text('Analyze image'),
        ),
      ],
    ),
  );
}

class _ChatLine {
  const _ChatLine({required this.text, this.fromUser = false});

  final String text;
  final bool fromUser;
}
