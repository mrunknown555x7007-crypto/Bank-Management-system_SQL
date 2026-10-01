
                                                              -- BANK MANAGEMENT SYSTEM  |  Advanced MySQL Database Project


                                              -- Covers: ER-Model -> Relational Model -> Normalization (1NF-BCNF, 4NF) -> SQL DDL/DML
                                              --         Constraints, Views, Indexes, Sequence-simulation, Synonym-simulation,
                                              --         Triggers, Stored Procedures, TCL, Joins, Subqueries, Set Ops, Aggregates.


DROP DATABASE IF EXISTS bank_management_system;
CREATE DATABASE bank_management_system
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;
USE bank_management_system;


-- SECTION 1: ER MODEL -> RELATIONAL SCHEMA (via Normalization, 3NF/BCNF minimum) AS FOLLOWED IN SYLLABUS 
-- =====================================================================================
-- ENTITY SETS   : Branch, Employee, Customer, Account_Type, Account, Loan_Type, Loan,
--                 Card, Loan_Payment, Transaction
-- WEAK ENTITY   : Nominee  (existence-dependent on Account; partial key = Nominee_Name,
--                 discriminator combined with owner Account_No forms the identifying key)
-- RELATIONSHIPS : Branch --1:N-- Employee
--                 Branch --1:N-- Account
--                 Customer --M:N-- Account  
--                 Account --1:N-- Transaction
--                 Account --1:1/1:N-- Card
--                 Customer --1:N-- Loan
--                 Loan --1:N-- Loan_Payment
--                 Employee --1:1(recursive) , Employee (Manager supervises Employee)


