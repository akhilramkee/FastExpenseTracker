# Specification: Cross-Platform Asynchronous Expense Tracker

## 1. Architectural Blueprint & Network Topology

This system is designed with an **offline-first paradigm**. The mobile application performs instantaneous local parsing and persistence, maintaining a zero-latency user experience. Heavy categorical intelligence using the local LLM (`Qwen3-8B`) occurs entirely asynchronously over a private Tailscale mesh network.

```
[ Mobile App (iOS/Android) ]
│
▼ (Private WireGuard Tunnel via Tailscale MagicDNS)
─── WAN / Wi-Fi Interface ──────────────────────────────────────────
│
▼ [ Secure Server Home Lab Node ]
┌──────────────────────────────────────────────────────────────────┐
│                                                                  │
│   ┌───────────────────────┐          ┌───────────────────────┐   │
│   │  Lightweight API      │          │  Ollama Engine        │   │
│   │  Gateway (Go/Python)  │─────────>│  (Model: Qwen3-8B)    │   │
│   │  Port: 8080           │          │  Port: 11434          │   │
│   └──────────┬────────────┘          └───────────────────────┘   │
│              │                                                   │
│              ▼                                                   │
│   ┌───────────────────────┐                                      │
│   │  Central Database     │                                      │
│   │  (SQLite/PostgreSQL)  │                                      │
│   └───────────────────────┘                                      │
└──────────────────────────────────────────────────────────────────┘
```

---

## 2. Core Data Schema & Synchronization Lifecycle

Every transaction record contains a `sync_status` flag to manage state propagation seamlessly between disconnected networks.

### SQL Database Schema Definition (Server)
```sql
CREATE TYPE sync_status_enum AS ENUM ('pending', 'processing', 'completed', 'failed');

CREATE TABLE transactions (
    id VARCHAR(36) PRIMARY KEY,
    raw_input TEXT NOT NULL,
    amount NUMERIC(10, 2) NOT NULL,
    description TEXT,
    tag VARCHAR(50),
    merchant VARCHAR(100),
    ai_confidence NUMERIC(3,2),
    is_recurring BOOLEAN DEFAULT FALSE,
    sync_status sync_status_enum DEFAULT 'pending',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
```

### State Propagation Lifecycle

1. **`pending`**: Logged instantly on the mobile device via regex extraction. Saved to local storage.
2. **`processing`**: Scheduled batch background job detects a valid Tailscale connection and dispatches the data to the API gateway.
3. **`completed`**: The server processes the queue with Qwen3-8B, enriches the relational parameters (merchant name, true category, recurrence flags), updates the central DB, and syncs the updated state back to the mobile device.

---

## 3. Cross-Platform Client Implementations

### Option A: Flutter (Dart) Framework Implementation

#### Fast-Regex Parser (`lib/core/utils/regex_parser.dart`)

```dart
import 'package:uuid/uuid.dart';

enum SyncStatus { pending, processing, completed, failed }

class TransactionModel {
  final String id;
  final String rawInput;
  final double amount;
  final String description;
  final String tag;
  final SyncStatus syncStatus;
  final DateTime createdAt;

  TransactionModel({
    required this.id,
    required this.rawInput,
    required this.amount,
    required this.description,
    required this.tag,
    this.syncStatus = SyncStatus.pending,
    DateTime? createdAt,
  }) : this.createdAt = createdAt ?? DateTime.now();

  static TransactionModel parse(String input) {
    final cleanInput = input.trim();
    
    // 1. Extract the first matching number (decimal or integer)
    final amountRegex = RegExp(r'\d+(\.\d{1,2})?');
    final amountMatch = amountRegex.firstMatch(cleanInput);
    final amount = amountMatch != null ? double.parse(amountMatch.group(0)!) : 0.0;

    // 2. Extract a tag starting with '#' or '@'
    final tagRegex = RegExp(r'[#@](\w+)');
    final tagMatch = tagRegex.firstMatch(cleanInput);
    final tag = tagMatch != null ? tagMatch.group(1)!.toLowerCase() : 'uncategorized';

    // 3. Clean remaining text for description
    String description = cleanInput
        .replaceAll(amountMatch?.group(0) ?? '', '')
        .replaceAll(tagMatch?.group(0) ?? '', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (description.isEmpty) {
      description = "Expense under $tag";
    }

    return TransactionModel(
      id: const Uuid().v4(),
      rawInput: cleanInput,
      amount: amount,
      description: description,
      tag: tag,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'raw_input': rawInput,
      'amount': amount,
      'description': description,
      'tag': tag,
      'sync_status': syncStatus.name,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
```

