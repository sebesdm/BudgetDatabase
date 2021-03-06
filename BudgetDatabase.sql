USE [Records]
GO

CREATE SCHEMA [Budget]
GO

CREATE TABLE [Budget].[MonthlyBudgetAdjustments](
	[SourceYear] [int] NOT NULL,
	[SourceMonth] [int] NOT NULL,
	[SourceTransactionCategory] [varchar](255) NOT NULL,
	[TargetYear] [int] NOT NULL,
	[TargetMonth] [int] NOT NULL,
	[TargetTransactionCategory] [varchar](255) NOT NULL,
	[Amount] [money] NOT NULL,
 CONSTRAINT [PK_Budget_MonthlyBudgetRolloverAllocations] PRIMARY KEY CLUSTERED 
(
	[SourceYear] ASC,
	[SourceMonth] ASC,
	[SourceTransactionCategory] ASC,
	[TargetYear] ASC,
	[TargetMonth] ASC,
	[TargetTransactionCategory] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO

CREATE TABLE [Budget].[MonthlyBudgets](
	[Year] [int] NOT NULL,
	[Month] [int] NOT NULL,
	[TransactionCategory] [varchar](255) NOT NULL,
	[Amount] [money] NOT NULL,
 CONSTRAINT [PK_Budget_MonthlyBudgets] PRIMARY KEY CLUSTERED 
(
	[Year] ASC,
	[Month] ASC,
	[TransactionCategory] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO

CREATE TABLE [dbo].[Accounts](
	[AccountID] [tinyint] IDENTITY(1,1) NOT NULL,
	[AccountName] [varchar](255) NOT NULL,
 CONSTRAINT [PK_Accounts] PRIMARY KEY CLUSTERED 
(
	[AccountID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO

CREATE TABLE [dbo].[AccountTransactions](
	[TransactionID] [int] IDENTITY(1,1) NOT NULL,
	[AccountID] [tinyint] NOT NULL,
	[Date] [date] NOT NULL,
	[Year]  AS (datepart(year,[Date])) PERSISTED,
	[Month]  AS (datepart(month,[Date])) PERSISTED,
	[Amount] [money] NOT NULL,
	[Description] [varchar](4000) NOT NULL,
	[TransactionCategory] [varchar](255) NOT NULL,
	[Note] [varchar](4000) NULL,
 CONSTRAINT [PK_AccountTransactions] PRIMARY KEY CLUSTERED 
(
	[TransactionID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO

CREATE TABLE [dbo].[TransactionCategories](
	[TransactionCategory] [varchar](255) NOT NULL,
 CONSTRAINT [PK_Budget_TransactionCategories] PRIMARY KEY CLUSTERED 
(
	[TransactionCategory] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
ALTER TABLE [Budget].[MonthlyBudgetAdjustments]  WITH CHECK ADD  CONSTRAINT [FK_Budget_MonthlyBudgetRolloverAllocations_SourceBudget] FOREIGN KEY([SourceYear], [SourceMonth], [SourceTransactionCategory])
REFERENCES [Budget].[MonthlyBudgets] ([Year], [Month], [TransactionCategory])
GO
ALTER TABLE [Budget].[MonthlyBudgetAdjustments] CHECK CONSTRAINT [FK_Budget_MonthlyBudgetRolloverAllocations_SourceBudget]
GO
ALTER TABLE [Budget].[MonthlyBudgetAdjustments]  WITH CHECK ADD  CONSTRAINT [FK_Budget_MonthlyBudgetRolloverAllocations_TargetBudget] FOREIGN KEY([TargetYear], [TargetMonth], [TargetTransactionCategory])
REFERENCES [Budget].[MonthlyBudgets] ([Year], [Month], [TransactionCategory])
GO
ALTER TABLE [Budget].[MonthlyBudgetAdjustments] CHECK CONSTRAINT [FK_Budget_MonthlyBudgetRolloverAllocations_TargetBudget]
GO
ALTER TABLE [Budget].[MonthlyBudgets]  WITH CHECK ADD  CONSTRAINT [FK_Budget_MonthlyBudgets_TransactionCategories] FOREIGN KEY([TransactionCategory])
REFERENCES [dbo].[TransactionCategories] ([TransactionCategory])
GO
ALTER TABLE [Budget].[MonthlyBudgets] CHECK CONSTRAINT [FK_Budget_MonthlyBudgets_TransactionCategories]
GO
ALTER TABLE [dbo].[AccountTransactions]  WITH CHECK ADD  CONSTRAINT [FK_AccountTransactions_TransactionCategories] FOREIGN KEY([TransactionCategory])
REFERENCES [dbo].[TransactionCategories] ([TransactionCategory])
GO
ALTER TABLE [dbo].[AccountTransactions] CHECK CONSTRAINT [FK_AccountTransactions_TransactionCategories]
GO

CREATE PROCEDURE [Budget].[BudgetAnalysis]
	@year INT,
    @month INT
AS
BEGIN
    -- Transactions for the month
    SELECT *
    INTO #MonthlyTransactions
    FROM AccountTransactions
    WHERE [Year] = @year AND [Month] = @month

    -- Budget for the searched month
    SELECT *
    INTO #MonthlyBudget
    FROM Budget.MonthlyBudgets mb
    WHERE mb.[Year] = @year AND mb.[Month] = @month

    -- TransactionCategory totals for the month
    SELECT ec.TransactionCategory, mb.[Year], mb.[Month], SUM(COALESCE(mt.Amount, 0)) AS Amount
    INTO #MonthlyTransactionCategoryTotals
    FROM TransactionCategories ec LEFT JOIN #MonthlyBudget mb
                ON ec.TransactionCategory = mb.TransactionCategory LEFT JOIN 
         #MonthlyTransactions mt
                ON mb.TransactionCategory = mt.TransactionCategory AND
                   mb.[Year] = mt.[Year] AND
                   mb.[Month] = mt.[Month]
    GROUP BY ec.TransactionCategory, mb.[Year], mb.[Month]
    ORDER BY ec.TransactionCategory

    -- Get the months previous to check for budget rollovers
    SELECT DISTINCT [Year], [Month]
    INTO #MonthlyBudgetRolloverMonths
    FROM Budget.MonthlyBudgets
    WHERE NOT CAST(CAST([Year] AS VARCHAR) + '-' + CAST([Month] AS VARCHAR) + '-01' AS DATE) >= 
                CAST(CAST(@year AS VARCHAR) + '-' + CAST(@month AS VARCHAR) + '-01' AS DATE)
    ORDER BY [Year] DESC, [Month] DESC

    -- Get Budget Adjustments which take from a source budget TransactionCategory
    SELECT mb.[Year], mb.[Month], mb.TransactionCategory, -1 * SUM(COALESCE(AdjSrc.Amount, 0)) AS BudgetAdjustment
    INTO #SourceBudgetAdjustments
    FROM Budget.MonthlyBudgets mb LEFT JOIN Budget.MonthlyBudgetAdjustments AdjSrc
            ON mb.[Year] = AdjSrc.[SourceYear] AND mb.[Month] = AdjSrc.[SourceMonth] AND mb.TransactionCategory = AdjSrc.SourceTransactionCategory
    GROUP BY mb.[Year], mb.[Month], mb.TransactionCategory

    -- Get Budget Adjustments which add to a target budget TransactionCategory
    SELECT mb.[Year], mb.[Month], mb.TransactionCategory, SUM(COALESCE(AdjTgt.Amount, 0)) AS BudgetAdjustment
    INTO #TargetBudgetAdjustments
    FROM Budget.MonthlyBudgets mb LEFT JOIN Budget.MonthlyBudgetAdjustments AdjTgt
            ON mb.[Year] = AdjTgt.[TargetYear] AND mb.[Month] = AdjTgt.[TargetMonth] AND mb.TransactionCategory = AdjTgt.TargetTransactionCategory
    GROUP BY mb.[Year], mb.[Month], mb.TransactionCategory

    -- Calculate the Budget Rollovers for each TransactionCategory, for each month
    SELECT ec.TransactionCategory, ec.[Year], ec.[Month], ec.Amount AS BudgetAmount, SUM(COALESCE(ct.Amount, 0)) AS Amount, COALESCE(sba.BudgetAdjustment, 0) AS SourceAdjustment, COALESCE(tba.BudgetAdjustment, 0) AS TargetAdjustment, ec.Amount - SUM(COALESCE(ct.Amount, 0)) + COALESCE(sba.BudgetAdjustment, 0) + COALESCE(tba.BudgetAdjustment, 0) AS Rollover
    INTO #TransactionCategoryMonthlyRollovers
    FROM Budget.MonthlyBudgets ec INNER JOIN #MonthlyBudgetRolloverMonths mbrm 
                ON ec.[Year] = mbrm.[Year] AND
                   ec.[Month] = mbrm.[Month] LEFT JOIN 
            AccountTransactions ct
                ON ec.TransactionCategory = ct.TransactionCategory AND 
                   ec.[Year] = ct.[Year] AND 
                   ec.[Month] = ct.[Month] LEFT JOIN
            #TargetBudgetAdjustments tba
                ON ec.[Year] = tba.[Year] AND 
                   ec.[Month] = tba.[Month] AND
                   ec.TransactionCategory = tba.TransactionCategory LEFT JOIN
            #SourceBudgetAdjustments sba
                ON ec.[Year] = sba.[Year] AND 
                   ec.[Month] = sba.[Month] AND
                   ec.TransactionCategory = sba.TransactionCategory
    GROUP BY ec.TransactionCategory, ec.[Year], ec.[Month], ec.Amount, sba.BudgetAdjustment, tba.BudgetAdjustment

    -- Calculate the Budget Rollovers for each TransactionCategory
    SELECT TransactionCategory, SUM(Rollover) AS RolloverTotal
    INTO #TransactionCategoryRollovers
    FROM #TransactionCategoryMonthlyRollovers
    GROUP BY TransactionCategory

    -- Calculate the spent amount, budget amount, budget rollovers, and budget adjustments for each TransactionCategory.  
    -- Calculate the final allowable total for each Expense category for the month.
    SELECT  ec.TransactionCategory, 
            COALESCE(mt.Amount, 0) AS CurrentAmount,
            COALESCE(mb.Amount, 0) as Budgeted,
            COALESCE(ecr.RolloverTotal, 0) as Rollover,
            COALESCE(sba.BudgetAdjustment, 0) + COALESCE(tba.BudgetAdjustment, 0) AS BudgetAdjustment,
            COALESCE(mb.Amount, 0) + COALESCE(ecr.RolloverTotal, 0) + COALESCE(sba.BudgetAdjustment, 0) + COALESCE(tba.BudgetAdjustment, 0) AS FinalAllowance
    INTO #MonthlyTransactionCategoryTotalsWithBudget
    FROM    TransactionCategories ec LEFT JOIN #MonthlyBudget mb
                ON ec.TransactionCategory = mb.TransactionCategory LEFT JOIN
            #MonthlyTransactionCategoryTotals as mt 
                ON mb.TransactionCategory = mt.TransactionCategory AND 
                   mb.[Year] = mt.[Year] AND 
                   mb.[Month] = mt.[Month] LEFT JOIN
            #TransactionCategoryRollovers ecr
                ON ec.TransactionCategory = ecr.TransactionCategory LEFT JOIN
            #TargetBudgetAdjustments tba
                ON mb.[Year] = tba.[Year] AND 
                   mb.[Month] = tba.[Month] AND
                   mb.TransactionCategory = tba.TransactionCategory LEFT JOIN
            #SourceBudgetAdjustments sba
                ON mb.[Year] = sba.[Year] AND 
                   mb.[Month] = sba.[Month] AND
                   mb.TransactionCategory = sba.TransactionCategory
    ORDER BY TransactionCategory

    SELECT  (SELECT SUM(CASE WHEN Amount > 0 THEN Amount ELSE 0 END) FROM Budget.MonthlyBudgets WHERE [Year] = @year AND [Month] = @month) AS BudgetIncome,
            (SELECT SUM(CASE WHEN Amount <= 0 THEN Amount ELSE 0 END) FROM Budget.MonthlyBudgets WHERE [Year] = @year AND [Month] = @month) AS BudgetExpenses,
            (SELECT SUM(Amount) FROM Budget.MonthlyBudgets WHERE [Year] = @year AND [Month] = @month) AS BudgetNet,
            -((SELECT SUM(RolloverTotal) FROM #TransactionCategoryRollovers) - (SELECT SUM(Amount) FROM #MonthlyTransactions)) AS AvailableFunds
    INTO #BudgetTotals

    --SELECT * FROM #MonthlyTransactions ORDER BY [Date]
    --SELECT * FROM #MonthlyTransactionCategoryTotals
    --SELECT * FROM #MonthlyBudgetRolloverMonths
    --SELECT * FROM #TransactionCategoryMonthlyRollovers ORDER BY TransactionCategory, [Year], [Month]
    --SELECT * FROM #TransactionCategoryRollovers
    --SELECT * FROM #SourceBudgetAdjustments
    --SELECT * FROM #TargetBudgetAdjustments

    SELECT * FROM #MonthlyTransactionCategoryTotalsWithBudget
    SELECT * FROM #BudgetTotals
END

GO

CREATE PROCEDURE [Budget].[BudgetChanges]
    @SourceYear INT,
    @SourceMonth INT,
    @TargetYear INT,
    @TargetMonth INT
AS
BEGIN
    SELECT mb1.TransactionCategory, mb1.Amount - mb2.Amount AS BudgetChange
    FROM Budget.MonthlyBudgets mb1 FULL OUTER JOIN 
         Budget.MonthlyBudgets mb2
            ON mb1.TransactionCategory = mb2.TransactionCategory
    WHERE mb1.[Year] = @SourceYear AND mb1.[Month] = @SourceMonth AND
          mb2.[Year] = @TargetYear AND mb2.[Month] = @TargetMonth AND
          mb1.Amount <> mb2.Amount
    UNION
    SELECT TransactionCategory, -Amount
    FROM Budget.MonthlyBudgets
    WHERE TransactionCategory NOT IN (
        SELECT TransactionCategory 
        FROM Budget.MonthlyBudgets
        WHERE [Year] = @SourceYear AND [Month] = @SourceMonth)
    AND [Year] = @TargetYear AND [Month] = @TargetMonth
        UNION
    SELECT TransactionCategory, Amount
    FROM Budget.MonthlyBudgets
    WHERE TransactionCategory NOT IN (
        SELECT TransactionCategory 
        FROM Budget.MonthlyBudgets
        WHERE [Year] = @TargetYear AND [Month] = @TargetMonth)
    AND [Year] = @SourceYear AND [Month] = @SourceMonth
END
GO

CREATE PROCEDURE [dbo].[MonthlyAccountAnalysis]
	@year INT,
    @month INT
AS
BEGIN
	-- Transactions for the month
    SELECT *
    INTO #MonthlyTransactions
    FROM AccountTransactions
    WHERE [Year] = @year AND [Month] = @month

    -- Income/Expense totals for the month
    SELECT  (SELECT SUM(Amount) FROM #MonthlyTransactions WHERE TransactionCategory IN ('Paycheck')) AS TotalIncome,
            (SELECT SUM(Amount) FROM #MonthlyTransactions WHERE TransactionCategory NOT IN ('Transfer', 'Paycheck')) AS TotalExpenses,
            (SELECT SUM(CASE WHEN Amount > 0 THEN Amount ELSE 0 END) FROM #MonthlyTransactions WHERE TransactionCategory IN ('Transfer')) AS TotalTransfersIn,
            (SELECT SUM(CASE WHEN Amount <= 0 THEN Amount ELSE 0 END) FROM #MonthlyTransactions WHERE TransactionCategory IN ('Transfer')) AS TotalTransfersOut,
            (SELECT SUM(Amount) FROM #MonthlyTransactions) AS NetCashflow,
            COALESCE((SELECT SUM(Amount) FROM Budget.MonthlyBudgetAdjustments WHERE TargetTransactionCategory IN ('Unallocated')), 0)
                - COALESCE((SELECT SUM(Amount) FROM Budget.MonthlyBudgetAdjustments WHERE SourceTransactionCategory IN ('Unallocated')), 0) AS TotalUnallocated
    INTO #MonthlyTotals

    SELECT * FROM #MonthlyTotals
END

GO
