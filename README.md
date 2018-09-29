# BudgetDatabase

## Overview

The script for BudgetDatabase will create a simple database schema with some stored procedures used to aggregate budget information.  The purpose of the overall database is to log transactions for an account, create budgets month-to-month, and balance budgets at the end of each month.  Use the stored procedures to get information on the status of a particular month.

## Setup

The following steps should initialize your Budget Database:
- Run the source BudgetDatabase.sql script in a new, empty SQL Server database.  
- Add a row to dbo.Accounts for the account you wish to track and budget against
- Add a row to dbo.TransactionCategories for "Unallocated".  This will be a bucket you do not budget agains, but will be used for initializing and moving funds.
- Add any number of rows to dbo.TransactionCategories for any budget categories you wish
- Add a row to dbo.AccountTransactions dated 1900-01-01 and of TransactionCategory "Unallocated".  Set the amount to a positive amount that for the starting account balance.  (This number may be the balance for whatever day you begin entering transactions)
- For any transaction categories, add those categories to Budget.MonthlyBudgets for the current month and with an amount you are allocating for the month.

## Tables

### dbo.Accounts

This table is responsible for storing the valid accounts for which transactions are being tracked.  For example, you may enter in an account for AccountID 1, "Wells Fargo Checking".  Any transactions entered for "Wells Fargo Checking" would be tied to AccountID 1.  Currently only one account per dbo.AccountTransactions table is tested and supported.

### dbo.TransactionCategories

This table is responsible for holding the different categories or buckets into which you want to mark transactions.  Examples of this might be "Rent", "Dining", "Paycheck"

### dbo.AccountTransactions

This is the main table responsible for holding any transactions posted against an account.  The following columns are as listed:

- TransactionID: The unique identifier of a specific transaction in the context of the budget database
- AccountID: The unique identifier of the account to which the transaction was posted
- Date: The date on which the transaction was posted
- Year: (Computed) The year portion of the Date column
- Month: (Computed) The month portion of the Date column
- Amount: The amount of the posted transaction.  Negative amounts represent withdrawls, Positive amounts represent deposits.
- Description: The description of the posted transaction as it exists in the account ledger
- TransactionCategory: The category into which the posted transaction falls
- Note: Any special comments regarding this transaction. (Typically used for checks, where the transaction description does not clearly indicate what it was for)

### Budget.MonthlyBudgets

This table is responsible for maintaining the budgeted amount per transaction category for a given year and month.  Negative amounts indicate the amount which is expected to be withdrawn from the account for that category for the month.  Positive amounts indicate the amount which is expected to be deposited to the account for the month.  An example MonthlyBudget might look like the following:

| Year | Month | TransactionCategory | Amount |
| ---- | ----- | ------------------- | ------ |
| 2018 | 10    | Paycheck            | 2000   |
| 2018 | 10    | Rent                | -950   |
| 2018 | 10    | Beer                | -50    |
| 2018 | 10    | Grocery             | -300   |
| 2018 | 10    | Dining              | -100   |
| 2018 | 10    | Entertainment       | -100   |
| 2018 | 10    | Auto Payment        | -300   |
| 2018 | 10    | Auto Insurance      | -100   |
| 2018 | 10    | Medical             | -100   |

### Budget.MonthlyBudgetAdjustments

This table is responsible for maintaining adjustments to budgets when balancing out at the end of each month.  If the posted transactions for a category in a given month are more or less than the budgeted amount, any difference is rolled over to the next month by default when using the databases stored procedures.  In order to make corrections for a month and avaoid this rollover, it is necessary to "move" budgeted funds from one category to another.

For example, say we had $2000 for paycheck in a month, -$200 spent in dining, and -$200 spent in grocery.  Using our sample budget table above, we are $100 over budget on dining, but $100 under budget on grocery.  In the next month, we will automatically be $100 in the hole on dining and have $100 extra for groceries due to the automatic rollover.  Since we likely do not want this (rollover may be desired on a category if we are "saving up", like a car or a TV), we will need to add a budget adjustment, like follows:

| SourceYear | SourceMonth | SourceTransactionCategory | TargetYear | TargetMonth | TargetTransactionCategory | Amount |
| ---------- | ----------- | ------------------------- | ---------- | ----------- | ------------------------- | ------ |
| 2018       | 10          | Grocery                   | 2018       | 10          | Dining                    | -100   |

This says, "Take 100 dollars that I budgeted for Grocery in and consider it allocated to Dining instead.  Doing this allows you to preserve the budget you created at the beginning of the month, while making adjustments to balance out differences at the end of the month.

Another way I like to handle budget adjustments is by having a TransactionCategory of "Unallocated".  I use this bucket as a temporary store of funds.  In the case my budget is under for more categories than it is not, I may not want to move anything to a different category, but I also may not want to roll it over either.  In this case, I can simply move extra funds to "Unallocated".  Utilizing the Unallocated category for the previous example would look like the following:

| SourceYear | SourceMonth | SourceTransactionCategory | TargetYear | TargetMonth | TargetTransactionCategory | Amount |
| ---------- | ----------- | ------------------------- | ---------- | ----------- | ------------------------- | ------ |
| 2018       | 10          | Grocery                   | 2018       | 10          | Unallocated               | -100   |
| 2018       | 10          | Unallocated               | 2018       | 10          | Dining                    | -100   |

This would be read as follows, "Take 100 dollars that I budgeted for Grocery and move it into Unallocated.  Then take 100 dallars from Unallocated and move it into Dining.".  I find that this provides a less coupled way to express budget adjustments.





















