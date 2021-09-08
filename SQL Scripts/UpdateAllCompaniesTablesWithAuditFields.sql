-- Create store procedure to add audit fields to all tables belonging to a specific company.
-- Note this script is intended to be used for upgrade from 15x version - not earlier. 
-- Reason is that it relies on table name schema used starting with version 15x. Prior to that table name did not use app id.
-- Parameters:
-- @Company - company name formatted as part of table name schema
-- @Debug_mode - Set to TRUE if you only want to print out DDL statements which will be executed 
CREATE OR ALTER PROCEDURE UpdateAuditFieldsForAllTablesInCompany @Company nvarchar(30), @Debug_mode bit
AS
declare @Sql NVARCHAR(MAX)
,             @AddAuditFieldsToTables CURSOR;

SET @AddAuditFieldsToTables = CURSOR FOR

SELECT 'IF ( OBJECTPROPERTY(OBJECT_ID(N''' + QUOTENAME(name) + '''), N''IsTable'')=1 AND COL_LENGTH(N'''+QUOTENAME(name)+''', N''$systemCreatedAt'') IS NULL) 
BEGIN ALTER TABLE '+ QUOTENAME(name) + 'ADD [$systemCreatedAt] [datetime] NOT NULL CONSTRAINT [MDF$' + name + '$$systemCreatedAt] DEFAULT (''1753.01.01''), [$systemCreatedBy] [uniqueidentifier] NOT NULL CONSTRAINT [MDF$' + name + '$$systemCreatedBy] DEFAULT (''00000000-0000-0000-0000-000000000000''), [$systemModifiedAt] [datetime] NOT NULL CONSTRAINT [MDF$' + name + '$$systemModifiedAt]  DEFAULT (''1753.01.01''), [$systemModifiedBy] [uniqueidentifier] NOT NULL CONSTRAINT [MDF$' + name + '$$systemModifiedBy]  DEFAULT (''00000000-0000-0000-0000-000000000000'') END '
FROM sys.tables WITH (NOLOCK)
WHERE name like @Company + '$%' and TRY_CONVERT(UNIQUEIDENTIFIER, RIGHT(name,36)) IS NOT NULL
;

OPEN @AddAuditFieldsToTables

FETCH NEXT FROM @AddAuditFieldsToTables INTO @Sql 

WHILE (@@FETCH_STATUS = 0)
BEGIN

	PRINT @Sql

	if (@debug_mode = 'FALSE') 
		BEGIN
				EXEC sp_executesql @Sql 
		END

   FETCH NEXT FROM @AddAuditFieldsToTables INTO @Sql 
END

CLOSE @AddAuditFieldsToTables
DEALLOCATE @AddAuditFieldsToTables

GO

-- Create store procedure to add system id to all company specfici tables. 
-- Parameters:
-- @Debug_mode - Set to TRUE if you only want to print out DDL statements which will be executed 
CREATE OR ALTER PROCEDURE AddAuditFieldsToAllCompanySpecificTables @Debug_mode bit
AS
declare       
@SelectCompanyName CURSOR,
@UpdateCompanyName NVARCHAR(MAX)
;

SET @SelectCompanyName= CURSOR FOR

select Name 
from Company WITH (NOLOCK)
;

OPEN @SelectCompanyName

FETCH NEXT FROM @SelectCompanyName INTO @UpdateCompanyName 

WHILE (@@FETCH_STATUS = 0)
BEGIN

-- Format company name 
SET @UpdateCompanyName = REPLACE(@UpdateCompanyName, '.', '_')
SET @UpdateCompanyName = REPLACE(@UpdateCompanyName, '"', '_')
SET @UpdateCompanyName = REPLACE(@UpdateCompanyName, '\', '_')
SET @UpdateCompanyName = REPLACE(@UpdateCompanyName, '/', '_')
SET @UpdateCompanyName = REPLACE(@UpdateCompanyName, '''', '_')
SET @UpdateCompanyName = REPLACE(@UpdateCompanyName, '%', '_')
SET @UpdateCompanyName = REPLACE(@UpdateCompanyName, ']', '_')
SET @UpdateCompanyName = REPLACE(@UpdateCompanyName, '[','_')
SET @UpdateCompanyName = 'EXEC UpdateAuditFieldsForAllTablesInCompany @Company=''' + @UpdateCompanyName + ''', @Debug_mode=''' + CONVERT(nvarchar,@debug_mode)+''''

PRINT GETDATE()
PRINT  @UpdateCompanyName 

EXEC sp_executesql @UpdateCompanyName

FETCH NEXT FROM @SelectCompanyName INTO @UpdateCompanyName
END

CLOSE @SelectCompanyName
DEALLOCATE @SelectCompanyName
GO

EXEC AddAuditFieldsToAllCompanySpecificTables true


