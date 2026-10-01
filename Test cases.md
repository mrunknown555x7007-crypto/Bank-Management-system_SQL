# Test Cases

This document lists manual verification tests for the constraints, triggers,
and stored procedure in `bank_management_system.sql`. Each test can be run
directly against the database after the main script has been executed once.

Run each **Test Input** and confirm it produces the **Expected Result**. A
`✅ Pass` / `❌ Fail` column is left blank for you to fill in during your own
verification run.

---

## 1. Entity Integrity & Domain Constraints

| ID | Test Case | Test Input | Expected Result | Result |
|---|---|---|---|---|
| TC-01 | Duplicate `Phone` rejected | `INSERT INTO Customer (Name, DOB, Gender, Address, City, Phone, Email, Aadhar_No) VALUES ('Test User','1990-01-01','M','Addr','City','9876500001','test@x.com','999900001111');` | Error — `Phone` already exists (`UNIQUE` violation) | |
| TC-02 | Invalid `Gender` value rejected | `INSERT INTO Customer (..., Gender, ...) VALUES (..., 'X', ...);` | Error — `X` is not a valid `ENUM('M','F','O')` value | |
| TC-03 | Negative account balance rejected | `INSERT INTO Account (Branch_ID, Type_ID, Balance) VALUES (1, 1, -500);` | Error — violates `chk_balance CHECK (Balance >= 0)` | |
| TC-04 | Zero/negative transaction amount rejected | `INSERT INTO Transaction (Account_No, Trans_Type, Amount, Balance_After) VALUES (1, 'DEPOSIT', 0, 0);` | Error — violates `CHECK (Amount > 0)` | |
| TC-05 | Invalid `IFSC_Code` length rejected | `INSERT INTO Branch (..., IFSC_Code, ...) VALUES (..., 'ABC123', ...);` | Error — violates `chk_ifsc CHECK (CHAR_LENGTH(IFSC_Code) = 11)` | |

---

## 2. Referential Integrity

