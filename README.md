# BudgetDatabase

## Overview

The script for BudgetDatabase will create a simple database schema with some stored procedures used to aggregate budget information.  The purpose of the overall database is to log transactions for an account, create budgets month-to-month, and balance budgets at the end of each month.  Use the stored procedures to get information on the status of a particular month.

## Setup

The following steps should initialize your Budget Database:
- Run the source BudgetDatabase.sql script in a new, empty SQL Server database.  
- Add a row to dbo.Accounts for the account you wish to track and budget against
- Add a row to dbo.TransactionCategories for "Unallocated".  This will be a bucket you do not budget against, but will be used for initializing and moving funds.
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

This table is responsible for maintaining adjustments to budgets when balancing out at the end of each month.  If the posted transactions for a category in a given month are more or less than the budgeted amount, any difference is rolled over to the next month by default when using the databases stored procedures.  In order to make corrections for a month and avoid this rollover, it is necessary to "move" budgeted funds from one category to another.

For example, say we had $2000 for paycheck in a month, -$200 spent in dining, and -$200 spent in grocery.  Using our sample budget table above, we are $100 over budget on dining, but $100 under budget on grocery.  In the next month, we will automatically be $100 in the hole on dining and have $100 extra for groceries due to the automatic rollover.  Since we likely do not want this (rollover may be desired on a category if we are "saving up", like a car or a TV), we will need to add a budget adjustment, like follows:

| SourceYear | SourceMonth | SourceTransactionCategory | TargetYear | TargetMonth | TargetTransactionCategory | Amount |
| ---------- | ----------- | ------------------------- | ---------- | ----------- | ------------------------- | ------ |
| 2018       | 10          | Grocery                   | 2018       | 10          | Dining                    | -100   |

This says, "Take 100 dollars that I budgeted for Grocery in and consider it allocated to Dining instead".  Doing this allows you to preserve the budget you created at the beginning of the month, while making adjustments to balance out differences at the end of the month.

Another way I like to handle budget adjustments is by having a TransactionCategory of "Unallocated".  I use this bucket as a temporary store of funds.  In the pleasant case where my budget is under for more categories than it is not, I may not want to move anything to a different category, but I also may not want to roll it over either.  In this case, I can simply move extra funds to "Unallocated".  Utilizing the Unallocated category for the previous example would look like the following:

| SourceYear | SourceMonth | SourceTransactionCategory | TargetYear | TargetMonth | TargetTransactionCategory | Amount |
| ---------- | ----------- | ------------------------- | ---------- | ----------- | ------------------------- | ------ |
| 2018       | 10          | Grocery                   | 2018       | 10          | Unallocated               | -100   |
| 2018       | 10          | Unallocated               | 2018       | 10          | Dining                    | -100   |

This would be read as follows, "Take 100 dollars that I budgeted for Grocery and move it into Unallocated.  Then take 100 dollars from Unallocated and move it into Dining.".  I find that this provides a less coupled way to express budget adjustments.

## Stored Procedures

### Budget.BudgetAnalysis

This stored procedure will take a year and month as input and do all the processing necessary to see how your posted transactions match up against what you have budgeted for the month.  The first data set you will see will look like this:

| TransactionCategory | CurrentAmount | Budgeted | Rollover | BudgetAdjustment | FinalAllowance |
| ------------------- | ------------- | -------- | -------- | ---------------- | -------------- |
| Auto                | -100          | -200     | -50      | 0                | -250           |
| Dining              | -25           | -100     | 0        | 0                | -100           |
| Paycheck            | 1000          | 2000     | 0        | 0                | 2000           |
| Grocery             | -250          | -300     | 0        | 0                | -300           |

This data set essentially reads like:
- For [TransactionCategory]
- You have spent [CurrentAmount] so far this month
- And you have budgeted [Budgeted] for the category
- And from the previous months you rolled over [Rollover] amount
- And have adjusted the category by [BudgetAdjustment]
- Leaving you with a total amount allowed for this category this month of [FinalAllowance]

In addition, you will see a second set as follows:

| BudgetIncome | BudgetExpenses | BudgetNet | AvailableFunds |
| ------------ | -------------- | --------- | -------------- |
| 1000         | -1000          | 0         | 625            |

This summary gives you information on the month's budget itself.  This will tell you how much you've budgeted for income and how much you've budgeted for expenses.  You want these numbers to balance and result in a BudgetNet of 0.  Taking in more than you are expensing?  Create a new category for Savings in which you budget to transfer money into.

### dbo.MonthlyAccountAnalysis

This stored procedure gives you an aggregate summary over the whole month of how much you've spent vs. how much you've taken in, and how much you have available to spend in total.  An example is as follows:

| TotalIncome | TotalExpenses | TotalTransfersIn | TotalTransfersOut | NetCashflow | TotalUnallocated |
| ----------- | ------------- | ---------------- | ----------------- | ----------- | ---------------- |
| 750         | -600          | 0                | -100              | 150         | 1500             |

### Budget.BudgetChanges

This stored procedure is a helper proc used to see changes in budget categories from month to month.













