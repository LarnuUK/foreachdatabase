# foreachdatabase
A cursor free alternative to sp_msforeachdb with additional parameters.

# Requirements
`foreachdatabase` - SQL Server 2012+ (Does not support Azure SQL Database)
`foreachdatabase_agg` - SQL Server 2017+ (Does not support Azure SQL Database)

# Deployment
Execute the `dbo.objectlist.sql` and then `dbo.foreachdatabase.sql` files in your desired database. The schema can be changed from `dbo` without issue; just note that the schema for the `@Database_List` must be updated if the schema of `objectlist` is changed.

An alternative solution, using `STRING_AGG`, is also available in `dbo.foreachdatabase_agg.sql`.

# Usage
By default, the `?` charater is used for replacement of the database name, like with sp_msforeachdb. The most basic usage would be to simply provide the command you want as a literal: `EXEC dbo.foreachdatabase N'USE ?; SELECT DB_NAME();'`. The procedure has the ability to have both pre and post commends run, using the `@Pre_Command` and `@Post_Command` parameters, and returns the command run in the `@Command_run` `OUTPUT` parameter. The `@WhatIf` parameter can be used in conjuction with the `@Command_run` parameter to get the statement(s) that would be run without it actually executing them.

## Syntax
```sql
[DECLARE @<objectlist> dbo.objectlist[;]
  [INSERT INTO @<objectlist> [(name)]
   VALUES(<sysname>)[,... n]][;]]

EXECUTE dbo.foreachdatabase [@Command =] <nvarchar>
                            [, @Delimit_Character = <nchar>]
                            [, @Quote_Character =  <nchar>]
                            [, @Skip_System = <bit>
                            |, @Skip_User = <bit>
                            |, @Database_List = <objectlist>]
                            [, @Auto_use = <bit>]
                            [, @Exit_On_Error = <bit>]
                            [, @Pre_Command = <nvarchar>]
                            [, @Post_Command = <nvarchar>]
                            [, @Command_Run = <nvarchar> OUTPUT]
                            [, @WhatIf = <bit>][;]
```

## Arguements

### @Command
One or more T-SQL statements to be executed. Can be any string data type, however, `nvarchar(MAX)` is recommended.

`@Command` is required.

### @Delimit_Character
A single character to denote what character will be replaced by the database name in delimit identified format, for example `[msdb]`, in the `@Command` parameter. **Any instances** of the character in the parameter will be replaced. Can be any string type of length `1`, however, `nchar` is recommended.

`@Delimit_Character` is not required. The default value is `N'?'`. `NULL` is not a permissable value and will cause error 62402 to be returned.

### @Quote_Character
A single character to denote what character will be replaced by the database name in single quote identified format with a notation character prefixed, for example `N'msdb'`, in the `@Command` parameter. **Any instances** of the character in the parameter will be replaced. Can be any string type of length `1`, however, `nchar` is recommended.

`@Quote_Character` is not required. The default value is `N'&'`. `NULL` is not a permissable value and will cause error 62403 to be returned.

### @Skip_System
A bit to denote if system databases should be skipped by the procedure; this includes `master`, `msdb`, `tempdb`, `model` and any databases marked as a distributor database. If the value `1`/`TRUE` is passed, then system databases will not have statements from `@Command` run against them.

`@Skip_System` is not required. The default value is `0`. `NULL` is not a permissable value and will cause error 62405 to be returned.

The value of `@Skip_System` is ignored if `@Database_List` is provided containing rows.

### @Skip_User
A bit to denote if users databases should be skipped by the procedure (these are any databases not denoted as a system database per `@skip_system`). If the value `1`/`TRUE` is passed, then user databases will not have statements from `@Command` run against them.

`@Skip_User` is not required. The default value is `0`. `NULL` is not a permissable value and will cause error 62404 to be returned.

The value of `@Skip_User_` is ignored if `@Database_List` is provided containing rows.

### @Database_List
A table variable, of type `dbo.objectlist` containing an explicit list of databases to run statements against; no other databases will be run against. If  `@Database_List` is provided containing rows then the values of `@Skip_User` and `@Skip_System` are ignored.

