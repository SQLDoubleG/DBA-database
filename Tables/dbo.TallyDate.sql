CREATE TABLE [dbo].[TallyDate]
(
[FullDate] [date] NOT NULL,
[DateString] [char] (10) COLLATE Latin1_General_CI_AS NULL,
[DayOfWeek] [tinyint] NULL,
[DayOfWeekName] [varchar] (10) COLLATE Latin1_General_CI_AS NULL,
[DayOfMonth] [tinyint] NULL,
[DayOfYear] [smallint] NULL,
[WeekOfYear] [tinyint] NULL,
[MonthName] [varchar] (10) COLLATE Latin1_General_CI_AS NULL,
[MonthOfYear] [tinyint] NULL,
[CalendarQuarter] [tinyint] NULL,
[CalendarYear] [smallint] NULL,
[IsWeekend] [bit] NULL,
[IsLeapYear] [bit] NULL
) ON [PRIMARY]
GO
ALTER TABLE [dbo].[TallyDate] ADD CONSTRAINT [PK_TallyDates] PRIMARY KEY CLUSTERED  ([FullDate]) ON [PRIMARY]
GO
