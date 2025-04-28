CREATE OR ALTER PROC [dbo].[foreachdatabase] @Command nvarchar(MAX),
                               @Delimit_Character nchar(1) = N'?', --Character to be replaced with a delimit identified version of the datbaase name I.e. [master]
                               @Quote_Character nchar(1) = N'&', --Character to be replaced with a single quoted (') version of the datbaase name I.e. 'master'
                               @Skip_System bit = 0, --Omits master, msdb, tempdb and model. Ignored if @Database_List has data.
                               @Skip_User bit = 0, --Omits all user databases. Ignored if @Database_List has data.
                               @Database_List dbo.objectlist READONLY, --If @Skip_System and @Skip_User equal 1, and this is empty, an error will be thrown
                               @Auto_Use bit = 0, --Automatically starts each command agaisnt a database with a USE
                               @Exit_On_Error bit = 1, --If an error is occurs against a single database, the command will still be run against the remainder. Otherwise everything is rolled back
                                                       --This does not effect the @Pre_Command and @Post_Command statements
                               @Pre_Command nvarchar(MAX) = NULL, --Command to run before @Command. Does not use Character Replacements. Run against master DB.
                               @Post_Command nvarchar(MAX) = NULL, --Command to run after @Command. Does not use Character Replacements. Run against master DB.
                               @Command_Run nvarchar(MAX) = NULL OUTPUT,  --Returns the generated and replaced command, for trouble shooting
                               @WhatIf bit = 0 --Don't actually run the statements; @Command_Run will still return the batch that would have been run
/*
Written by Thom A 2019-11-26
Original Source: https://wp.larnu.uk/a-cursor-free-version-of-sp_msforeachdb/
Licenced under CC BY-ND 4.0
*/
AS BEGIN

    --Do some checking of passed values first
    DECLARE @ErrorMessage nvarchar(2000);

    --Check that @Skip_System, @Skip_User aren't both 0 or that @Database_List has some rows
    IF (@Skip_System = 1 AND @Skip_User = 1 AND NOT EXISTS (SELECT 1 FROM @Database_List))
        THROW 62401, N'System and User databases cannot be skipped if a Database List is not supplied.', 16;

    IF @Delimit_Character IS NULL OR @Delimit_Character = '' BEGIN
        SET @ErrorMessage = FORMATMESSAGE(N'%s cannot have a value of NULL or ''''.',N'@Delimit_Character');
        THROW 62402, @ErrorMessage, 16;
    END;

    IF @Quote_Character IS NULL OR @Quote_Character = '' BEGIN
        SET @ErrorMessage = FORMATMESSAGE(N'%s cannot have a value of NULL or ''''.',N'@Quote_Character');
        THROW 62402, @ErrorMessage, 16;
    END;

    IF @Skip_User IS NULL BEGIN
        SET @ErrorMessage = FORMATMESSAGE(N'%s cannot have a value of NULL.',N'@Skip_User');
        THROW 62403, @ErrorMessage, 16;
    END;

    IF @Skip_System IS NULL BEGIN
        SET @ErrorMessage = FORMATMESSAGE(N'%s cannot have a value of NULL.',N'@Skip_System');
        THROW 62403, @ErrorMessage, 16;
    END;

    IF @Exit_On_Error IS NULL BEGIN
        SET @ErrorMessage = FORMATMESSAGE(N'%s cannot have a value of NULL.',N'@Exit_On_Error');
        THROW 62403, @ErrorMessage, 16;
    END;

    IF @Auto_Use IS NULL BEGIN
        SET @ErrorMessage = FORMATMESSAGE(N'Msg 62404, Level 1, State 1' + NCHAR(10) +N'%s has a value of NULL. Behaviour will be as if the value is 0.',N'@Exit_On_Error')
        PRINT @ErrorMessage;
    END;

    IF @WhatIf IS NULL BEGIN
        SET @ErrorMessage = FORMATMESSAGE(N'Msg 62404, Level 1, State 1' + NCHAR(10) +N'%s has a value of NULL. Behaviour will be as if the value is 0.',N'@WhatIf')
        PRINT @ErrorMessage;
    END;

    DECLARE @CRLF nchar(2) = NCHAR(13) + NCHAR(10);
    DECLARE @RC int;

    --Add the Pre Command to the batch
    SET @Command_Run = ISNULL(N'/* --- Pre Command Begin. --- */' + @CRLF + @CRLF + N'USE master;' + @CRLF + @CRLF + @Pre_Command + @CRLF + @CRLF + N'/* --- Pre Command End. --- */', N'');

    --Get the databases we need to deal with
    --As @Database_List might be empty and it's READONLY, and we're going to do the command in database_id order we need another variable.
    DECLARE @DBs table (database_id int,
                        database_name sysname);
    IF EXISTS (SELECT 1 FROM @Database_List)
        INSERT INTO @DBs (database_id,database_name)
        SELECT d.database_id,
               d.[name]
        FROM sys.databases d
             JOIN @Database_List DL ON d.[name] = DL.[name]
        WHERE d.state_desc != 'OFFLINE';
    ELSE
        INSERT INTO @DBs (database_id,database_name)
        SELECT d.database_id,
               d.[name]
        FROM sys.databases d
        WHERE (((d.database_id <= 4 OR d.is_distributor = 1) AND @Skip_System = 0)
           OR (d.database_id > 4 AND @Skip_User = 0 AND d.is_distributor = 0))
          AND d.state_desc != 'OFFLINE';

    SET @Command_Run = @Command_Run + @CRLF + @CRLF +
                       N'/* --- Begin command for each database. --- */' + @CRLF + @CRLF +
                       CASE WHEN @Exit_On_Error = 0 THEN N'--Turning XACT_ABORT off due to @Exit_On_Error parameter' + @CRLF + @CRLF + N'SET XACT_ABORT OFF;' + @CRLF + N'DECLARE @Error nvarchar(4000);' ELSE N'SET XACT_ABORT ON;' END +
                       (SELECT @CRLF + @CRLF + 
                               N'/* --- Running @Command against database ' + QUOTENAME(DB.database_name,'''') + N'. --- */' + @CRLF + @CRLF +
                               CASE WHEN @Auto_Use = 1 THEN N'USE ' + QUOTENAME(DB.database_name) + N';' + @CRLF + @CRLF ELSE N'' END +
                               N'BEGIN TRY' + @CRLF + @CRLF +
                               REPLACE(REPLACE(@Command, @Delimit_Character, QUOTENAME(DB.database_name)),@Quote_Character, 'N' + QUOTENAME(DB.database_name,'''')) + @CRLF + @CRLF +
                               'END TRY' + @CRLF +
                               N'BEGIN CATCH' + @CRLF +
                               CASE WHEN @Exit_On_Error = 0 THEN N'    SET @Error = N''The following error occured during the batch, but has been skipped:'' + NCHAR(13) + NCHAR(10) + ' + @CRLF +
                                                                 N'                 N''Msg '' + CONVERT(nvarchar(6),ERROR_NUMBER()) + '', Level '' + CONVERT(nvarchar(6),ERROR_SEVERITY()) + '', State '' + CONVERT(nvarchar(6),ERROR_STATE()) + '', Line '' + CONVERT(nvarchar(6),ERROR_LINE()) + NCHAR(13) + NCHAR(10) +' + @CRLF + 
                                                                 N'                 ERROR_MESSAGE();' + @CRLF +
                                                                 N'    PRINT @Error;' + @CRLF +
                                                                 N'    SET @RC = ERROR_NUMBER();'
                                                            ELSE N'    THROW;'
                               END + @CRLF +
                               N'END CATCH;' + @CRLF +
                               N'/* --- Completed @Command against database ' + QUOTENAME(DB.database_name,'''') + N'. --- */'
                        FROM @DBs DB
                        FOR XML PATH(N''),TYPE).value('.','nvarchar(MAX)') + @CRLF + @CRLF +
                        CASE WHEN @Exit_On_Error = 0 THEN N'--Turning XACT_ABORT back on due to @Exit_On_Error parameter' + @CRLF + @CRLF + N'SET XACT_ABORT ON;' ELSE N'' END;

    SET @Command_Run = @Command_Run + ISNULL(@CRLF + @CRLF + N'/* --- Post Command Begin. --- */' + @CRLF + @CRLF + N'USE master;' + @CRLF + @CRLF + @Post_Command + @CRLF + @CRLF + N'/* --- Post Command End. --- */', N'');
    
    IF @WhatIf = 0
        EXEC sp_executesql @Command_Run, N'@RC int OUTPUT', @RC = @RC;
    ELSE
        PRINT N'What if: see value returned from @Command_Run.';

    SET @RC = ISNULL(@RC, 0);
    RETURN @RC;

END;