If a database name is provided that does not exist in the system, no statements will be attempted to be run against that database.

> #### Note
> If both `@Skip_System` and `@Skip_User` are supplied with a value of `1` and `@Database_List` contains no rows, error 62401 will be returned.

### @Auto_Use
A bit to denote if prior to each command against the database, a `USE` statement to change database context should be used.

`@Auto_Use` is not required. The default value is `0`; a value of `NULL` will be treated as `0`.

### @Exit_On_Error
A bit to denote if on encountering an error against a specific database if the entire process should be aborted or not.

If set to `1` then the entire batch will be aborted and a `ROLLBACK` completed for as much as possible. If set to `0` then the batch will continue. The error will be `PRINT`ed and the procedure will also return the last error number generated as its `RETURN` value.

`@Auto_Use` is not required. The default value is `1`. `NULL` is not a permissable value and will cause error 62406 to be returned.

### @Pre_Command
A command to be executed prior to the execution of `@Command` for each database. `@Pre_Command` is run within the `master` database; use an explicit `USE` statement to have the statement run in a different database. Can be any string data type, however, `nvarchar(MAX)` is recommended.

`@Pre_Command` is not required. The default value is `NULL`.

### @Post_Command
A command to be executed prior to the execution of `@Command` for each database. `@Post_Command` is run within the `master` database; use an explicit `USE` statement to have the statement run in a different database. Can be any string data type, however, `nvarchar(MAX)` is recommended.

`@Post_Command` is not required. The default value is `NULL`.

### @Command_Run
Provides the full set of statements that would (or was) executed by `dbo.foreachdatabase`. Can be any string data type, however, `nvarchar(MAX)` is recommended.

`@Command_Run` is not required. Any value within a variable will passed will be overwritten.

### @WhatIf
A bit to denote that no statements should be run against each database. If set to `1` the statements are only prepared and not executed. Should be used alongside `@Command_Run` to obtain what statement(s) will have been executed.

`@WhatIf` is not required. The default value is `0`; a value of `NULL` will be treated as `0`.

# Examples

## Table count in each database
A simple execution to return the count of tables in each database, using a literal for `@Command`, while not using any of the additional parameters of the procedure:
```sql
EXEC dbo.foreachdatabase N'USE ?; SELECT COUNT(*) FROM sys.tables';
```

## Insert Table count for user databases into temporary table 
Insert the data from the counts into a temporary table. Utilise the `@Quote_Character` feature (using default value) and `@Auto_Use`. Also utilise the pre and post commands to `CREATE` and `SELECT` against the temporary table:
```sql
EXEC dbo.foreachdatabase @Command = N'INSERT INTO #Counts (DatabaseName, TableCount) SELECT &, COUNT(*) FROM sys.tables;',
                         @Skip_System = 1,
                         @Auto_Use = 1,
                         @Pre_Command = N'CREATE TABLE #Counts (DatabaseName sysname, TableCount int);',
                         @Post_Command = N'SELECT DatabaseName, TableCount FROM #Counts;'
```

## Provide a specific list of databases and ignore errors
Execute a command, stored in the variable `@Command`, to be run against an explicit list of databases. Also ignore any errors that may occur in each database:
```sql
DECLARE @Databases dbo.objectlist;
INSERT INTO @Databases (name)
VALUES(N'MyDatabases'),(N'YourDatabase'),(N'SampleDatabase');

EXEC dbo.foreachdatabase @Command = @Command,
                         @Database_List = @Databases,
                         @Auto_Use = 1,
                         @Exit_On_Error = 0;
```

## Overide default quote character and object the statements that would be run for tests
Prepared the statements to be run against each database, in the variable `@Command`, but not execute them, and store the statement(s) would be run in the variable `@StatementsToBeRun`. Also override the value of the quote character to a pipe (`|`).
```sql
DECLARE @StatementsToBeRun nvarchar(MAX);

EXEC dbo.foreachdatabase @Command = @Command,
                         @Auto_Use = 1,
                         @Skip_System = 1,
                         @Quote_Character = N'|',
                         @Command_Run = @StatementsToBeRun OUTPUT,
                         @WhatIf = 1;

PRINT @StatementsToBeRun;
```
