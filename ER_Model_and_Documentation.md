# Bank Management System (Documentation)

This companion document covers the *theory* side of the syllabus that a `.sql`
file can only gesture at with comments: the ER model behind the schema, the
normalization walkthrough, Codd's rules, a short UML note, and a relational
algebra ↔ SQL cheat-sheet mapped to the queries in `bank_management_system.sql`.

---

## 1. ER Model Overview

**Entity sets:** Branch, Employee, Customer, Account_Type, Account, Loan_Type,
Loan, Loan_Payment, Card, Transaction.

**Weak entity set:** `Nominee`.
A nominee has no independent existence — it is only meaningful in the context
of the account it is attached to. Its **partial key** is `Nominee_Name`; combined
with the **owner entity's key** `Account_No`, it forms the nominee's full
identifying key. Participation of Nominee in the `has_nominee` relationship is
**total** (every nominee row must reference a live account), while an
Account's participation in that same relationship is **partial** (an account
may have zero nominees). This is why `Account_No` in `Nominee` is `ON DELETE
CASCADE` — the weak entity cannot outlive its owner.

**Relationships and cardinalities:**

| Relationship | Cardinality | Notes |
|---|---|---|
| Branch → Employee | 1 : N | An employee works at exactly one branch |
| Employee → Employee | 1 : N (recursive) | `Manager_ID` self-references `Employee` |
| Branch → Account | 1 : N | An account is opened at one branch |
| Account_Type → Account | 1 : N | Lookup entity for interest rate / min balance |
| Customer ↔ Account | M : N | Resolved via `Customer_Account` (joint accounts) |
| Account → Nominee | 1 : N | Weak entity, identifying relationship |
| Account → Transaction | 1 : N | |
| Account → Card | 1 : N | |
| Customer → Loan | 1 : N | |
| Branch, Loan_Type → Loan | 1 : N each | |
| Loan → Loan_Payment | 1 : N | |

### Constraints modeled
- **Key constraints** — every strong entity has a surrogate primary key
  (`AUTO_INCREMENT`); the weak entity `Nominee` uses a composite key.
- **Participation constraints** — `NOT NULL` foreign keys enforce total
  participation (e.g. every `Account` *must* have a `Branch_ID`).
- **Mapping cardinality** — enforced by where the foreign key lives (the "many"
  side always holds the FK) and by the `Customer_Account` bridge table for the
  M:N case.
- **Domain constraints** — `ENUM`, `CHECK`, and column types (e.g.
  `Share_Percent BETWEEN 0 AND 100`).

### Common ERD issues avoided here
- **Fan trap** — avoided by not directly connecting Customer→Loan→Payment as a
  single flattened relation; each relationship is its own table so aggregation
  paths stay unambiguous.
- **Chasm trap** — avoided by making the Customer↔Account relationship
  explicit (`Customer_Account`) rather than implying it through a shared
  branch, which would wrongly suggest every branch customer holds every branch
  account.
- **Redundant relationships** — Account_Type and Loan_Type are separated out
  instead of repeating `Interest_Rate` on every Account/Loan row.

### Introduction to UML (context)
An ER diagram and a UML class diagram describe the same structure with
different notation: an **entity** becomes a **class**, an **attribute**
becomes a class **field**, and a **relationship** becomes an **association**
(with the same multiplicity notation, e.g. `1..*`, `0..1`). The recursive
Employee–Manager relationship above would be drawn in UML as a class `Employee`
with a self-association labeled "manages" (`1` on the manager end, `*` on the
managed-employee end). Weak entities like `Nominee` are typically shown in UML
as a class with a **composition** (filled diamond) link to `Account`, since
composition also implies "cannot exist without its owner."

---

## 2. Normalization Walkthrough

Imagine the naive, unnormalized starting point a beginner might design:

```
BankInfo(Customer_ID, Customer_Name, Phone, Account_No, Account_Type,
         Interest_Rate, Branch_Name, Branch_City, Loan_ID, Loan_Type,
         Loan_Interest_Rate, Nominee1_Name, Nominee2_Name)
```

