
#partimos de  una app registrada en spotify
#https://developer.spotify.com/dashboard


#obtenemos un code navegando a authorize , para dar el ok
#cambiamos el code por un token

#el callback de la app tiene que coincidir con el que estamos usando para las dos llamadas

$scriptPath = $MyInvocation.MyCommand.Path
[string] $StatePath = "$(Split-Path $scriptPath -Parent)/state.xml"


$client_id = 'fffffffffffffffffffffffffffffffffffff'
$client_secret = 'fffffffffffffffffffffffffffffffffffff'

#intentamos primero refrescar el token
$access_token = ""


# Convert to SecureString
[securestring]$secStringPassword = ConvertTo-SecureString $client_secret -AsPlainText -Force
[pscredential]$credObject = New-Object System.Management.Automation.PSCredential ($client_id, $secStringPassword)

if (Test-Path -Path $StatePath) {

    $state = Import-Clixml -Path $StatePath
    $response = Invoke-RestMethod `
        -Uri "https://accounts.spotify.com/api/token" `
        -Method Post `
        -Body "grant_type=refresh_token&refresh_token=$($state.refresh_token)" `
        -ContentType "application/x-www-form-urlencoded" `
        -Authentication Basic `
        -Credential $credObject 

    $access_token = $response.access_token
    #$refresh_token =$response.refresh_token    
    Write-Output "access_token: $access_token"

}
else {
    $callback = 'http://localhost:8888/callback'
    $callbackEncoded = [System.Web.HttpUtility]::UrlEncode($callback);
    #$scope = 'user-read-private user-read-email';
    [string[]] $Scope = @(
        "user-modify-playback-state",
        "user-read-playback-state",
        "user-read-currently-playing",
        "user-read-recently-played",
        "user-read-playback-position",
        "user-top-read",
        "playlist-read-collaborative",
        "playlist-modify-public",
        "playlist-read-private",
        "playlist-modify-private",
        "app-remote-control",
        "streaming",
        "user-read-email",
        "user-read-private",
        "user-library-modify",
        "user-library-read")

    $state = -join ((65..90) + (97..122) | Get-Random -Count 16 | % { [char]$_ })

    $Form = @{
        response_type = 'code'
        client_id     = $client_id
        scope         = $scope
        redirect_uri  = $callbackEncoded
        state         = $state
    }

    $query = [system.String]::Join("&", @($Form.Keys | ForEach-Object { "$_=$($Form[$_])" }))
    $url = "https://accounts.spotify.com/authorize?$query"

    <# 
        Add-Type -AssemblyName System.Windows.Forms 
        Add-Type -AssemblyName System.Drawing

        $form = New-Object Windows.Forms.Form
        $form.Width = 450
        $form.Height = 650

        $web = New-Object Windows.Forms.WebBrowser
        $web.Width = 420
        $web.Height = 600
        $web.Url = $url

        # Evento para interceptar la navegación
        $web.ScriptErrorsSuppressed = $true
        $form.Controls.Add($web)
        $form.show()
    #>  

    # Create a new HttpListener instance
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add("$callback/")  # Ensure this matches your redirect URI
    $listener.Start()
    Write-Output "Listening for OAuth callback on $callback/"


    Start-Process $url

    # Wait for an incoming request
    $context = $listener.GetContext()
    $request = $context.Request

    # Extract the query parameters from the request
    $queryParams = [System.Web.HttpUtility]::ParseQueryString($request.Url.Query)
    $authCode = $queryParams["code"]

    Write-Output "Authorization code received: $authCode"

    $listener.Stop()
    $listener.Prefixes.Clear()
    $listener.Dispose()


    $bytes = [System.Text.Encoding]::UTF8.GetBytes("$client_id" + ":" + "$client_secret")
    $Authorization = [System.Convert]::ToBase64String($bytes)

    $headers = @{
        'content-type'  = 'application/x-www-form-urlencoded'
        'Authorization' = "Basic $Authorization"
    }
    $body = @{        
        code         = $authCode
        redirect_uri = $callback
        grant_type   = 'authorization_code'
    }

    $url = 'https://accounts.spotify.com/api/token'
    try {
        $response = Invoke-RestMethod -Uri $url -Method Post -ContentType "application/x-www-form-urlencoded" -Body $body -Headers $headers
    }
    catch {
        $_.Exception
    }

    $access_token = $response.access_token
    #$refresh_token =$response.refresh_token

    Write-Output "access_token: $access_token"    
    $response  | Export-Clixml -Path $StatePath -Force
}

$headers = @{
    Authorization = "Bearer $access_token"
}

$lista=@()
#lee listas
try {
    $playlist = Invoke-RestMethod `
        -Uri "https://api.spotify.com/v1/me/playlists?limit=50" `
        -Method Get `
        -Headers $headers `
        -ContentType "application/json" 
} 
catch {
    $_.Exception
}

#filtra las de favoritos
$nombres = @('Favoritos', 'Favoritas de la radio')
$favoritosIds = $playlist.items | Where-Object { $nombres -contains $_.name } | Select-Object -ExpandProperty id


foreach ($favoritosId in $favoritosIds) {
    try {
        $r = Invoke-RestMethod `
            -Uri "https://api.spotify.com/v1/playlists/$favoritosId" `
            -Method Get `
            -Headers $headers `
            -ContentType "application/json"
    }
    catch {
        $_.Exception
    }
    $lista += $r.tracks.items.track.id
}

$offset = 0
$limit = 50
#lee canciones me gustan
while ($true) {
    try {
        $r = Invoke-RestMethod `
            -Uri "https://api.spotify.com/v1/me/tracks?offset=$offset&limit=$limit" `
            -Method Get `
            -Headers $headers `
            -ContentType "application/json"
    }
    catch {
        $_.Exception
        break
    }

    # Si no se obtuvieron más elementos, salir del bucle
    if ($r.items.Count -eq 0) {
        break
    }
    
    # Agregar los elementos obtenidos a la lista
    $lista += $r.items.track.id


    # Incrementar el offset
    $offset += $limit
}



#imprime canciones me gustan
#$lista = Get-Content -Path .\MeGustan.txt

$listaUnica = $lista | Select-Object -Unique

foreach ($l in $listaUnica) {



    try {
        $e = Invoke-RestMethod -Uri "https://api.spotify.com/v1/tracks/$l" -Method Get -Headers $headers -ContentType "application/json" 
    }
    catch {
        $_.Exception
    }
    
    #$r| ForEach-Object {@() + $_ + $_.artists + $_.album + $_.album.artists|ForEach-Object { $_.PSObject.TypeNames.Add("spfy.$($_.type)") }}
    
    $sal = $e.album.name 
    $sal += ' by '
    $contador = 0
    foreach ($a in $e.artists ) {
        $contador++
        $sal += $a.name 
        if ($e.artists.Count -eq $contador) {
            $char = ""
        }
        else {
            $char = " and "
        }

        $sal += $char
    }    
    $sal += ':"' + $e.name + '"'
    Write-Host $sal
    
}