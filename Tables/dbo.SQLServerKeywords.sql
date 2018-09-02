CREATE TABLE [dbo].[SQLServerKeywords]
(
[SQLServerProduct] [sys].[sysname] NOT NULL,
[keyword] [sys].[sysname] NOT NULL
) ON [PRIMARY]
GO
ALTER TABLE [dbo].[SQLServerKeywords] ADD CONSTRAINT [UQ_SQLServerKeywords_SQLServerProduct_keyword] UNIQUE NONCLUSTERED  ([SQLServerProduct], [keyword]) ON [PRIMARY]
GO
