CREATE TABLE [dbo].[PowershellAuditScripts]
(
[ID] [tinyint] NOT NULL,
[Name] [varchar] (128) COLLATE Latin1_General_CI_AS NOT NULL,
[Script] [varchar] (4000) COLLATE Latin1_General_CI_AS NOT NULL
) ON [PRIMARY]
GO
ALTER TABLE [dbo].[PowershellAuditScripts] ADD CONSTRAINT [PK_PowershellAuditScripts] PRIMARY KEY CLUSTERED  ([ID]) ON [PRIMARY]
GO
