CREATE TABLE [dbo].[SQLServerProductVersions]
(
[SQLServerProduct] [varchar] (20) COLLATE Latin1_General_CI_AS NULL,
[ResourceVersion] [varchar] (20) COLLATE Latin1_General_CI_AS NULL,
[FileVersion] [varchar] (20) COLLATE Latin1_General_CI_AS NULL,
[Description] [varchar] (512) COLLATE Latin1_General_CI_AS NULL,
[ReleaseDate] [date] NULL
) ON [PRIMARY]
GO