#### Tailscale Network Worker (`lib/core/network/sync_worker.dart`)

```dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class SyncWorker {
  static const String serverUrl = 'http://your-tailscale-node-ip:8080/api/v1/sync';

  static Future<bool> performBackgroundSync(List<Map<String, dynamic>> pendingTransactions) async {
    if (pendingTransactions.isEmpty) return true;

    try {
      // Network Handshake Verification (Fail-fast if target node is unreachable)
      final result = await InternetAddress.lookup('your-tailscale-node-ip')
          .timeout(const Duration(seconds: 4));
      
      if (result.isEmpty || result[0].rawAddress.isEmpty) {
        return false; 
      }

      final response = await http.post(
        Uri.parse(serverUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'transactions': pendingTransactions}),
      );

      return response.statusCode == 202;
    } catch (_) {
      return false; // Fail silently to optimize battery runtime
    }
  }
}
```

---

### Option B: React Native / TypeScript Framework Implementation

#### Fast-Regex Parser (`src/core/utils/regexParser.ts`)

```typescript
import 'react-native-get-random-values';
import { v4 as uuidv4 } from 'uuid';

export type SyncStatus = 'pending' | 'processing' | 'completed' | 'failed';

export interface Transaction {
  id: string;
  rawInput: string;
  amount: number;
  description: string;
  tag: string;
  syncStatus: SyncStatus;
  createdAt: string;
}

export function parseSingleLineEntry(input: string): Transaction {
  const cleanInput = input.trim();

  const amountMatch = cleanInput.match(/\d+(\.\d{1,2})?/);
  const amount = amountMatch ? parseFloat(amountMatch[0]) : 0.0;

  const tagMatch = cleanInput.match(/[#@](\w+)/);
  const tag = tagMatch ? tagMatch[1].toLowerCase() : 'uncategorized';

  let description = cleanInput
    .replace(amountMatch ? amountMatch[0] : '', '')
    .replace(tagMatch ? tagMatch[0] : '', '')
    .replace(/\s+/g, ' ')
    .trim();

  if (!description) {
    description = `Expense under ${tag}`;
  }

  return {
    id: uuidv4(),
    rawInput: cleanInput,
    amount,
    description,
    tag,
    syncStatus: 'pending',
    createdAt: new Date().toISOString(),
  };
}
```

#### Tailscale Network Worker (`src/core/network/syncWorker.ts`)

```typescript
import { Transaction } from './regexParser';

const SERVER_URL = 'http://your-tailscale-node-ip:8080/api/v1/sync';

export async function performBackgroundSync(pendingTransactions: Transaction[]): Promise<boolean> {
  if (pendingTransactions.length === 0) return true;

  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 4000);

    const response = await fetch(SERVER_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ transactions: pendingTransactions }),
      signal: controller.signal,
    });

    clearTimeout(timeoutId);
    return response.status === 202;
  } catch (error) {
    return false;
  }
}
```

---

## 4. Backend Gateway & LLM Prompting Interface

The server gateway acts as an asynchronous engine worker pool. When a network sync chunk lands, the application acknowledges the pipeline instantly, dropping processing locks on the client.

### Ollama Model Hyperparameters

* **Inference Model**: `qwen3:8b`
* **Temperature Constraint**: `0.1` (Forces programmatic deterministic data output)
* **API Ingestion Format Requirement**: `format: "json"`

### Structured System Instruction Engine Prompt

```text
You are an isolated financial intelligence string extraction parser microservice engine.
Your specific structural instructions are to accept raw, single-line data entries and resolve them into perfectly compliant structured parameters without additional narrative text wrapper outputs.

You must format output streams to match the parameters of this designated JSON schema map:
{
  "amount": float,
  "category": string,
  "confidence": float (range 0.00 to 1.00),
  "merchant": string or null,
  "is_recurring": boolean
}
```

### Data Pipeline Processing Target Verification Sample

* **Input payload passed down from gateway background thread**: `"1450 zoom subscription renewal @work"`
* **Ollama Raw JSON Response Stream**:

```json
{
  "amount": 1450.00,
  "category": "Software & Subscriptions",
  "confidence": 0.99,
  "merchant": "Zoom",
  "is_recurring": true
}
```