**1NF (atomic values, no repeating groups):**
`Nominee1_Name, Nominee2_Name` are a repeating group → violates 1NF.
*Fix:* move nominees into their own table, one row per nominee
(`Nominee(Account_No, Nominee_Name, ...)`), as done in the schema.

**2NF (no partial dependency on part of a composite key):**
Once the key is composite (e.g. `(Customer_ID, Account_No)`), a column like
`Customer_Name` depends only on `Customer_ID`, not on the whole key → partial
dependency, violates 2NF.
*Fix:* split into `Customer(Customer_ID, Customer_Name, ...)` and
`Customer_Account(Customer_ID, Account_No, ...)` — exactly the bridge table in
the schema.

**3NF (no transitive dependency on non-key attributes):**
`Interest_Rate` and `Branch_City` depend on `Account_Type`/`Branch_Name`
respectively, not directly on `Account_No` → transitive dependency, violates 3NF.
*Fix:* pull them into their own lookup entities — `Account_Type` and `Branch` —
which is exactly why those tables exist in the schema instead of duplicating
`Interest_Rate` on every account row.

**BCNF (every determinant is a candidate key):**
Consider a hypothetical `Assigned(Employee_ID, Branch_ID, Designation)` where
each `Designation` at a branch is always handled by one specific `Employee_ID`,
but an employee can hold that designation at only one branch. Here
`Designation → Branch_ID` holds even though `Designation` alone isn't a
candidate key → violates BCNF.
*Fix:* decompose into `Designation_Branch(Designation, Branch_ID)` and
`Employee_Designation(Employee_ID, Designation)`. The schema avoids this trap
by keeping `Designation` a plain descriptive attribute of `Employee`, not a
key-like attribute participating in a dependency of its own.

**Multivalued dependencies & 4NF:**
Suppose we tried to store a customer's `(Account_No, Nominee_Name)` pairs and
`(Account_No, Card_Number)` pairs in **one** combined table
`Account_Extras(Account_No, Nominee_Name, Card_Number)`. Nominees and cards are
independent of each other given an account — this is a **multivalued
dependency** (`Account_No →→ Nominee_Name` and `Account_No →→ Card_Number`),
and cramming both into one table forces a spurious cross-product of every
nominee with every card. *Fix:* 4NF requires splitting them into two
independent tables — which is exactly why `Nominee` and `Card` are separate
tables in the schema, each with their own FK back to `Account`, rather than
one combined table.

---

## 3. Codd's 12 Rules (brief, as commonly examined)

1. **Information Rule** — all data is represented as values in tables (done:
   every fact here lives in a row/column, no side files).
2. **Guaranteed Access** — every value is reachable by table + primary key +
   column name (`Account.Balance` via `Account_No`).
3. **Systematic NULL handling** — `NULL` represents "missing/inapplicable"
   uniformly (e.g. `Employee.Manager_ID` is `NULL` for branch managers).
4. **Dynamic online catalog** — the schema is itself queryable via
   `INFORMATION_SCHEMA` (see Section 8.4 of the SQL file).
5. **Comprehensive sublanguage** — SQL covers definition, manipulation,
   constraints, and transaction control in one language.
6. **View updating** — updatable views must be updatable through the DBMS;
   demonstrated by `View_Branch_Employees` (updatable) vs.
   `View_Customer_Total_Balance` (not updatable, since it aggregates).
7. **High-level insert/update/delete** — DML operates on whole sets, not
   record-at-a-time (e.g. the `UPDATE ... WHERE Designation = 'Teller'`
   statement updates every matching row in one statement).
8. **Physical data independence** — adding an index (Section 2 of the SQL
   file) doesn't change any application query.
9. **Logical data independence** — adding `View_Customer_Public` doesn't
   require changing the underlying `Customer` table.
10. **Integrity independence** — constraints (`CHECK`, `FOREIGN KEY`) live in
    the schema itself, not scattered across application code.
11. **Distribution independence** — conceptually, queries would work the same
    if `bank_management_system` were split across servers (not implemented
    here, but the principle holds since no query hardcodes physical location).
12. **Non-subversion** — there's no row-at-a-time backdoor that could bypass
    the `CHECK` constraints or triggers defined at the set level.

---

## 4. Relational Algebra (ALL SQL OPERATION )

