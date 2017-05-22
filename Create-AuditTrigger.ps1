$targetServer = 'SCSBENSQLDEV01'
$targetDB = 'ATOReporting_UAT'
$targetSchema = 'aux'
$targetTable = 'DistributionLists'

[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.Smo')
$SMO = New-Object 'Microsoft.SqlServer.Management.Smo.Server' $targetServer
$Database = $SMO.Databases.Item($targetDB)


$table = $Database.Tables.Item($targetTable, $targetSchema)

function createTable {

    param(
        [Microsoft.SqlServer.Management.Smo.Table] $sourcetable,
        [string] $schema
    )


    [Microsoft.SqlServer.Management.Smo.Database] $DB = $souretable.Parent

#    [Microsoft.SqlServer.Management.Smo.Table] $copiedTable = 
#        New-Object Microsoft.SqlServer.Management.Smo.Table ($DB, [string] "$($sourceTable.Name)_Copy", $schema)

    [Microsoft.SqlServer.Management.Smo.Table] $copiedtable = `
        New-Object Microsoft.SqlServer.Management.Smo.Table ([Microsoft.SqlServer.Management.Smo.Database] $Database, [string] "$($sourcetable.Name)", $schema)


    [Microsoft.SqlServer.Management.Smo.Server] $server = $sourcetable.Parent.Parent

#    createColumns [Microsoft.SqlServer.Management.Smo.Table] $sourcetable, [Microsoft.SqlServer.Management.Smo.Table] $copiedtable
    createColumns $sourcetable $copiedtable


    $copiedtable.AnsiNullsStatus = $sourceTable.AnsiNullsStatus
    $copiedtable.QuotedIdentifierStatus = $sourcetable.QuotedIdentifierStatus
    $copiedtable.TextFileGroup = $sourcetable.TextFileGroup
    $copiedtable.FileGroup = $sourcetable.FileGroup
    $copiedtable.Create()

}

function createColumns {
    param(
        [Microsoft.SqlServer.Management.Smo.Table] $sourceTable,
        [Microsoft.SqlServer.Management.Smo.Table] $copiedTable
    )

    [Microsoft.SqlServer.Management.Smo.Server] $server = $sourceTable.Parent.Parent
    foreach ($source in $sourceTable.Columns){
        [Microsoft.SqlServer.Management.Smo.Column] $column = 
            New-Object Microsoft.SqlServer.Management.Smo.Column($copiedTable, $source.Name, $source.DataType)
        $column.Collation = $source.Collation
        $column.Nullable = $source.Nullable
        $column.Computed = $source.Computed
        $column.ComputedText = $source.ComputedText
        $column.Default = $source.Default
        
        if ($source.DefaultConstraint -ne $null) {
            [string] $tabname = $copiedTable.Name
            [string] $constrname  = $source.DefaultConstraint.Name
            $column.AddDefaultConstraint("$tabname_$constrname")
            $column.DefaultConstraint.Text = $source.DefaultConstraint.Text
        }

        $column.IsPersisted = $source.IsPersisted
        $column.DefaultSchema = $source.DefaultSchema
        $column.RowGuidCol = $source.RowGuidCol

        $column.IsFileStream = $source.IsFileStream
        $column.IsSparse = $source.IsSparse
        $column.IsColumnSet = $source.IsColumnSet

        $copiedTable.Columns.Add($column)

    }

    $dt = new-object Microsoft.SqlServer.Management.Smo.DataType([Microsoft.SqlServer.Management.Smo.SqlDataType]::NVarChar, 255)
        [Microsoft.SqlServer.Management.Smo.Column] $column = 
            New-Object Microsoft.SqlServer.Management.Smo.Column($copiedTable, 'auditUser', $dt)
    $copiedTable.Columns.Add($column)    
    
    $dt = new-object Microsoft.SqlServer.Management.Smo.DataType([Microsoft.SqlServer.Management.Smo.SqlDataType]::NVarChar, 64)
        [Microsoft.SqlServer.Management.Smo.Column] $column = 
            New-Object Microsoft.SqlServer.Management.Smo.Column($copiedTable, 'auditReason', $dt)
    $copiedTable.Columns.Add($column)

    $dt = new-object Microsoft.SqlServer.Management.Smo.DataType([Microsoft.SqlServer.Management.Smo.SqlDataType]::DateTime)
        [Microsoft.SqlServer.Management.Smo.Column] $column = 
            New-Object Microsoft.SqlServer.Management.Smo.Column($copiedTable, 'auditTimeStamp', $dt)
    $copiedTable.Columns.Add($column)

}

$auditSchema = "audit_$targetSchema"
if (!$Database.Schemas.Item($auditSchema)) {
    $newSchema = New-Object Microsoft.SqlServer.Management.SMO.Schema $Database, $auditSchema
    $newSchema.Owner = 'dbo'
    $newSchema.Create()
}

createTable $table $auditSchema


$trigger = New-Object Microsoft.SqlServer.Management.SMO.Trigger $table, 'audit_trigger'

$trigger.TextMode = $false
$trigger.Insert = $false
$trigger.Update = $true
$trigger.Delete = $true
$triggerText = @"
BEGIN
INSERT INTO $($auditSchema).$($targetTable)
SELECT
    $($table.Columns | %{"$($_.Name),`n`t"})
	[auditUserName] = USER_ID()
	,[auditReason] = 'UPDATED'
	,[auditTimeStamp] = GETDATE()
FROM inserted;
INSERT INTO $($auditSchema).$($targetTable)
SELECT
    $($table.Columns | %{"$($_.Name),`n`t"})
	[auditUserName] = USER_ID()
	,[auditReason] = 'DELETED'
	,[auditTimeStamp] = GETDATE()
FROM deleted;
END
"@

$triggerText
$trigger.TextBody = $triggerText
#$trigger.ImplementationType = [Microsoft.SqlServer.Management.SMO.ImplementationType]::TransactSql


$trigger.Create()
