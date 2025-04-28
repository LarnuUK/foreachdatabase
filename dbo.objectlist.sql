IF NOT EXISTS (SELECT 1 FROM sys.types WHERE [name] = N'objectlist')
    CREATE TYPE dbo.objectlist AS table ([name] sysname);
