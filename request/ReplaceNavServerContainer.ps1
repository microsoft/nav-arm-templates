Param(
    [string] $queryString
)

$alwaysPull = ([System.Web.HttpUtility]::ParseQueryString($queryString)).Get("alwayspull")
$parameters = @{}
if ($alwaysPull -eq "yes") {
    $parameters += @{ "alwayspull" = $true }
}

Replace-NavServerContainer @parameters
