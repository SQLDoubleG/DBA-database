CREATE TABLE [dbo].[TallyTime]
(
[FullTime] [time] (0) NOT NULL,
[HoursMinutes] [time] (0) NULL,
[HourOfDay] [tinyint] NULL,
[Minute] [tinyint] NULL,
[Second] [tinyint] NULL,
[AM-PM] [char] (2) COLLATE Latin1_General_CI_AS NULL,
[IsWorkingHours] [bit] NULL
) ON [PRIMARY]
GO
ALTER TABLE [dbo].[TallyTime] ADD CONSTRAINT [PK_TallyTime] PRIMARY KEY CLUSTERED  ([FullTime]) ON [PRIMARY]
GO
