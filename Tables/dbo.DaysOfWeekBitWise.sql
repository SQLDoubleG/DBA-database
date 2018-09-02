CREATE TABLE [dbo].[DaysOfWeekBitWise]
(
[bitValue] [tinyint] NOT NULL,
[name] [varchar] (10) COLLATE Latin1_General_CI_AS NULL,
[DayNumberOfTheWeek] [tinyint] NULL
) ON [PRIMARY]
GO
ALTER TABLE [dbo].[DaysOfWeekBitWise] ADD CONSTRAINT [PK__DaysOfWe__3002031277AABCF8] PRIMARY KEY CLUSTERED  ([bitValue]) ON [PRIMARY]
GO
