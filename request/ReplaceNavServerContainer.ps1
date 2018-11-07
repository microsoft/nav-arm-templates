Param(
    [string] $alwaysPull = "no"
)

Replace-NavServerContainer -alwaysPull:($alwaysPull -eq "yes")