| ID | Test Case | Test Input | Expected Result | Result |
|---|---|---|---|---|
| TC-06 | Account cannot reference a non-existent branch | `INSERT INTO Account (Branch_ID, Type_ID, Balance) VALUES (999, 1, 1000);` | Error — foreign key constraint fails (`Branch_ID` 999 doesn't exist) | |
| TC-07 | Deleting a branch with employees is restricted | `DELETE FROM Branch WHERE Branch_ID = 1;` (branch 1 has employees) | Error — `ON DELETE RESTRICT` on `fk_emp_branch` blocks the delete | |
| TC-08 | Deleting an account cascades to its nominees | `DELETE FROM Account WHERE Account_No = 4;` then `SELECT * FROM Nominee WHERE Account_No = 4;` | Nominee rows for account 4 are also deleted (`ON DELETE CASCADE`) — confirms `Nominee` behaves as a true weak entity | |
| TC-09 | Deleting a manager sets `Manager_ID` to NULL, not error | `DELETE FROM Employee WHERE Employee_ID = 1;` then `SELECT Manager_ID FROM Employee WHERE Employee_ID = 2;` | `Manager_ID` becomes `NULL` for employees who reported to Employee 1 (`ON DELETE SET NULL`) | |

---

## 3. Trigger Behavior

| ID | Test Case | Test Input | Expected Result | Result |
|---|---|---|---|---|
| TC-10 | Deposit increases account balance | `INSERT INTO Transaction (Account_No, Trans_Type, Amount, Description, Balance_After) VALUES (1, 'DEPOSIT', 1000, 'Test deposit', 0);` then check `Account.Balance` for account 1 | Balance increases by exactly 1000 (via `trg_before_insert_transaction` + `trg_after_insert_transaction`) | |
| TC-11 | Withdrawal exceeding balance is rejected | `INSERT INTO Transaction (Account_No, Trans_Type, Amount, Description, Balance_After) VALUES (5, 'WITHDRAWAL', 999999, 'Overdraw attempt', 0);` (account 5 has a small balance) | Error — `SIGNAL SQLSTATE '45000'`, "Insufficient balance for this transaction" | |
| TC-12 | Underage customer insert is rejected | `INSERT INTO Customer (Name, DOB, ...) VALUES ('Minor Test', CURDATE() - INTERVAL 10 YEAR, ...);` | Error — `trg_validate_customer_age` raises "Customer must be at least 18 years old" | |
| TC-13 | Balance change is audit-logged | `UPDATE Account SET Balance = Balance + 500 WHERE Account_No = 2;` then `SELECT * FROM Audit_Log WHERE Table_Name = 'Account' ORDER BY Log_ID DESC LIMIT 1;` | A new `Audit_Log` row exists showing the old and new balance | |
| TC-14 | Loan status change is audit-logged | `UPDATE Loan SET Status = 'DEFAULTED' WHERE Loan_ID = 2;` then check `Audit_Log` | A new row logs the `ACTIVE → DEFAULTED` transition | |
| TC-15 | Loan auto-closes on full repayment | Insert a `Loan_Payment` row whose cumulative total (with prior payments) meets or exceeds `Principal_Amount` for a given `Loan_ID`, then check `Loan.Status` | `Status` automatically becomes `'CLOSED'` via `trg_after_loan_payment` | |

---

## 4. Stored Procedure / TCL

| ID | Test Case | Test Input | Expected Result | Result |
|---|---|---|---|---|
| TC-16 | Successful transfer | `CALL Transfer_Funds(2, 1, 5000.00, @status); SELECT @status;` | `@status` = `'SUCCESS'`; account 2's balance decreases by 5000, account 1's increases by 5000 | |
| TC-17 | Transfer with insufficient funds is rolled back | `CALL Transfer_Funds(5, 1, 999999.00, @status); SELECT @status;` | `@status` = `'FAILED: insufficient funds'`; **neither** account's balance changes (full rollback, no partial transfer) | |
| TC-18 | Manual `SAVEPOINT`/`ROLLBACK TO` behavior | Run the manual TCL block in Section 8.3 of the SQL file, then uncomment the `ROLLBACK TO sp1;` line and re-run | Only the update *after* the savepoint is undone; the update before it is retained after `COMMIT` | |

---

## 5. Views

| ID | Test Case | Test Input | Expected Result | Result |
|---|---|---|---|---|
| TC-19 | Updatable view accepts writes | `UPDATE View_Branch_Employees SET Salary = Salary * 1.1 WHERE Employee_ID = 3;` then check `Employee.Salary` | The underlying `Employee` row is updated — confirms `View_Branch_Employees` is updatable | |
| TC-20 | Aggregate view rejects writes | `UPDATE View_Customer_Total_Balance SET Total_Balance = 0 WHERE Customer_ID = 1;` | Error — MySQL refuses the update because the view is derived from a `GROUP BY`/aggregate query | |
| TC-21 | Security view hides sensitive columns | `SELECT * FROM View_Customer_Public;` | Result set contains only `Customer_ID`, `Name`, `City`, `Phone` — no `Aadhar_No` or `Email` | |

---

## 6. Relational Algebra Queries

| ID | Test Case | Reference | Expected Result | Result |
|---|---|---|---|---|
| TC-22 | Division query correctness | Section 7.11 | Only customers holding **at least one account of every** `Account_Type` currently defined are returned. **Verified:** against the shipped seed data this correctly returns 0 rows (no customer holds all three types); inserting a CURRENT and a FIXED_DEPOSIT account for an existing SAVINGS-only customer causes that customer to appear, confirming the query logic. | |
| TC-23 | Set operations return correct row counts | Section 7.12 (`UNION`, `INTERSECT`, `EXCEPT`) | `UNION` row count ≤ `UNION ALL` row count; `INTERSECT` returns only cities present in both `Branch` and `Customer`; `EXCEPT` returns only customer cities with no branch | |
| TC-24 | Self-join produces correct manager mapping | Section 7.6 | Each employee's `Manager_Name` matches the `Name` of the employee referenced by their `Manager_ID`; employees with `Manager_ID IS NULL` show `NULL` for `Manager_Name` | |

---

## How to Reset Between Test Runs

Since several tests mutate data (transfers, deletes, status changes), reset to
a clean state before re-running the full suite:

```bash
mysql -u root -p < bank_management_system.sql
```

This drops and recreates the database from scratch, so every test starts from
the same known seed data.
