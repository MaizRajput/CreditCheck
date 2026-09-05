-- CreditCheck database schema
-- MySQL 8.0+ (needed later for window functions in queries.sql)

-- Run this once to create the tables, then load the 5 CSVs into them
-- in this order: branches, customers, loan_applications, loans, repayments
-- (this order matters because of the foreign keys below)

CREATE DATABASE IF NOT EXISTS creditcheck;
USE creditcheck;

DROP TABLE IF EXISTS repayments;
DROP TABLE IF EXISTS loans;
DROP TABLE IF EXISTS loan_applications;
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS branches;

-- Branch master data
CREATE TABLE branches (
    branch_id INT PRIMARY KEY,
    branch_name VARCHAR(100),
    city VARCHAR(50),
    region VARCHAR(50),
    manager_name VARCHAR(100)
) ENGINE=InnoDB;

-- Customer master data
CREATE TABLE customers (
    customer_id INT PRIMARY KEY,
    name VARCHAR(100),
    age INT,
    gender VARCHAR(10),
    city VARCHAR(50),
    income DECIMAL(12,2),
    employment_type VARCHAR(30),
    credit_score INT,
    join_date DATE
) ENGINE=InnoDB;

-- Every loan application, approved or not
CREATE TABLE loan_applications (
    application_id INT PRIMARY KEY,
    customer_id INT,
    branch_id INT,
    application_date DATE,
    requested_amount DECIMAL(14,2),
    approval_status VARCHAR(20),
    risk_score DECIMAL(6,2),
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
    FOREIGN KEY (branch_id) REFERENCES branches(branch_id)
) ENGINE=InnoDB;

-- One row per loan that actually got disbursed
CREATE TABLE loans (
    loan_id INT PRIMARY KEY,
    application_id INT,
    customer_id INT,
    branch_id INT,
    loan_type VARCHAR(30),
    loan_amount DECIMAL(14,2),
    interest_rate DECIMAL(5,2),
    tenure_months INT,
    disbursement_date DATE,
    status VARCHAR(20),
    FOREIGN KEY (application_id) REFERENCES loan_applications(application_id),
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
    FOREIGN KEY (branch_id) REFERENCES branches(branch_id)
) ENGINE=InnoDB;

-- The fact table: one row per EMI installment, this is the most granular data
CREATE TABLE repayments (
    payment_id INT PRIMARY KEY,
    loan_id INT,
    due_date DATE,
    paid_date DATE NULL,
    amount_due DECIMAL(12,2),
    amount_paid DECIMAL(12,2),
    payment_status VARCHAR(20),
    dpd INT,
    FOREIGN KEY (loan_id) REFERENCES loans(loan_id)
) ENGINE=InnoDB;

-- Indexes to speed up the joins and window functions used in queries.sql
CREATE INDEX idx_apps_customer ON loan_applications(customer_id);
CREATE INDEX idx_loans_customer ON loans(customer_id);
CREATE INDEX idx_loans_branch ON loans(branch_id);
CREATE INDEX idx_loans_application ON loans(application_id);
CREATE INDEX idx_repay_loan ON repayments(loan_id);
