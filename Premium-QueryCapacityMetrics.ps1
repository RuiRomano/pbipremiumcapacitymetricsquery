#Requires -Modules @{ ModuleName="MicrosoftPowerBIMgmt"; ModuleVersion="1.2.1026" }
param(
    $datasetId = "1ca0779a-0802-4c44-8521-a92ee70f6490"
    ,
    $capacityId = "7DE26338-A4B5-445D-A455-058B336117A3"
    ,
    $startDate = $null
    ,
    $outputPath = ".\output"
)

$ErrorActionPreference = "Stop"

$currentPath = (Split-Path $MyInvocation.MyCommand.Definition -Parent)

Set-Location $currentPath

$stateFilePath = "$currentPath\state.json"

if (Test-Path $stateFilePath)
{
    $state = Get-Content $stateFilePath | ConvertFrom-Json

    if (!($state.LastRun -is [datetime])) {
        $state.LastRun = [datetime]::Parse($state.LastRun).ToUniversalTime()
    }
}
else
{
    $state = @{
        LastRun = [Datetime]::UtcNow.Date.AddDays(-10)
    }
}

if ($startDate -eq $null)
{
    $startDate = $state.LastRun
}

$endDate = [datetime]::UtcNow.Date

Connect-PowerBIServiceAccount 

Write-Host "Getting data for '$startDate' - '$endDate'"

while($startDate -le $endDate)
{
    Write-Host "Getting data for '$startDate'"

    $query = "
    DEFINE
    MPARAMETER CapacityID =
        ""$capacityId""
    EVALUATE 
        SUMMARIZECOLUMNS(
          'Artifacts'[Artifact]
          , 'Operation Names'[OperationName]
          , 'Dates'[Date]     
          , TREATAS({""CPU""}, 'Metrics'[Metric])
          , TREATAS({""$capacityId""}, 'Capacities'[capacityId])
          , FILTER(ALL('Dates'[Date]), 'Dates'[Date] = dt""$($startDate.ToString("yyyy-MM-dd"))"")        
          ,""CPUSeconds"", 'All Measures'[Dynamic M1 CPU]
          ,""DurationSeconds"", 'All Measures'[Dynamic M1 Duration]
          ,""Users"", 'All Measures'[Dynamic M1 Users]
          ,""Memory"", 'All Measures'[Dynamic M1 Memory]
        )"

        $body = @{
            "queries" = @(
                @{               
                    "query" = $query

                    ;
                    "includeNulls" = $false
                }
            )
        }

    $bodyStr = $body | ConvertTo-Json

    $result = Invoke-PowerBIRestMethod -url "datasets/$datasetId/executeQueries" -body $bodyStr -method Post | ConvertFrom-Json

    $outputData = $result.results[0].tables[0].rows
     
    $outputData | select -First 100 | Format-Table

    Write-Host ("Saving data from: {0:yyyy-MM-dd}" -f $startDate)    
    
    $outputFilePath = ("$outputPath\$capacityId_{0:yyyyMMdd}.csv" -f $startDate)
    
    New-Item -ItemType Directory -Path (Split-Path $outputFilePath -Parent) -ErrorAction SilentlyContinue | Out-Null

    $outputData | ConvertTo-Csv -NoTypeInformation | Out-File $outputFilePath    

    $state.LastRun = $startDate.Date.ToString("o")

    ConvertTo-Json $state | Out-File $stateFilePath -force -Encoding utf8

    $startDate = $startDate.AddDays(1)
}

