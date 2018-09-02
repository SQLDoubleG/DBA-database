CREATE TABLE [dbo].[WindowsSku]
(
[WindowsConstant] [sys].[sysname] NOT NULL,
[HexValue] [sql_variant] NULL,
[IntValue] AS (CONVERT([int],[HexValue],(0))),
[Meaning] [varchar] (128) COLLATE Latin1_General_CI_AS NULL
) ON [PRIMARY]
GO