-- ---------------------------------------------------------------------------
-- 1. BRANCH  (Strong entity)
-- ---------------------------------------------------------------------------
CREATE TABLE Branch (
    Branch_ID      INT AUTO_INCREMENT PRIMARY KEY,
    Branch_Name    VARCHAR(80)  NOT NULL,
    City           VARCHAR(50)  NOT NULL,
    State          VARCHAR(50)  NOT NULL,
    IFSC_Code      CHAR(11)     NOT NULL UNIQUE,
    Contact_No     VARCHAR(15)  NOT NULL,
    CONSTRAINT chk_ifsc CHECK (CHAR_LENGTH(IFSC_Code) = 11)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- 2. EMPLOYEE  (Strong entity; recursive 1:1/1:N relationship = Manager)
-- ---------------------------------------------------------------------------
CREATE TABLE Employee (
    Employee_ID    INT AUTO_INCREMENT PRIMARY KEY,
    Name           VARCHAR(80)  NOT NULL,
    Designation    VARCHAR(50)  NOT NULL,
    Branch_ID      INT          NOT NULL,
    Manager_ID     INT          DEFAULT NULL,
    Salary         DECIMAL(10,2) NOT NULL CHECK (Salary > 0),
    Hire_Date      DATE         NOT NULL,
    Email          VARCHAR(100) UNIQUE,
    CONSTRAINT fk_emp_branch  FOREIGN KEY (Branch_ID)  REFERENCES Branch(Branch_ID)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_emp_manager FOREIGN KEY (Manager_ID) REFERENCES Employee(Employee_ID)
        ON UPDATE CASCADE ON DELETE SET NULL
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- 3. CUSTOMER  (Strong entity)
-- ---------------------------------------------------------------------------
CREATE TABLE Customer (
    Customer_ID    INT AUTO_INCREMENT PRIMARY KEY,
    Name           VARCHAR(80)  NOT NULL,
    DOB            DATE         NOT NULL,
    Gender         ENUM('M','F','O') NOT NULL,
    Address        VARCHAR(200) NOT NULL,
    City           VARCHAR(50)  NOT NULL,
    Phone          VARCHAR(15)  NOT NULL UNIQUE,
    Email          VARCHAR(100) UNIQUE,
    Aadhar_No      CHAR(12)     NOT NULL UNIQUE,
    Created_At     TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
    -- NOTE: an "age >= 18" rule is NOT enforced here as a CHECK constraint because
    -- MySQL disallows non-deterministic functions (CURDATE(), NOW()) inside CHECK().
    -- It is enforced instead by trg_validate_customer_age below.
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- 4. ACCOUNT_TYPE  (lookup entity - pulled out during normalization to remove
--    a transitive/repeating-group dependency: Interest_Rate & Min_Balance
--    depend only on the account *type*, not on each Account row -> 3NF fix)
-- ---------------------------------------------------------------------------
CREATE TABLE Account_Type (
    Type_ID        INT AUTO_INCREMENT PRIMARY KEY,
    Type_Name      VARCHAR(30)  NOT NULL UNIQUE,   -- SAVINGS, CURRENT, FIXED_DEPOSIT
    Interest_Rate  DECIMAL(4,2) NOT NULL DEFAULT 0.00,
    Min_Balance    DECIMAL(10,2) NOT NULL DEFAULT 0.00
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- 5. ACCOUNT  (Strong entity; Branch 1:N, Account_Type 1:N)
-- ---------------------------------------------------------------------------
CREATE TABLE Account (
    Account_No     BIGINT AUTO_INCREMENT PRIMARY KEY,
    Branch_ID      INT NOT NULL,
    Type_ID        INT NOT NULL,
    Balance        DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    Open_Date      DATE NOT NULL DEFAULT (CURRENT_DATE),
    Status         ENUM('ACTIVE','CLOSED','FROZEN') NOT NULL DEFAULT 'ACTIVE',
    CONSTRAINT fk_acc_branch FOREIGN KEY (Branch_ID) REFERENCES Branch(Branch_ID),
    CONSTRAINT fk_acc_type   FOREIGN KEY (Type_ID)   REFERENCES Account_Type(Type_ID),
    CONSTRAINT chk_balance CHECK (Balance >= 0)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- 6. CUSTOMER_ACCOUNT  (Associative/bridge entity resolving the M:N
-- ---------------------------------------------------------------------------
CREATE TABLE Customer_Account (
    Customer_ID       INT NOT NULL,
    Account_No        BIGINT NOT NULL,
    Relationship_Type ENUM('PRIMARY','JOINT','GUARDIAN') NOT NULL DEFAULT 'PRIMARY',
    Linked_Date       DATE NOT NULL DEFAULT (CURRENT_DATE),
    PRIMARY KEY (Customer_ID, Account_No),
    CONSTRAINT fk_ca_cust FOREIGN KEY (Customer_ID) REFERENCES Customer(Customer_ID)
        ON DELETE CASCADE,
    CONSTRAINT fk_ca_acc  FOREIGN KEY (Account_No)  REFERENCES Account(Account_No)
        ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- 7. NOMINEE  (WEAK ENTITY SET: cannot exist without an owning Account.
--   @ Identifying relationship = "has_nominee". Partial key = Nominee_Name;
--    @ full/composite key = (Account_No, Nominee_Name).)
-- ---------------------------------------------------------------------------
CREATE TABLE Nominee (
    Account_No     BIGINT       NOT NULL,
    Nominee_Name   VARCHAR(80)  NOT NULL,   -- partial key (discriminator)
    Relation       VARCHAR(30)  NOT NULL,
    Nominee_Phone  VARCHAR(15),
    Share_Percent  DECIMAL(5,2) NOT NULL DEFAULT 100.00 CHECK (Share_Percent BETWEEN 0 AND 100),
    PRIMARY KEY (Account_No, Nominee_Name),   -- composite key = owner key + partial key
    CONSTRAINT fk_nominee_acc FOREIGN KEY (Account_No) REFERENCES Account(Account_No)
        ON DELETE CASCADE       -- total participation: nominee dies with the account
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- 8. TRANSACTION  (Strong entity, weak-ish in spirit but given a surrogate key)
-- ---------------------------------------------------------------------------
CREATE TABLE Transaction (
    Transaction_ID  BIGINT AUTO_INCREMENT PRIMARY KEY,
    Account_No      BIGINT NOT NULL,
    Trans_Type      ENUM('DEPOSIT','WITHDRAWAL','TRANSFER_IN','TRANSFER_OUT') NOT NULL,
    Amount          DECIMAL(12,2) NOT NULL CHECK (Amount > 0),
    Trans_Date      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    Description     VARCHAR(150),
    Balance_After   DECIMAL(12,2) NOT NULL,
    CONSTRAINT fk_txn_acc FOREIGN KEY (Account_No) REFERENCES Account(Account_No)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- 9. LOAN_TYPE (lookup entity, same 3NF rationale as Account_Type)
-- ---------------------------------------------------------------------------
CREATE TABLE Loan_Type (
    Loan_Type_ID   INT AUTO_INCREMENT PRIMARY KEY,
    Loan_Name      VARCHAR(40) NOT NULL UNIQUE,   -- HOME, PERSONAL, AUTO, EDUCATION
    Interest_Rate  DECIMAL(4,2) NOT NULL,
    Max_Amount     DECIMAL(12,2) NOT NULL,
    Tenure_Months  INT NOT NULL
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- 10. LOAN  (Customer 1:N, Branch 1:N, Loan_Type 1:N)
-- ---------------------------------------------------------------------------
CREATE TABLE Loan (
    Loan_ID         INT AUTO_INCREMENT PRIMARY KEY,
    Customer_ID     INT NOT NULL,
    Branch_ID       INT NOT NULL,
    Loan_Type_ID    INT NOT NULL,
    Principal_Amount DECIMAL(12,2) NOT NULL CHECK (Principal_Amount > 0),
    Sanction_Date   DATE NOT NULL,
    EMI_Amount      DECIMAL(10,2) NOT NULL,
    Status          ENUM('ACTIVE','CLOSED','DEFAULTED') NOT NULL DEFAULT 'ACTIVE',
    CONSTRAINT fk_loan_cust   FOREIGN KEY (Customer_ID)  REFERENCES Customer(Customer_ID),
    CONSTRAINT fk_loan_branch FOREIGN KEY (Branch_ID)    REFERENCES Branch(Branch_ID),
    CONSTRAINT fk_loan_type   FOREIGN KEY (Loan_Type_ID) REFERENCES Loan_Type(Loan_Type_ID)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- 11. LOAN_PAYMENT (Loan 1:N)
-- ---------------------------------------------------------------------------
CREATE TABLE Loan_Payment (
    Payment_ID     BIGINT AUTO_INCREMENT PRIMARY KEY,
    Loan_ID        INT NOT NULL,
    Payment_Date   DATE NOT NULL DEFAULT (CURRENT_DATE),
    Amount_Paid    DECIMAL(10,2) NOT NULL CHECK (Amount_Paid > 0),
    Payment_Mode   ENUM('CASH','ONLINE','CHEQUE','AUTO_DEBIT') NOT NULL,
    CONSTRAINT fk_pay_loan FOREIGN KEY (Loan_ID) REFERENCES Loan(Loan_ID)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- 12. CARD (Account 1:N)
-- ---------------------------------------------------------------------------
CREATE TABLE Card (
    Card_ID        INT AUTO_INCREMENT PRIMARY KEY,
    Account_No     BIGINT NOT NULL,
    Card_Type      ENUM('DEBIT','CREDIT') NOT NULL,
    Card_Number    CHAR(16) NOT NULL UNIQUE,
    Expiry_Date    DATE NOT NULL,
    Card_Status    ENUM('ACTIVE','BLOCKED','EXPIRED') NOT NULL DEFAULT 'ACTIVE',
    CONSTRAINT fk_card_acc FOREIGN KEY (Account_No) REFERENCES Account(Account_No)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- 13. AUDIT_LOG (supports trigger-based auditing demo)
-- ---------------------------------------------------------------------------
CREATE TABLE Audit_Log (
    Log_ID       BIGINT AUTO_INCREMENT PRIMARY KEY,
    Table_Name   VARCHAR(40) NOT NULL,
    Operation    VARCHAR(10) NOT NULL,
    Record_Key   VARCHAR(50) NOT NULL,
    Old_Value    VARCHAR(255),
    New_Value    VARCHAR(255),
    Changed_At   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- 14. SEQUENCE SIMULATION
--     Plain MySQL (unlike Oracle/MariaDB) has no CREATE SEQUENCE object.
--     AUTO_INCREMENT already covers surrogate keys above; this table +
--     function shows the *concept* of a sequence generator for cases where
--     you need a custom, gap-controlled numbering scheme (e.g. cheque
--     numbers, receipt numbers).
-- ---------------------------------------------------------------------------
CREATE TABLE Sequence_Generator (
    Seq_Name      VARCHAR(30) PRIMARY KEY,
    Current_Value BIGINT NOT NULL DEFAULT 0
) ENGINE=InnoDB;

INSERT INTO Sequence_Generator VALUES ('RECEIPT_NO', 1000);

DELIMITER $$
CREATE FUNCTION NEXT_VAL(p_seq_name VARCHAR(30))
RETURNS BIGINT
DETERMINISTIC
MODIFIES SQL DATA
BEGIN
    DECLARE v_next BIGINT;
    UPDATE Sequence_Generator
       SET Current_Value = Current_Value + 1
     WHERE Seq_Name = p_seq_name;
    SELECT Current_Value INTO v_next
      FROM Sequence_Generator WHERE Seq_Name = p_seq_name;
    RETURN v_next;
END$$
DELIMITER ;

-- ---------------------------------------------------------------------------
-- 15. SYNONYM SIMULATION
--     MySQL has no CREATE SYNONYM (Oracle-only feature). A simple VIEW that
--     just re-exposes a table under another name achieves the same alias
--     effect and is the standard MySQL workaround.
-- ---------------------------------------------------------------------------
CREATE VIEW Cust AS SELECT * FROM Customer;   -- "synonym" for Customer
USE bank_management_system;

-- =====================================================================================
-- SECTION 2: INDEXES  (speed up FK lookups / frequent search columns)
-- =====================================================================================
CREATE INDEX idx_customer_phone   ON Customer(Phone);
CREATE INDEX idx_customer_city    ON Customer(City);
CREATE INDEX idx_account_branch   ON Account(Branch_ID);
CREATE INDEX idx_account_type     ON Account(Type_ID);
CREATE INDEX idx_txn_account_date ON Transaction(Account_No, Trans_Date);
CREATE INDEX idx_loan_customer    ON Loan(Customer_ID);
-- Card_Number is already UNIQUE via the table definition, so no extra index is needed.

-- =====================================================================================
-- SECTION 3: VIEWS
-- =====================================================================================

-- 3.1 Simple, single-table, UPDATABLE view (updates on it propagate to Employee).
CREATE VIEW View_Branch_Employees AS
SELECT Employee_ID, Name, Designation, Branch_ID, Salary
FROM Employee
WHERE Salary > 0;
-- Demo: UPDATE View_Branch_Employees SET Salary = Salary * 1.1 WHERE Employee_ID = 1;
-- works fine because the view maps 1:1 onto rows/columns of a single base table.

-- 3.2 Complex, multi-table + aggregate view -> NOT updatable (illustrates the
--     table vs. view distinction: aggregates/joins/GROUP BY break updatability).
CREATE VIEW View_Customer_Total_Balance AS
SELECT c.Customer_ID,
       c.Name,
       COUNT(ca.Account_No)      AS Num_Accounts,
       SUM(a.Balance)            AS Total_Balance
FROM Customer c
JOIN Customer_Account ca ON c.Customer_ID = ca.Customer_ID
JOIN Account a           ON ca.Account_No = a.Account_No
GROUP BY c.Customer_ID, c.Name;

-- 3.3 Business view: active loans with customer & branch context (security use case
--     -- a teller role can be granted SELECT on this view without direct table access).
CREATE VIEW View_Active_Loans AS
SELECT l.Loan_ID, c.Name AS Customer_Name, b.Branch_Name,
       lt.Loan_Name, l.Principal_Amount, l.EMI_Amount, l.Sanction_Date
FROM Loan l
JOIN Customer c   ON l.Customer_ID = c.Customer_ID
JOIN Branch b     ON l.Branch_ID = b.Branch_ID
JOIN Loan_Type lt ON l.Loan_Type_ID = lt.Loan_Type_ID
WHERE l.Status = 'ACTIVE';

-- 3.4 Column/row-restricted security view: hides Aadhar_No & Email from general staff.
CREATE VIEW View_Customer_Public AS
SELECT Customer_ID, Name, City, Phone
FROM Customer;

-- =====================================================================================
-- SECTION 4: TRIGGERS
-- =====================================================================================

DELIMITER $$

-- 4.0 Enforce "customer must be 18+" -- moved here from a CHECK constraint because
--     MySQL CHECK() does not allow non-deterministic functions such as CURDATE().
CREATE TRIGGER trg_validate_customer_age
BEFORE INSERT ON Customer
FOR EACH ROW
BEGIN
    IF NEW.DOB > DATE_SUB(CURDATE(), INTERVAL 18 YEAR) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Customer must be at least 18 years old';
    END IF;
END$$

-- 4.1 Keep Account.Balance in sync automatically whenever a Transaction row is
--     inserted, and reject a withdrawal that would overdraw the account.
CREATE TRIGGER trg_before_insert_transaction
BEFORE INSERT ON Transaction
FOR EACH ROW
BEGIN
    DECLARE v_balance DECIMAL(12,2);
    SELECT Balance INTO v_balance FROM Account WHERE Account_No = NEW.Account_No;

    IF NEW.Trans_Type IN ('WITHDRAWAL','TRANSFER_OUT') AND v_balance < NEW.Amount THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Insufficient balance for this transaction';
    END IF;

    IF NEW.Trans_Type IN ('DEPOSIT','TRANSFER_IN') THEN
        SET NEW.Balance_After = v_balance + NEW.Amount;
    ELSE
        SET NEW.Balance_After = v_balance - NEW.Amount;
    END IF;
END$$

CREATE TRIGGER trg_after_insert_transaction
AFTER INSERT ON Transaction
FOR EACH ROW
BEGIN
    IF NEW.Trans_Type IN ('DEPOSIT','TRANSFER_IN') THEN
        UPDATE Account SET Balance = Balance + NEW.Amount WHERE Account_No = NEW.Account_No;
    ELSE
        UPDATE Account SET Balance = Balance - NEW.Amount WHERE Account_No = NEW.Account_No;
    END IF;
END$$

-- 4.2 Audit trail: log every balance change on Account (BEFORE UPDATE so we can
--     see both OLD and NEW values).
CREATE TRIGGER trg_audit_account_update
BEFORE UPDATE ON Account
FOR EACH ROW
BEGIN
    IF OLD.Balance <> NEW.Balance THEN
        INSERT INTO Audit_Log(Table_Name, Operation, Record_Key, Old_Value, New_Value)
        VALUES ('Account', 'UPDATE', CAST(OLD.Account_No AS CHAR),
                CAST(OLD.Balance AS CHAR), CAST(NEW.Balance AS CHAR));
    END IF;
END$$

-- 4.3 Audit trail on Loan status changes (e.g. ACTIVE -> CLOSED/DEFAULTED).
CREATE TRIGGER trg_audit_loan_status
AFTER UPDATE ON Loan
FOR EACH ROW
BEGIN
    IF OLD.Status <> NEW.Status THEN
        INSERT INTO Audit_Log(Table_Name, Operation, Record_Key, Old_Value, New_Value)
        VALUES ('Loan', 'STATUS_CHANGE', CAST(OLD.Loan_ID AS CHAR), OLD.Status, NEW.Status);
    END IF;
END$$

-- 4.4 Auto-close a loan once cumulative payments meet/exceed the principal.
CREATE TRIGGER trg_after_loan_payment
AFTER INSERT ON Loan_Payment
FOR EACH ROW
BEGIN
    DECLARE v_total_paid DECIMAL(12,2);
    DECLARE v_principal  DECIMAL(12,2);

    SELECT SUM(Amount_Paid) INTO v_total_paid FROM Loan_Payment WHERE Loan_ID = NEW.Loan_ID;
    SELECT Principal_Amount INTO v_principal FROM Loan WHERE Loan_ID = NEW.Loan_ID;

    IF v_total_paid >= v_principal THEN
        UPDATE Loan SET Status = 'CLOSED' WHERE Loan_ID = NEW.Loan_ID;
    END IF;
END$$

DELIMITER ;

-- =====================================================================================
-- SECTION 5: STORED PROCEDURE demonstrating TCL (Transaction Control Language)
-- =====================================================================================
DELIMITER $$

CREATE PROCEDURE Transfer_Funds(
    IN  p_from_account BIGINT,
    IN  p_to_account   BIGINT,
    IN  p_amount       DECIMAL(12,2),
    OUT p_status       VARCHAR(100)
)
BEGIN
    DECLARE v_from_balance DECIMAL(12,2);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_status = 'FAILED: transaction rolled back due to an error';
    END;

    START TRANSACTION;

        SELECT Balance INTO v_from_balance
          FROM Account WHERE Account_No = p_from_account FOR UPDATE;

        IF v_from_balance < p_amount THEN
            ROLLBACK;
            SET p_status = 'FAILED: insufficient funds';
        ELSE
            SAVEPOINT before_debit;

            INSERT INTO Transaction(Account_No, Trans_Type, Amount, Description, Balance_After)
            VALUES (p_from_account, 'TRANSFER_OUT', p_amount,
                    CONCAT('Transfer to A/C ', p_to_account), 0);

            INSERT INTO Transaction(Account_No, Trans_Type, Amount, Description, Balance_After)
            VALUES (p_to_account, 'TRANSFER_IN', p_amount,
                    CONCAT('Transfer from A/C ', p_from_account), 0);

            COMMIT;
            SET p_status = 'SUCCESS';
        END IF;

END$$

DELIMITER ;
USE bank_management_system;








-- =====================================================================================
-- SECTION 6:  DATA INPUT ( IN SQL DATABASE)
-- =====================================================================================

INSERT INTO Branch (Branch_Name, City, State, IFSC_Code, Contact_No) VALUES
('MG Road Branch',   'Bhopal',   'Madhya Pradesh', 'SBIN0001234', '0755-2345678'),
('Andheri Branch',   'Mumbai',   'Maharashtra',    'SBIN0005678', '022-26345678'),
('Connaught Place',  'Delhi',    'Delhi',          'SBIN0009999', '011-23456789');

INSERT INTO Employee (Name, Designation, Branch_ID, Manager_ID, Salary, Hire_Date, Email) VALUES
('Anil Sharma',   'Branch Manager', 1, NULL, 95000.00, '2015-06-01', 'anil.sharma@bank.com'),
('Priya Verma',   'Loan Officer',   1, 1,    58000.00, '2018-03-15', 'priya.verma@bank.com'),
('Rahul Nair',    'Teller',         1, 1,    35000.00, '2021-01-10', 'rahul.nair@bank.com'),
('Sunita Rao',    'Branch Manager', 2, NULL, 98000.00, '2014-09-20', 'sunita.rao@bank.com'),
('Vikram Singh',  'Teller',         2, 4,    36000.00, '2020-07-01', 'vikram.singh@bank.com'),
('Neha Gupta',    'Branch Manager', 3, NULL, 97000.00, '2016-02-11', 'neha.gupta@bank.com');

INSERT INTO Customer (Name, DOB, Gender, Address, City, Phone, Email, Aadhar_No) VALUES
('Ravi Kumar',    '1990-04-12','M','12 Lake View, Bhopal','Bhopal',   '9876500001','ravi.k@mail.com','111122223333'),
('Sneha Patil',   '1985-11-02','F','45 Park Street, Mumbai','Mumbai', '9876500002','sneha.p@mail.com','222233334444'),
('Aman Joshi',    '1995-07-19','M','78 MG Road, Bhopal','Bhopal',     '9876500003','aman.j@mail.com','333344445555'),
('Kavita Iyer',   '1992-01-25','F','9 Sector 5, Delhi','Delhi',       '9876500004','kavita.i@mail.com','444455556666'),
('Manoj Tiwari',  '1988-09-09','M','221 Model Town, Delhi','Delhi',   '9876500005','manoj.t@mail.com','555566667777'),
('Divya Menon',   '1993-03-30','F','56 Andheri West, Mumbai','Mumbai','9876500006','divya.m@mail.com','666677778888');

INSERT INTO Account_Type (Type_Name, Interest_Rate, Min_Balance) VALUES
('SAVINGS',        3.50, 1000.00),
('CURRENT',        0.00,    0.00),
('FIXED_DEPOSIT',  6.75, 5000.00);

-- Accounts opened with an opening balance recorded directly (initial seed, not via trigger)
INSERT INTO Account (Branch_ID, Type_ID, Balance, Open_Date, Status) VALUES
(1, 1, 25000.00, '2020-01-15', 'ACTIVE'),  -- 1 Ravi   Savings
(1, 2, 150000.00,'2019-05-20', 'ACTIVE'),  -- 2 Aman   Current
(2, 1, 42000.00, '2021-03-10', 'ACTIVE'),  -- 3 Sneha  Savings
(2, 3, 100000.00,'2022-06-01', 'ACTIVE'),  -- 4 Divya  FD
(3, 1, 8000.00,  '2018-11-05', 'ACTIVE'),  -- 5 Kavita Savings
(3, 1, 60000.00, '2020-08-22', 'ACTIVE'),  -- 6 Manoj  Savings (joint with Kavita)
(1, 1, 500.00,   '2023-02-14', 'FROZEN');  -- 7 Ravi   Savings (second, low-balance)

INSERT INTO Customer_Account (Customer_ID, Account_No, Relationship_Type) VALUES
(1, 1, 'PRIMARY'),
(3, 2, 'PRIMARY'),
(2, 3, 'PRIMARY'),
(6, 4, 'PRIMARY'),
(4, 5, 'PRIMARY'),
(5, 6, 'PRIMARY'),
(4, 6, 'JOINT'),      -- Kavita & Manoj jointly hold account 6
(1, 7, 'PRIMARY');

INSERT INTO Nominee (Account_No, Nominee_Name, Relation, Nominee_Phone, Share_Percent) VALUES
(1, 'Meena Kumar',  'Spouse',  '9998800001', 100.00),
(3, 'Ramesh Patil',  'Father',  '9998800002', 100.00),
(4, 'Suresh Menon',  'Husband', '9998800003', 50.00),
(4, 'Anjali Menon',  'Daughter','9998800004', 50.00),
(6, 'Geeta Tiwari',  'Wife',    '9998800005', 100.00);

INSERT INTO Loan_Type (Loan_Name, Interest_Rate, Max_Amount, Tenure_Months) VALUES
('HOME',      8.50, 5000000.00, 240),
('PERSONAL', 12.00,  500000.00,  60),
('AUTO',      9.25, 1000000.00,  84),
('EDUCATION',10.00,  800000.00, 120);

INSERT INTO Loan (Customer_ID, Branch_ID, Loan_Type_ID, Principal_Amount, Sanction_Date, EMI_Amount, Status) VALUES
(1, 1, 2, 200000.00, '2022-01-10', 5500.00, 'ACTIVE'),
(2, 2, 1, 2500000.00,'2020-05-15', 21000.00,'ACTIVE'),
(4, 3, 3, 600000.00, '2021-09-01', 9000.00, 'ACTIVE'),
(5, 3, 4, 300000.00, '2019-06-20', 4200.00, 'CLOSED');

INSERT INTO Loan_Payment (Loan_ID, Payment_Date, Amount_Paid, Payment_Mode) VALUES
(1, '2022-02-10', 5500.00, 'AUTO_DEBIT'),
(1, '2022-03-10', 5500.00, 'AUTO_DEBIT'),
(2, '2020-06-15', 21000.00,'ONLINE'),
(4, '2019-07-20', 300000.00,'ONLINE');  -- full payoff -> trigger auto-closes it

INSERT INTO Card (Account_No, Card_Type, Card_Number, Expiry_Date) VALUES
(1, 'DEBIT',  '4111111111111111', '2027-04-30'),
(2, 'CREDIT', '5500000000000004', '2026-11-30'),
(3, 'DEBIT',  '4111111111112222', '2028-03-31'),
(6, 'DEBIT',  '4111111111113333', '2027-08-31');

-- A few transactions routed through the trigger-driven pipeline (do NOT touch
-- Account.Balance directly for these -- the triggers in 02_objects.sql do it).
INSERT INTO Transaction (Account_No, Trans_Type, Amount, Description, Balance_After) VALUES
(1, 'DEPOSIT',    5000.00, 'Salary credit', 0),
(3, 'WITHDRAWAL', 2000.00, 'ATM withdrawal', 0),
(2, 'DEPOSIT',   10000.00, 'Cash deposit', 0);
USE bank_management_system;





-- =====================================================================================
-- SECTION 7:   SQL  QUERY SHOWCASE  
-- =====================================================================================

-- 7.1 SELECTION (sigma) + PROJECTION (pi)
--     sigma(Status='ACTIVE')(Account), then pi(Account_No, Balance)
SELECT Account_No, Balance
FROM Account
WHERE Status = 'ACTIVE';

-- 7.2 PROJECTION with DISTINCT (relational algebra projection removes duplicates)
SELECT DISTINCT City FROM Customer;

-- 7.3 INNER JOIN (natural-join style: Account bowtie Branch bowtie Account_Type)
SELECT a.Account_No, b.Branch_Name, at.Type_Name, a.Balance
FROM Account a
JOIN Branch b        ON a.Branch_ID = b.Branch_ID
JOIN Account_Type at ON a.Type_ID  = at.Type_ID;

-- 7.4 LEFT OUTER JOIN -- every customer, even those with zero loans
SELECT c.Name, l.Loan_ID, l.Principal_Amount
FROM Customer c
LEFT JOIN Loan l ON c.Customer_ID = l.Customer_ID;

-- 7.5 RIGHT OUTER JOIN -- every loan, even if (hypothetically) customer data is missing
SELECT l.Loan_ID, c.Name
FROM Customer c
RIGHT JOIN Loan l ON c.Customer_ID = l.Customer_ID;

-- 7.6 SELF JOIN -- Employee and their Manager (recursive relationship)
SELECT e.Name AS Employee_Name, m.Name AS Manager_Name
FROM Employee e
LEFT JOIN Employee m ON e.Manager_ID = m.Employee_ID;

-- 7.7 AGGREGATE FUNCTIONS + GROUP BY + HAVING
--     Total balance per branch, only branches holding > 50000 total
SELECT b.Branch_Name,
       COUNT(a.Account_No)      AS Num_Accounts,
       SUM(a.Balance)           AS Total_Balance,
       AVG(a.Balance)           AS Avg_Balance,
       MAX(a.Balance)           AS Max_Balance,
       MIN(a.Balance)           AS Min_Balance
FROM Account a
JOIN Branch b ON a.Branch_ID = b.Branch_ID
GROUP BY b.Branch_Name
HAVING SUM(a.Balance) > 50000
ORDER BY Total_Balance DESC;

-- 7.8 NESTED SUBQUERY -- customers whose (single) account balance is above the
--     overall average account balance (subquery in WHERE clause)
SELECT c.Name, a.Balance
FROM Customer c
JOIN Customer_Account ca ON c.Customer_ID = ca.Customer_ID
JOIN Account a           ON ca.Account_No = a.Account_No
WHERE a.Balance > (SELECT AVG(Balance) FROM Account);

-- 7.9 CORRELATED SUBQUERY -- accounts whose balance is the branch's own maximum
SELECT a.Account_No, a.Branch_ID, a.Balance
FROM Account a
WHERE a.Balance = (
    SELECT MAX(a2.Balance) FROM Account a2 WHERE a2.Branch_ID = a.Branch_ID
);

-- 7.10 SUBQUERY WITH IN / NOT IN -- customers who have never taken a loan
SELECT Name FROM Customer
WHERE Customer_ID NOT IN (SELECT Customer_ID FROM Loan);

-- 7.11 RELATIONAL DIVISION
--     "Find customers who hold an account of EVERY Account_Type that exists."
--     Classic division = NOT EXISTS( types they are missing ).
SELECT c.Customer_ID, c.Name
FROM Customer c
WHERE NOT EXISTS (
    SELECT at.Type_ID FROM Account_Type at
    WHERE at.Type_ID NOT IN (
        SELECT a.Type_ID
        FROM Customer_Account ca
        JOIN Account a ON ca.Account_No = a.Account_No
        WHERE ca.Customer_ID = c.Customer_ID
    )
);

-- 7.12 SET OPERATIONS
--     UNION: every city that has either a Branch or a Customer
SELECT City FROM Branch
UNION
SELECT City FROM Customer;

--     UNION ALL: same, but keep duplicates
SELECT City FROM Branch
UNION ALL
SELECT City FROM Customer;

--     INTERSECT (MySQL LATEST VERSION ): cities that have BOTH a branch and a customer
SELECT City FROM Branch
INTERSECT
SELECT City FROM Customer;

--     EXCEPT / MINUS (MySQL 8.0.31+): customer cities with NO branch presence
SELECT City FROM Customer
EXCEPT
SELECT City FROM Branch;

-- 7.13 RENAMING (rho) -- table & column aliases
SELECT cust.Name AS Account_Holder, acc.Balance AS Current_Balance
FROM Customer AS cust
JOIN Customer_Account AS ca ON cust.Customer_ID = ca.Customer_ID
JOIN Account AS acc         ON ca.Account_No = acc.Account_No;

-- 7.14 SINGLE-ROW FUNCTIONS, CONVERSION FUNCTIONS, CONDITIONAL EXPRESSIONS
SELECT
    Name,
    UPPER(Name)                                   AS Name_Upper,
    ROUND(DATEDIFF(CURDATE(), DOB) / 365.25, 0)   AS Age_Years,
    CAST(Phone AS UNSIGNED)                        AS Phone_Numeric,
    DATE_FORMAT(DOB, '%d-%b-%Y')                   AS DOB_Formatted,
    CASE
        WHEN TIMESTAMPDIFF(YEAR, DOB, CURDATE()) >= 60 THEN 'Senior Citizen'
        WHEN TIMESTAMPDIFF(YEAR, DOB, CURDATE()) >= 18 THEN 'Adult'
        ELSE 'Minor'
    END                                            AS Category,
    IFNULL(Email, 'Not Provided')                  AS Email_Safe
FROM Customer;

-- 7.15 TUPLE RELATIONAL CALCULUS (for reference/comparison)
-- TRC:  { t | t in Customer AND EXISTS l in Loan (l.Customer_ID = t.Customer_ID) }
-- Equivalent SQL:
SELECT t.* FROM Customer t
WHERE EXISTS (SELECT 1 FROM Loan l WHERE l.Customer_ID = t.Customer_ID);

-- 7.16 JOINED RELATIONS across many tables -- full statement of an account
SELECT c.Name, a.Account_No, b.Branch_Name, at.Type_Name, a.Balance,
       t.Trans_Type, t.Amount, t.Trans_Date
FROM Customer c
JOIN Customer_Account ca ON c.Customer_ID = ca.Customer_ID
JOIN Account a           ON ca.Account_No = a.Account_No
JOIN Branch b             ON a.Branch_ID = b.Branch_ID
JOIN Account_Type at      ON a.Type_ID = at.Type_ID
LEFT JOIN Transaction t   ON a.Account_No = t.Account_No
ORDER BY c.Name, t.Trans_Date;

-- =====================================================================================
-- SECTION 8: DML + TCL DEMONSTRATION
-- =====================================================================================

-- 8.1 Plain DML
UPDATE Employee SET Salary = Salary * 1.05 WHERE Designation = 'Teller';
DELETE FROM Loan_Payment WHERE Amount_Paid < 0;   -- no-op safeguard example

-- 8.2 TCL via the stored procedure (uses START TRANSACTION / SAVEPOINT / COMMIT / ROLLBACK)
CALL Transfer_Funds(2, 1, 15000.00, @status);
SELECT @status;

-- 8.3 Manual TCL example
START TRANSACTION;
    UPDATE Account SET Balance = Balance - 1000 WHERE Account_No = 3;
    SAVEPOINT sp1;
    UPDATE Account SET Balance = Balance + 1000 WHERE Account_No = 5;
    -- Suppose a business rule check fails here:
    -- ROLLBACK TO sp1;  -- would undo only the second update
COMMIT;

-- 8.4 Data dictionary views (MySQL's INFORMATION_SCHEMA plays the role Oracle's
--     USER_TABLES / USER_VIEWS / USER_TAB_COLUMNS play)
SELECT TABLE_NAME, TABLE_TYPE
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'bank_management_system';

SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE, IS_NULLABLE, COLUMN_KEY
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'bank_management_system' AND TABLE_NAME = 'Account';
