param(
    [switch]$Kill,
    [int]$TimeoutSeconds = 5,
    [string]$WatchProcess = ""
)

Add-Type -AssemblyName PresentationFramework

$pidFile = Join-Path $PSScriptRoot ".splash.pid"
$logFile = Join-Path $PSScriptRoot ".splash.log"

function Write-SplashLog($msg) {
    $ts = Get-Date -Format "HH:mm:ss.fff"
    "$ts - $msg" | Out-File -FilePath $logFile -Append -Encoding UTF8
}

if ($Kill) {
    Write-SplashLog "Kill mode - reading PID file"
    $procsToKill = @()
    if (Test-Path $pidFile) {
        $pidVal = Get-Content $pidFile -ErrorAction SilentlyContinue
        if ($pidVal) {
            $proc = Get-Process -Id $pidVal -ErrorAction SilentlyContinue
            if ($proc) { $procsToKill += $proc }
        }
        Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
    }
    foreach ($p in $procsToKill) {
        try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {}
    }
    Write-SplashLog "Kill complete"
    exit 0
}

Set-Content -Path $pidFile -Value $PID
Write-SplashLog "Splash starting - PID=$PID, Session=$([System.Diagnostics.Process]::GetCurrentProcess().SessionId), Timeout=${TimeoutSeconds}s"

$xaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="SplashScreen"
    WindowStyle="None"
    WindowState="Maximized"
    Topmost="True"
    ShowInTaskbar="False"
    Background="#0d1117">
    <Grid>
        <Border
            Name="CardBorder"
            Background="#161b22"
            CornerRadius="15"
            BorderBrush="#30363d"
            BorderThickness="1"
            Width="480"
            Height="260"
            HorizontalAlignment="Center"
            VerticalAlignment="Center"
            Padding="30">
            <Border.Effect>
                <DropShadowEffect
                    Color="Black"
                    ShadowDepth="0"
                    BlurRadius="30"
                    Opacity="0.35"
                    RenderingBias="Performance" />
            </Border.Effect>
            <StackPanel>
                <Rectangle
                    Name="SpinnerRect"
                    Fill="#58a6ff"
                    Width="420"
                    Height="4"
                    RadiusX="2"
                    RadiusY="2"
                    HorizontalAlignment="Stretch"
                    VerticalAlignment="Bottom"
                    Opacity="0.3" />
                <TextBlock
                    Name="StatusText"
                    Text="Launching..."
                    Foreground="#58a6ff"
                    FontSize="32"
                    FontFamily="Segoe UI"
                    FontWeight="SemiBold"
                    HorizontalAlignment="Center"
                    Margin="0,20,0,0"
                    TextOptions.TextFormattingMode="Display" />
                <TextBlock
                    Name="SubText"
                    Text="Please wait"
                    Foreground="#8b949e"
                    FontSize="14"
                    FontFamily="Segoe UI"
                    HorizontalAlignment="Center"
                    Margin="0,8,0,0"
                    TextOptions.TextFormattingMode="Display" />
            </StackPanel>
        </Border>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

$fontPath = Join-Path $PSScriptRoot "..\assets\fonts\BungeeHairline-Regular.ttf"
$fontFamily = $null
if (Test-Path $fontPath) {
    try {
        $fontFamily = New-Object System.Windows.Media.FontFamily("$fontPath#Bungee Hairline")
    } catch {
        Write-Error "Failed to load Bungee Hairline font: $($_.Exception.Message)"
    }
}

$statusText = $window.FindName("StatusText")
if ($fontFamily) {
    $statusText.FontFamily = $fontFamily
    $statusText.FontWeight = [System.Windows.FontWeights]::Normal
} else {
    $statusText.FontSize = 24
    $statusText.FontWeight = [System.Windows.FontWeights]::SemiBold
}

$spinner = $window.FindName("SpinnerRect")

$anim = New-Object System.Windows.Media.Animation.DoubleAnimation
$anim.From = 0
$anim.To = 420
$anim.Duration = [System.TimeSpan]::FromSeconds(1.5)
$anim.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
$anim.AutoReverse = $true
$anim.EasingFunction = New-Object System.Windows.Media.Animation.SineEase -Property @{ EasingMode = "EaseInOut" }
$spinner.BeginAnimation([System.Windows.Shapes.Rectangle]::WidthProperty, $anim) | Out-Null

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds($TimeoutSeconds)

$script:closing = $false
$script:showStartTime = [DateTime]::MinValue

$closeWindow = {
    if ($script:closing) { return }
    $script:closing = $true
    $timer.Stop()
    if ($script:watchTimer) { $script:watchTimer.Stop() }
    $anim.Freeze()
    $window.Close()
}

$timer.Add_Tick($closeWindow)
$window.Add_Deactivated($closeWindow)

# Process watcher - polls for the app process to appear
$script:WatchProcess = $WatchProcess
$script:watchTimer = $null
if ($WatchProcess) {
    Write-SplashLog "Watching for process matching: $WatchProcess"
    $script:watchTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:watchTimer.Interval = [TimeSpan]::FromMilliseconds(200)
    $script:watchTimer.Add_Tick({
            if ($script:showStartTime -eq [DateTime]::MinValue -or (Get-Date) - $script:showStartTime -lt [TimeSpan]::FromSeconds(2)) {
            return
        }
        try {
            $found = [System.Diagnostics.Process]::GetProcesses() |
                Where-Object { $_.ProcessName -like $script:WatchProcess }
            if ($found) {
                Write-SplashLog ("WatchProcess detected (" + ($found.Count) + " match(es)) - closing splash")
                & $closeWindow
            }
        } catch {
            Write-SplashLog "WatchProcess error: $($_.Exception.Message)"
        }
    })
    $script:watchTimer.Start()
}

$timer.Start()

Write-SplashLog "Window showing (ShowDialog)..."
$script:showStartTime = Get-Date
$window.ShowDialog() | Out-Null
Write-SplashLog "Window closed"

Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
Write-SplashLog "Splash exiting"
