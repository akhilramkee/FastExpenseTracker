import '../db/database_helper.dart';
import '../models/transaction_model.dart';

class ExpenseEntryService {
  final DatabaseHelper _dbHelper;

  ExpenseEntryService({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper();

  Future<TransactionModel> addFromText(String text) async {
    final parsed = TransactionModel.parse(text.trim());
    await _dbHelper.insertTransaction(parsed);
    return parsed;
  }
}
