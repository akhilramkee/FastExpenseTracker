import 'dart:async';
import 'dart:convert';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:file_picker/file_picker.dart';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:intl/intl.dart';
import 'core/db/database_helper.dart';
import 'core/models/transaction_model.dart';
import 'core/network/sync_worker.dart';
import 'core/services/expense_entry_service.dart';
import 'core/utils/category_utils.dart';
import 'core/utils/currency_utils.dart';
import 'widgets/quick_add_sheet.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
  } else if (defaultTargetPlatform == TargetPlatform.macOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  runApp(const ExpenseTrackerApp());
}

class ExpenseTrackerApp extends StatelessWidget {
  const ExpenseTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TapEx',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F101A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF8B5CF6),
          secondary: Color(0xFF06B6D4),
          surface: Color(0xFF1E1F30),
        ),
        textTheme: ThemeData.dark().textTheme.apply(
              fontFamily: 'Outfit',
            ),
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final TextEditingController _entryController = TextEditingController();
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncWorker _syncWorker = SyncWorker();
  final ExpenseEntryService _expenseEntryService = ExpenseEntryService();
  final AppLinks _appLinks = AppLinks();

  List<TransactionModel> _transactions = [];
  bool _isSyncing = false;
  bool _isImporting = false;
  bool _isLoading = true;
  bool _serverOnline = false;
  String _livePreviewText = "Type something like: 1450 zoom subscription renewal @work";
  Timer? _statusPollTimer;
  Timer? _serverStatusTimer;
  StreamSubscription<Uri>? _linkSubscription;
  bool _quickAddPending = false;
  String _pendingQuickAddInitialText = '';
  bool _isQuickAddSheetOpen = false;

  // Live preview parser state
  double _parsedAmount = 0.0;
  String? _selectedCategoryFilter;

  List<TransactionModel> get _filteredTransactions {
    if (_selectedCategoryFilter == null) return _transactions;
    return _transactions
        .where((tx) => tx.tag.toLowerCase() == _selectedCategoryFilter)
        .toList();
  }

  List<String> get _availableCategories {
    final tags = _transactions.map((tx) => tx.tag.toLowerCase()).toSet().toList();
    tags.sort();
    return tags;
  }

  @override
  void initState() {
    super.initState();
    _initializeData();

    // Check server status periodically
    _serverStatusTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted) _checkServerStatus();
    });

    // Auto pull sync updates every 5 seconds if there are processing transactions
    _statusPollTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      final hasUnfinished = _transactions.any(
        (tx) => tx.syncStatus == SyncStatus.processing || tx.syncStatus == SyncStatus.failed
      );
      if (hasUnfinished && mounted) {
        await _syncWorker.pullSyncUpdates();
        _loadTransactions();
      }
    });

    _entryController.addListener(_updateLivePreview);
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    final initialLink = await _appLinks.getInitialLink();
    if (initialLink != null) {
      _queueQuickAddFromUri(initialLink);
    }

    _linkSubscription = _appLinks.uriLinkStream.listen(_queueQuickAddFromUri);
  }

  void _queueQuickAddFromUri(Uri uri) {
    if (uri.host != 'add') return;

    setState(() {
      _quickAddPending = true;
      _pendingQuickAddInitialText = uri.queryParameters['text'] ?? '';
    });
    _maybeShowQuickAddSheet();
  }

  Future<void> _maybeShowQuickAddSheet() async {
    if (!_quickAddPending || _isLoading || !mounted || _isQuickAddSheetOpen) return;

    _quickAddPending = false;
    final initialText = _pendingQuickAddInitialText;
    _pendingQuickAddInitialText = '';

    _isQuickAddSheetOpen = true;
    final saved = await showQuickAddSheet(
      context,
      initialText: initialText,
      expenseEntryService: _expenseEntryService,
    );
    _isQuickAddSheetOpen = false;

    if (!mounted || saved == null) return;

    await _loadTransactions();
    if (!mounted) return;

    _triggerSync();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Saved: ${formatCurrency(saved.amount)} ${saved.description} #${saved.tag}',
        ),
      ),
    );
  }

  @override
  void dispose() {
    _statusPollTimer?.cancel();
    _serverStatusTimer?.cancel();
    _linkSubscription?.cancel();
    _entryController.dispose();
    super.dispose();
  }

  Future<void> _checkServerStatus() async {
    final online = await _syncWorker.isServerReachable();
    if (mounted) {
      setState(() {
        _serverOnline = online;
      });
    }
  }

  Future<void> _initializeData() async {
    try {
      await _loadTransactions();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _maybeShowQuickAddSheet();
      }
    }
    unawaited(_triggerSync());
    unawaited(_checkServerStatus());
  }

  Future<void> _loadTransactions() async {
    final list = await _dbHelper.getTransactions();
    if (mounted) {
      setState(() {
        _transactions = list;
      });
    }
  }

  void _updateLivePreview() {
    final text = _entryController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _livePreviewText = "Type something like: 06/20 Rs. 45.90 dinner @night #food (date optional, defaults to today)";
        _parsedAmount = 0.0;
      });
      return;
    }

    final parsed = TransactionModel.parse(text);
    final dateLabel = DateFormat('MMM d, yyyy').format(parsed.createdAt);
    setState(() {
      _parsedAmount = parsed.amount;
      _livePreviewText =
          "Preview — $dateLabel • Amount: ${formatCurrency(parsed.amount)}  •  Tag: #${parsed.tag}";
    });
  }

  Future<void> _saveTransaction() async {
    final text = _entryController.text.trim();
    if (text.isEmpty) return;

    await _expenseEntryService.addFromText(text);
    _entryController.clear();

    await _loadTransactions();

    // Proactively trigger background sync
    _triggerSync();
  }

  Future<void> _triggerSync() async {
    if (_isSyncing) return;
    setState(() {
      _isSyncing = true;
    });

    try {
      await _syncWorker.syncAll();
      await _loadTransactions();
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  Future<void> _importFromFile() async {
    if (!_serverOnline) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Server offline — import requires a connection')),
      );
      return;
    }
    if (_isImporting) return;

    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt', 'csv', 'text'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not read the selected file')),
      );
      return;
    }

    final content = utf8.decode(bytes);
    if (content.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The selected file is empty')),
      );
      return;
    }

    final format = file.extension?.toLowerCase() == 'csv' ? 'csv' : 'text';

    setState(() {
      _isImporting = true;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Submitting import…')),
      );
    }

    try {
      await _syncWorker.submitImport(
        content: content,
        format: format,
      );

      _triggerSync();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Import submitted — transactions will appear after sync'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
        });
      }
    }
  }

  Future<void> _editTransaction(TransactionModel tx) async {
    final controller = TextEditingController(text: tx.rawInput);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1F30),
        title: const Text('Edit expense'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. 06/20 45.90 dinner @night #food',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (result == null || result.trim().isEmpty) return;

    final updated = tx.reparse(result.trim());
    await _dbHelper.updateTransaction(updated);
    await _loadTransactions();

    if (_serverOnline) {
      await _syncWorker.syncEditedTransaction(updated);
      await _loadTransactions();
    }
  }

  Future<void> _deleteTransaction(TransactionModel tx) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1F30),
        title: const Text('Delete expense?'),
        content: Text(
          'Remove "${tx.displayTitle}" (${formatCurrency(tx.amount)})? This will sync the deletion to the server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await _dbHelper.queueDelete(tx.id);
    await _dbHelper.deleteTransaction(tx.id);
    if (_selectedCategoryFilter != null &&
        !_transactions.any((t) => t.id != tx.id && t.tag.toLowerCase() == _selectedCategoryFilter)) {
      _selectedCategoryFilter = null;
    }
    await _loadTransactions();
    _triggerSync();
  }

  double _calculateTotalExpenses(List<TransactionModel> transactions) {
    return transactions.fold(0.0, (sum, item) => sum + item.amount);
  }

  @override
  Widget build(BuildContext context) {
    final visibleTransactions = _filteredTransactions;
    final totalExpense = _calculateTotalExpenses(visibleTransactions);
    final formatter = currencyFormatter;
    final isFiltered = _selectedCategoryFilter != null;

    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'TapEx',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.5,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _serverOnline ? Colors.greenAccent : Colors.redAccent,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _serverOnline ? 'Tailscale Online' : 'Offline Mode',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[400],
                              ),
                            ),
                          ],
                        )
                      ],
                    ),
                    IconButton.filledTonal(
                      onPressed: _triggerSync,
                      icon: _isSyncing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.sync),
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF1E1F30),
                        foregroundColor: Colors.white,
                      ),
                    )
                  ],
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
              SliverToBoxAdapter(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF8B5CF6), Color(0xFF06B6D4)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      )
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TOTAL SPENT',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Colors.white.withValues(alpha: 0.8),
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        formatter.format(totalExpense),
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        isFiltered
                            ? '${visibleTransactions.length} of ${_transactions.length} shown'
                            : '${_transactions.length} Transactions Logged',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
              SliverToBoxAdapter(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1F30),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _entryController,
                        decoration: InputDecoration(
                          hintText: 'Add expense (e.g. 06/20 45.90 dinner @night #food)',
                          hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
                          border: InputBorder.none,
                          prefixIcon: IconButton(
                            tooltip: _serverOnline
                                ? 'Import from file'
                                : 'Import from file (requires server connection)',
                            onPressed: _isImporting ? null : _importFromFile,
                            icon: _isImporting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Icon(
                                    Icons.upload_file_rounded,
                                    color: _serverOnline
                                        ? const Color(0xFF8B5CF6)
                                        : Colors.grey[600],
                                  ),
                          ),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.arrow_forward_rounded),
                            onPressed: _saveTransaction,
                            color: const Color(0xFF06B6D4),
                          ),
                        ),
                        onSubmitted: (_) => _saveTransaction(),
                      ),
                      const Divider(height: 16, color: Colors.white10),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        child: Text(
                          _livePreviewText,
                          style: TextStyle(
                            fontSize: 12,
                            color: _parsedAmount > 0 ? const Color(0xFF06B6D4) : Colors.grey[400],
                            fontWeight: _parsedAmount > 0 ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
              SliverToBoxAdapter(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Recent Transactions',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_transactions.any((tx) => tx.syncStatus != SyncStatus.completed))
                      Text(
                        'Auto-sync active',
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      )
                  ],
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              if (_availableCategories.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _buildFilterChip(label: 'All', value: null),
                        ..._availableCategories.map(
                          (category) => _buildFilterChip(label: category, value: category),
                        ),
                      ],
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
              ],
              if (visibleTransactions.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.receipt_long_rounded, size: 64, color: Colors.grey[700]),
                        const SizedBox(height: 16),
                        Text(
                          isFiltered ? 'No transactions in this category.' : 'No transactions yet.',
                          style: TextStyle(color: Colors.grey[500], fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _buildTransactionCard(visibleTransactions[index]),
                    childCount: visibleTransactions.length,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip({required String label, required String? value}) {
    final selected = _selectedCategoryFilter == value;
    final style = value != null
        ? resolveCategoryStyle(tag: value)
        : const CategoryStyle(icon: Icons.grid_view_rounded, color: Color(0xFF8B5CF6));

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        avatar: Icon(style.icon, size: 16, color: selected ? Colors.white : style.color),
        selected: selected,
        onSelected: (_) {
          setState(() {
            _selectedCategoryFilter = value;
          });
        },
        selectedColor: style.color.withValues(alpha: 0.35),
        checkmarkColor: Colors.white,
        backgroundColor: const Color(0xFF1E1F30),
        labelStyle: TextStyle(
          color: selected ? Colors.white : Colors.grey[300],
          fontSize: 12,
        ),
        side: BorderSide(
          color: selected ? style.color : Colors.white.withValues(alpha: 0.08),
        ),
      ),
    );
  }

  Widget _buildTransactionCard(TransactionModel tx) {
    Color badgeColor;
    IconData statusIcon;
    bool showSpinner = false;

    switch (tx.syncStatus) {
      case SyncStatus.pending:
        badgeColor = Colors.orangeAccent;
        statusIcon = Icons.wifi_off_rounded;
        break;
      case SyncStatus.processing:
        badgeColor = Colors.blueAccent;
        statusIcon = Icons.hourglass_empty_rounded;
        showSpinner = true;
        break;
      case SyncStatus.completed:
        badgeColor = Colors.greenAccent;
        statusIcon = Icons.check_circle_rounded;
        break;
      case SyncStatus.failed:
        badgeColor = Colors.redAccent;
        statusIcon = Icons.error_outline_rounded;
        break;
    }

    final categoryStyle = resolveCategoryStyle(tag: tx.tag, merchant: tx.merchant);
    final categoryLabel = displayCategoryLabel(tag: tx.tag, merchant: tx.merchant);
    final isEnriched = tx.merchant != null && tx.syncStatus == SyncStatus.completed;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1F30),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: tx.syncStatus == SyncStatus.processing
              ? const Color(0xFF8B5CF6).withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.03),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: categoryStyle.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              categoryStyle.icon,
              color: categoryStyle.color,
            ),
          ),
          const SizedBox(width: 16),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.displayTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  softWrap: true,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                if (tx.displayLabel != null &&
                    tx.displayLabel!.isNotEmpty &&
                    tx.rawInput.trim() != tx.displayLabel!.trim()) ...[
                  const SizedBox(height: 2),
                  Text(
                    tx.rawInput,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                  DateFormat('MMM d, yyyy').format(tx.createdAt),
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: categoryStyle.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '#$categoryLabel',
                        style: TextStyle(
                          fontSize: 10,
                          color: categoryStyle.color,
                          fontWeight: isEnriched ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                    if (tx.tag.toLowerCase() != categoryLabel.toLowerCase()) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '#${tx.tag}',
                          style: TextStyle(fontSize: 9, color: Colors.grey[500]),
                        ),
                      ),
                    ],
                    if (tx.isRecurring) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.repeat, size: 8, color: Color(0xFF8B5CF6)),
                            SizedBox(width: 2),
                            Text(
                              'Recurring',
                              style: TextStyle(fontSize: 8, color: Color(0xFF8B5CF6)),
                            ),
                          ],
                        ),
                      ),
                    ]
                  ],
                ),
                if (tx.syncStatus == SyncStatus.failed) ...[
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: _triggerSync,
                    child: const Text(
                      'Tap to retry sync',
                      style: TextStyle(fontSize: 11, color: Colors.redAccent, decoration: TextDecoration.underline),
                    ),
                  )
                ]
              ],
            ),
          ),

          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, size: 18, color: Colors.grey[500]),
                color: const Color(0xFF1E1F30),
                onSelected: (action) {
                  if (action == 'edit') _editTransaction(tx);
                  if (action == 'delete') _deleteTransaction(tx);
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
              Text(
                formatCurrency(tx.amount),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (showSpinner) ...[
                    const SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Icon(statusIcon, size: 12, color: badgeColor),
                  const SizedBox(width: 4),
                  Text(
                    tx.syncStatus.name.toUpperCase(),
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      color: badgeColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              )
            ],
          )
        ],
      ),
    );
  }
}
