import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:intl/intl.dart';
import 'core/db/database_helper.dart';
import 'core/models/transaction_model.dart';
import 'core/network/sync_worker.dart';

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
      title: 'AuraExpense',
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
  
  List<TransactionModel> _transactions = [];
  bool _isSyncing = false;
  bool _serverOnline = false;
  String _livePreviewText = "Type something like: 1450 zoom subscription renewal @work";
  Timer? _statusPollTimer;
  Timer? _serverStatusTimer;

  // Live preview parser state
  double _parsedAmount = 0.0;

  @override
  void initState() {
    super.initState();
    _loadTransactions();
    _checkServerStatus();
    
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
  }

  @override
  void dispose() {
    _statusPollTimer?.cancel();
    _serverStatusTimer?.cancel();
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
        _livePreviewText = "Type something like: 1450 zoom subscription renewal @work";
        _parsedAmount = 0.0;
      });
      return;
    }

    final parsed = TransactionModel.parse(text);
    setState(() {
      _parsedAmount = parsed.amount;
      _livePreviewText = "Preview — Amount: \$${parsed.amount.toStringAsFixed(2)}  •  Tag: #${parsed.tag}";
    });
  }

  Future<void> _saveTransaction() async {
    final text = _entryController.text.trim();
    if (text.isEmpty) return;

    final parsedTx = TransactionModel.parse(text);
    await _dbHelper.insertTransaction(parsedTx);
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
      // 1. Push pending
      await _syncWorker.performBackgroundSync();
      // 2. Reload local list
      await _loadTransactions();
      // 3. Pull latest enriched changes
      await _syncWorker.pullSyncUpdates();
      // 4. Reload final
      await _loadTransactions();
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  double _calculateTotalExpenses() {
    return _transactions.fold(0.0, (sum, item) => sum + item.amount);
  }

  @override
  Widget build(BuildContext context) {
    final totalExpense = _calculateTotalExpenses();
    final formatter = NumberFormat.currency(symbol: '\$');

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'AuraExpense',
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
                  // Sync Button
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
              const SizedBox(height: 24),

              // Total Expense Glassmorphic Card
              Container(
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
                      '${_transactions.length} Transactions Logged',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Input Box
              Container(
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
                        hintText: 'Add expense (e.g. 45.90 dinner @night #food)',
                        hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
                        border: InputBorder.none,
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
              const SizedBox(height: 24),

              // Transaction List Header
              Row(
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
              const SizedBox(height: 12),

              // Transaction List
              Expanded(
                child: _transactions.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.receipt_long_rounded, size: 64, color: Colors.grey[700]),
                            const SizedBox(height: 16),
                            Text(
                              'No transactions yet.',
                              style: TextStyle(color: Colors.grey[500], fontSize: 16),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _transactions.length,
                        physics: const BouncingScrollPhysics(),
                        itemBuilder: (context, index) {
                          final tx = _transactions[index];
                          return _buildTransactionCard(tx);
                        },
                      ),
              ),
            ],
          ),
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

    final displayTag = tx.merchant ?? tx.tag;
    final isEnriched = tx.merchant != null;

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
          // Category Icon/Avatar
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F101A),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isEnriched ? Icons.storefront_rounded : Icons.label_outline_rounded,
              color: isEnriched ? const Color(0xFF06B6D4) : Colors.white60,
            ),
          ),
          const SizedBox(width: 16),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '#$displayTag',
                        style: TextStyle(
                          fontSize: 10,
                          color: isEnriched ? const Color(0xFF06B6D4) : Colors.grey[400],
                          fontWeight: isEnriched ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
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

          // Price and Sync Status
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$${tx.amount.toStringAsFixed(2)}',
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