All operators below are demonstrated with real queries in Section 7 of
`bank_management_system.sql`.

| Relational Algebra | Symbol | SQL Equivalent | Example in the SQL file |
|---|---|---|---|
| Selection | σ (sigma) | `WHERE` | 7.1 |
| Projection | π (pi) | `SELECT <cols>` (+ `DISTINCT` to drop dupes) | 7.1, 7.2 |
| Rename | ρ (rho) | `AS` (table/column alias) | 7.13 |
| Union | ∪ | `UNION` / `UNION ALL` | 7.12 |
| Set Difference | − | `EXCEPT` | 7.12 |
| Intersection | ∩ | `INTERSECT` | 7.12 |
| Cartesian Product | × | `CROSS JOIN` / comma join | (implicit basis of all joins) |
| Natural Join / Theta Join | ⋈ | `JOIN ... ON` | 7.3–7.6, 7.16 |
| Division | ÷ | `NOT EXISTS` (double-negation pattern) | 7.11 |
| Grouping / Aggregation | (extension, γ) | `GROUP BY` + aggregate functions | 7.7 |
| Ungrouping | — | plain `SELECT` without `GROUP BY` on the base table | n/a — grouping is undone by querying the base table directly instead of the grouped result |

**Tuple Relational Calculus (TRC)** describes *what* to retrieve rather than
*how*:
`{ t | t ∈ Customer ∧ ∃ l ∈ Loan (l.Customer_ID = t.Customer_ID) }`
reads as "all customer tuples `t` such that there exists a loan tuple
referencing them" — translated directly into the `EXISTS` subquery in
Section 7.15 of the SQL file.

**Relational comparison** (used throughout `WHERE`/`HAVING` clauses): `=, <>,
<, >, <=, >=` compare attribute values directly (e.g.
`a.Balance > (SELECT AVG(Balance) FROM Account)` in query 7.8), while
`IN`/`NOT IN`/`EXISTS`/`NOT EXISTS` compare a value or tuple against a
*set* produced by a subquery — the mechanism behind the division query (7.11).

---

## 5. Logical View of Data, Keys, and Integrity Rules

- **Logical view**: application code and the query showcase interact only
  with tables/views — never with the physical `.ibd` files MySQL stores data
  in. Views such as `View_Customer_Public` further narrow that logical view
  for security purposes (hiding `Aadhar_No`/`Email`).
- **Keys**: every table has a declared **primary key** (surrogate or
  composite); **candidate keys** exist too (e.g. `Customer.Phone`,
  `Customer.Aadhar_No`, `Customer.Email` are all unique and could each serve
  as the PK — `Customer_ID` was simply chosen as the **primary** one).
  **Foreign keys** implement all the relationships listed in Section 1.
- **Entity integrity**: no primary key column may be `NULL` — guaranteed by
  MySQL for every `PRIMARY KEY` declared in the schema.
- **Referential integrity**: every foreign key must match an existing primary
  key value or be `NULL` where nullable (e.g. `Employee.Manager_ID`) —
  enforced by the `FOREIGN KEY ... REFERENCES` clauses, with `ON DELETE
  CASCADE`/`RESTRICT`/`SET NULL` chosen per relationship's real-world
  semantics (a nominee cannot survive its account being deleted; a branch
  cannot be deleted while employees still reference it).
- **Domain integrity**: `CHECK` constraints and `ENUM` types keep values
  within a valid domain (e.g. `Status` can only be `ACTIVE`, `CLOSED`, or
  `FROZEN`).

---

## 6. How to Run

```bash
mysql -u root -p < bank_management_system.sql
```

Run the whole file top to bottom — table creation, indexes, views, triggers,
the stored procedure, sample data, and the query showcase are all in
dependency order. If your server has binary logging enabled and you hit error
1418 when creating `NEXT_VAL`, run
`SET GLOBAL log_bin_trust_function_creators = 1;` first (requires `SUPER`).

`INTERSECT`/`EXCEPT` require **MySQL LATEST VERSION**; on older 8.0.x builds,
replace them with `IN`/`NOT IN` equivalents (shown as comments would be a good
follow-up exercise).
