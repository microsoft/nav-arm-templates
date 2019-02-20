Param(
    [string] $imageName = "",
    [string] $alwaysPull = "no"
)

Replace-NavServerContainer -imageName $imageName -alwaysPull:($alwaysPull -eq "yes")
