param([switch]$SmokeTest, [switch]$ShowPanel)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Windows.Forms;
using System.Runtime.InteropServices;
public static class IconHandle { [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr h); }
public static class MonitorDpi {
 [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr context);
}
public class SmoothTaskbarLabel : Label {
 private bool hovered;
 public SmoothTaskbarLabel() {
   SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer, true);
 }
 protected override void OnMouseEnter(EventArgs e) { hovered=true; Invalidate(); base.OnMouseEnter(e); }
 protected override void OnMouseLeave(EventArgs e) { hovered=false; Invalidate(); base.OnMouseLeave(e); }
 protected override void OnPaint(PaintEventArgs e) {
   e.Graphics.Clear(BackColor);
   if(hovered) {
     e.Graphics.SmoothingMode=System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
     using(var shape=new System.Drawing.Drawing2D.GraphicsPath())
     using(var fill=new SolidBrush(BackColor.GetBrightness()>0.5f ? Color.FromArgb(22,0,0,0) : Color.FromArgb(32,255,255,255))) {
       int left=2,top=2,right=Width-3,bottom=Height-3,radius=10;
       shape.AddArc(left,top,radius,radius,180,90);
       shape.AddArc(right-radius,top,radius,radius,270,90);
       shape.AddArc(right-radius,bottom-radius,radius,radius,0,90);
       shape.AddArc(left,bottom-radius,radius,radius,90,90);
       shape.CloseFigure(); e.Graphics.FillPath(fill,shape);
     }
   }
   e.Graphics.TextRenderingHint=System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
   using(var brush=new SolidBrush(ForeColor))
   using(var format=(StringFormat)StringFormat.GenericTypographic.Clone()) {
     format.Alignment=StringAlignment.Center; format.LineAlignment=StringAlignment.Center;
     format.FormatFlags |= StringFormatFlags.NoWrap;
     // En spaces keep the period and percentage visibly separated at clock size.
     e.Graphics.DrawString(Text.Replace(" ","\u2002"),Font,brush,new RectangleF(0,0,Width,Height),format);
   }
 }
}
public class TaskbarText : Form {
 [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left,Top,Right,Bottom; }
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern IntPtr FindWindow(string cls,string title);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern IntPtr FindWindowEx(IntPtr parent,IntPtr after,string cls,string title);
 [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hwnd,out RECT rect);
 [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hwnd);
 [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr hwnd,IntPtr after,int x,int y,int w,int h,uint flags);
 public bool PositionOnTaskbar() {
   var bar=FindWindow("Shell_TrayWnd",null);
   var tray=FindWindowEx(bar,IntPtr.Zero,"TrayNotifyWnd",null);
   RECT b,t;
   if(bar==IntPtr.Zero || tray==IntPtr.Zero || !IsWindowVisible(bar) || !GetWindowRect(bar,out b) || !GetWindowRect(tray,out t)) { Hide(); return false; }
   var screen=Screen.FromHandle(bar).Bounds;
   int h=b.Bottom-b.Top;
   if(h<20 || h>120 || b.Top>=screen.Bottom-3 || t.Left-b.Left<Width+20) { Hide(); return false; }
   int x=t.Left-Width-8,y=b.Top+(h-Height)/2;
   try { using(var pixel=new Bitmap(1,1)) {
     using(var g=Graphics.FromImage(pixel)) g.CopyFromScreen(x,b.Top+2,0,0,new Size(1,1));
     BackColor=pixel.GetPixel(0,0);
   } } catch { BackColor=Color.FromArgb(28,28,28); }
   Location=new Point(x,y);
   if(!Visible) Show();
   SetWindowPos(Handle,new IntPtr(-1),x,y,Width,Height,0x10|0x40);
   return true;
 }
 protected override bool ShowWithoutActivation { get { return true; } }
 protected override CreateParams CreateParams {
   get { var p=base.CreateParams; p.ExStyle |= 0x08000000 | 0x80; return p; }
 }
 public TaskbarText() {
   Text="Codex Taskbar Text"; FormBorderStyle=FormBorderStyle.None;
   ShowInTaskbar=false; TopMost=true; AutoScaleMode=AutoScaleMode.None;
   Font=new Font("Segoe UI Variable Text",SystemFonts.MessageBoxFont.SizeInPoints,FontStyle.Regular); ForeColor=Color.FromArgb(74,222,128);
   ClientSize=new Size(168,36); Cursor=Cursors.Hand;
 }
}
'@
[void][MonitorDpi]::SetProcessDpiAwarenessContext([IntPtr](-4))
if ($SmokeTest) { [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::ThrowException) }
[System.Windows.Forms.Application]::EnableVisualStyles()
$mutex = New-Object Threading.Mutex($false, 'Local\CodexTokenMonitorWindows')
if (-not $mutex.WaitOne(0)) { $mutex.Dispose(); exit }
$script:job = $null
$script:lastRefresh = [datetime]::MinValue
$script:status = $null
$node = (Get-Command node.exe -ErrorAction Stop).Source
$backend = Join-Path $PSScriptRoot 'backend.cjs'
$form = New-Object Windows.Forms.Form
$form.Text = 'Codex Token Monitor'
$form.Size = New-Object Drawing.Size(460, 550)
$form.StartPosition = 'Manual'
$form.ShowInTaskbar = $false
$form.TopMost = $false
$form.BackColor = [Drawing.Color]::FromArgb(25,29,36)
$form.ForeColor = [Drawing.Color]::WhiteSmoke
$form.Font = New-Object Drawing.Font('Segoe UI', 10)
$form.FormBorderStyle = 'FixedToolWindow'
$title = New-Object Windows.Forms.Label
$title.Text = 'CODEX · USO DA CONTA'
$title.SetBounds(20,16,410,30)
$title.Font = New-Object Drawing.Font('Segoe UI', 13, [Drawing.FontStyle]::Bold)
$form.Controls.Add($title)
$details = New-Object Windows.Forms.TextBox
$details.Multiline = $true
$details.ReadOnly = $true
$details.ScrollBars = 'Vertical'
$details.BorderStyle = 'None'
$details.BackColor = $form.BackColor
$details.ForeColor = $form.ForeColor
$details.SetBounds(20,180,405,120)
$details.Text = 'Credenciais não configuradas. Clique em Entrar com ChatGPT.'
$form.Controls.Add($details)
function New-LimitRow($parent, $name, $x, $y, $width) {
    $label = New-Object Windows.Forms.Label
    $label.SetBounds($x,$y,$width,26)
    $label.Font = New-Object Drawing.Font('Segoe UI',11,[Drawing.FontStyle]::Bold)
    $label.Text = $name + '  —'
    $parent.Controls.Add($label)
    return [pscustomobject]@{Label=$label;Name=$name}
}
function Update-LimitRow($row, $quota) {
    $hasValue = $quota -and $null -ne $quota.remaining
    $value = if ($hasValue) { [Math]::Max(0,[Math]::Min(100,[double]$quota.remaining)) } else { 0 }
    $row.Label.Text = if ($hasValue) { $row.Name + ('  {0:0}% disponível' -f $value) } else { $row.Name + '  —' }

}
$panelShort = New-LimitRow $form '5h' 20 60 405
$panelWeekly = New-LimitRow $form 'Semana' 20 115 405
$shortReset = New-Object Windows.Forms.Label
$shortReset.SetBounds(20,90,405,24)
$shortReset.ForeColor = [Drawing.Color]::Silver
$form.Controls.Add($shortReset)
$weeklyReset = New-Object Windows.Forms.Label
$weeklyReset.SetBounds(20,145,405,24)
$weeklyReset.ForeColor = [Drawing.Color]::Silver
$form.Controls.Add($weeklyReset)

function Button($text, $x, $y, $width) {
    $b = New-Object Windows.Forms.Button
    $b.Text = $text
    $b.SetBounds($x,$y,$width,36)
    $b.FlatStyle = 'Flat'
    $form.Controls.Add($b)
    return $b
}
$refresh = Button 'Atualizar' 20 415 125
$login = Button 'Entrar com ChatGPT' 155 415 265
$logout = Button 'Remover credenciais' 20 460 220
$hide = Button 'Fechar painel' 250 460 170
$tray = New-Object Windows.Forms.NotifyIcon
$tray.Text = 'Codex Token Monitor'
$weeklyTray = New-Object Windows.Forms.NotifyIcon
$weeklyTray.Text = 'Codex · Semana'
$taskbarText = New-Object TaskbarText
$taskbarLabel = New-Object SmoothTaskbarLabel
$taskbarLabel.Dock = 'Fill'
$taskbarLabel.TextAlign = 'MiddleCenter'
$taskbarLabel.Text = '5H — | 7D —'
$taskbarLabel.Font = $taskbarText.Font
$taskbarLabel.AccessibleName = 'Limites disponíveis do Codex: 5 horas e 7 dias'
$taskbarText.Controls.Add($taskbarLabel)
$appearanceFile = Join-Path $env:LOCALAPPDATA 'CodexTokenMonitor\profile\appearance.json'
$script:appearanceLoading = $true
$script:customColor = '#4ADE80'
$fontSizes = @(9.0,10.8,12.0)
$fontOptions = @($fontSizes | ForEach-Object { New-Object Drawing.Font('Segoe UI Variable Text',[single]$_,[Drawing.FontStyle]::Regular) })
$colorNames = @('Verde','Azul','Branco','Amarelo','Laranja','Vermelho','Roxo','Rosa','Ciano','Personalizada')
$colorValues = @('#4ADE80','#60A5FA','#F5F5F5','#FACC15','#FB923C','#F87171','#C084FC','#F472B6','#22D3EE')
$fontCaption = New-Object Windows.Forms.Label
$fontCaption.Text = 'Tamanho da fonte'
$fontCaption.SetBounds(20,310,195,25)
$form.Controls.Add($fontCaption)
$fontChoice = New-Object Windows.Forms.ComboBox
$fontChoice.DropDownStyle = 'DropDownList'
$fontChoice.SetBounds(20,337,195,30)
[void]$fontChoice.Items.AddRange([object[]]@('Pequena · 9 pt','Média · 10,8 pt','Grande · 12 pt'))
$form.Controls.Add($fontChoice)
$colorCaption = New-Object Windows.Forms.Label
$colorCaption.Text = 'Cor do texto'
$colorCaption.SetBounds(230,310,195,25)
$form.Controls.Add($colorCaption)
$colorChoice = New-Object Windows.Forms.ComboBox
$colorChoice.DropDownStyle = 'DropDownList'
$colorChoice.SetBounds(230,337,195,30)
[void]$colorChoice.Items.AddRange([object[]]$colorNames)
$form.Controls.Add($colorChoice)
$customColorButton = Button 'Escolher outra cor…' 230 373 195
$appearanceMessage = New-Object Windows.Forms.Label
$appearanceMessage.Text = 'Alterações salvas automaticamente.'
$appearanceMessage.ForeColor = [Drawing.Color]::Silver
$appearanceMessage.SetBounds(20,374,205,34)
$appearanceMessage.Font = New-Object Drawing.Font('Segoe UI',9)
$form.Controls.Add($appearanceMessage)
function Apply-Appearance {
    if ($fontChoice.SelectedIndex -lt 0 -or $colorChoice.SelectedIndex -lt 0) { return }
    $size = [single]$fontSizes[$fontChoice.SelectedIndex]
    $hex = if ($colorChoice.SelectedIndex -eq 9) { $script:customColor } else { $colorValues[$colorChoice.SelectedIndex] }
    $color = [Drawing.ColorTranslator]::FromHtml($hex)
    $newFont = $fontOptions[$fontChoice.SelectedIndex]
    $taskbarText.Font = $newFont
    $taskbarLabel.Font = $newFont
    $taskbarText.ForeColor = $color
    $taskbarLabel.ForeColor = $color
    $panelShort.Label.Font = $newFont; $panelWeekly.Label.Font = $newFont
    $panelShort.Label.ForeColor = $color; $panelWeekly.Label.ForeColor = $color
    $taskbarText.Width = [int][Math]::Ceiling(168 * $size / 9)
    [void]$taskbarText.PositionOnTaskbar()
    if ($tray.Icon -and $script:status) { Render-Status $script:status }
    $taskbarLabel.Invalidate()
    if (-not $script:appearanceLoading) {
        try {
            $parent = Split-Path $appearanceFile
            [void][IO.Directory]::CreateDirectory($parent)
            $value = @{size=$fontChoice.SelectedIndex;color=$colorChoice.SelectedIndex;custom_color=$script:customColor} | ConvertTo-Json -Compress
            $temporary = $appearanceFile + '.tmp'
            [IO.File]::WriteAllText($temporary,$value,(New-Object Text.UTF8Encoding($false)))
            if ([IO.File]::Exists($appearanceFile)) { [IO.File]::Replace($temporary,$appearanceFile,[NullString]::Value) } else { [IO.File]::Move($temporary,$appearanceFile) }
            $appearanceMessage.Text = 'Alterações salvas automaticamente.'
        } catch { $appearanceMessage.Text = 'Aplicado; não foi possível salvar.' }
    }
}
$fontChoice.Add_SelectedIndexChanged({ Apply-Appearance })
$colorChoice.Add_SelectedIndexChanged({ Apply-Appearance })
$customColorButton.Add_Click({
    $dialog = New-Object Windows.Forms.ColorDialog
    $dialog.FullOpen = $true
    $dialog.Color = $taskbarText.ForeColor
    if ($dialog.ShowDialog($form) -eq [Windows.Forms.DialogResult]::OK) {
        $script:customColor = '#{0:X2}{1:X2}{2:X2}' -f $dialog.Color.R,$dialog.Color.G,$dialog.Color.B
        $colorChoice.SelectedIndex = 9
        Apply-Appearance
    }
    $dialog.Dispose()
})
$savedAppearance = $null
try { $savedAppearance = [IO.File]::ReadAllText($appearanceFile) | ConvertFrom-Json } catch { }
if ($savedAppearance -and $savedAppearance.custom_color -match '^#[0-9a-fA-F]{6}$') { $script:customColor = $savedAppearance.custom_color }
$fontChoice.SelectedIndex = if ($savedAppearance -and $savedAppearance.size -in @(0,1,2)) { [int]$savedAppearance.size } else { 0 }
$colorChoice.SelectedIndex = if ($savedAppearance -and $savedAppearance.color -in @(0,1,2,3,4,5,6,7,8,9)) { [int]$savedAppearance.color } else { 0 }
Apply-Appearance
$script:appearanceLoading = $false
$taskbarLabel.Add_Click({ Show-Panel })
$taskbarTip = New-Object Windows.Forms.ToolTip
$positionTimer = New-Object Windows.Forms.Timer
$positionTimer.Interval = 1000
$positionTimer.Add_Tick({ [void]$taskbarText.PositionOnTaskbar() })
function Set-TrayIcon($target, $name, $percent) {
    $bitmap = New-Object Drawing.Bitmap(32,32)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $graphics.Clear([Drawing.Color]::Transparent)
    $graphics.TextRenderingHint = [Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $color = $taskbarText.ForeColor
    $brush = New-Object Drawing.SolidBrush($color)
    $valueText = if ($name -eq 'percentage') { if ($null -eq $percent) { '—' } else { '{0:0}%' -f $percent } } else { $name + '-' }
    $fontSize = if ($valueText.Length -ge 4) { 15 } else { 20 }
    $valueFont = New-Object Drawing.Font('Segoe UI',$fontSize,[Drawing.FontStyle]::Bold,[Drawing.GraphicsUnit]::Pixel)
    $format = New-Object Drawing.StringFormat
    $format.Alignment = 'Center'; $format.LineAlignment = 'Center'
    $format.FormatFlags = [Drawing.StringFormatFlags]::NoWrap -bor [Drawing.StringFormatFlags]::NoClip
    while ($graphics.MeasureString($valueText,$valueFont,1000,$format).Width -gt 32 -and $fontSize -gt 10) {
        $valueFont.Dispose()
        $fontSize--
        $valueFont = New-Object Drawing.Font('Segoe UI',$fontSize,[Drawing.FontStyle]::Bold,[Drawing.GraphicsUnit]::Pixel)
    }
    $graphics.DrawString($valueText,$valueFont,$brush,(New-Object Drawing.RectangleF(0,0,32,32)),$format)
    $handle = $bitmap.GetHicon()
    $temporaryIcon = [Drawing.Icon]::FromHandle($handle)
    $newIcon = $temporaryIcon.Clone()
    $oldIcon = $target.Icon
    $target.Icon = $newIcon
    if ($oldIcon) { $oldIcon.Dispose() }
    $temporaryIcon.Dispose()
    [void][IconHandle]::DestroyIcon($handle)
    $valueFont.Dispose(); $brush.Dispose(); $format.Dispose(); $graphics.Dispose(); $bitmap.Dispose()
}
function Show-Panel {
    $area = [Windows.Forms.Screen]::FromPoint([Windows.Forms.Cursor]::Position).WorkingArea
    $form.Location = New-Object Drawing.Point(($area.Right - $form.Width - 12),($area.Bottom - $form.Height - 12))
    $form.Show(); $form.Activate()
}
function Start-Read($action) {
    if ($script:job) { return }
    $refresh.Enabled = $false; $login.Enabled = $false; $logout.Enabled = $false
    $details.Text = if ($action -eq 'login') { 'Conclua o login no navegador. A sessão pertence somente a este widget.' } else { 'Atualizando...' }
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $node
    $info.Arguments = '"' + $backend + '" ' + $action
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = [Text.Encoding]::UTF8
    $script:job = New-Object Diagnostics.Process
    $script:job.StartInfo = $info
    [void]$script:job.Start()
    $script:output = $script:job.StandardOutput.ReadToEndAsync()
    $script:stderr = $script:job.StandardError.ReadToEndAsync()
    $script:deadline = [datetime]::Now.AddSeconds($(if ($action -eq 'login') { 230 } else { 65 }))
}
function Render-Status($s) {
    $quotas = @($s.quotas | Where-Object { $_ })
    $codexQuotas = @($quotas | Where-Object { $_.bucket_id -eq 'codex' })
    if ($codexQuotas.Count -gt 0) { $quotas = $codexQuotas }
    $short = $quotas | Where-Object { $_.slot -eq 'primary' -and $_.window_minutes -ne 10080 } | Select-Object -First 1
    $weekly = $quotas | Where-Object { $_.window_minutes -eq 10080 } | Select-Object -First 1
    $shortName = if ($short.window_minutes) { '{0:g}h' -f ($short.window_minutes/60) } else { '5h' }
    $panelShort.Name = $shortName
    Update-LimitRow $panelShort $short
    Update-LimitRow $panelWeekly $weekly
    $shortReset.Text = if ($short) { 'Renova: ' + $short.resets } else { 'Limite de uso indisponível' }
    $weeklyReset.Text = if ($weekly) { 'Renova: ' + $weekly.resets } else { 'Limite semanal indisponível' }
    $lines = New-Object 'Collections.Generic.List[string]'
    if ($s.configured) {
        $lines.Add('Plano: ' + $s.plan)
        $lines.Add('')
        foreach ($q in $s.quotas) {
            $remaining = if ($null -eq $q.remaining) { 'Indisponível' } else { '{0:0}% restante' -f $q.remaining }
            $lines.Add($q.title + ': ' + $remaining)
            $lines.Add('Renova: ' + $q.resets)
            $lines.Add('')
        }
        $lines.Add('Tokens acumulados: ' + $s.lifetime_tokens)
        $lines.Add('Último dia (' + $s.daily_date + '): ' + $s.daily_tokens)
        $lines.Add('')
        $lines.Add('Atualizado: ' + $s.sampled_at)
    }
    foreach ($message in $s.errors) { $lines.Add($message) }
    $details.Text = $lines -join "`r`n"
    Set-TrayIcon $tray $shortName $short.remaining
    Set-TrayIcon $weeklyTray 'percentage' $short.remaining
    $shortTip = if ($short -and $null -ne $short.remaining) { '{0:0}%' -f $short.remaining } else { '—' }
    $weeklyTip = if ($weekly -and $null -ne $weekly.remaining) { '{0:0}%' -f $weekly.remaining } else { '—' }
    $taskbarLabel.Text = ('{0} {1} | 7D {2}' -f $shortName.ToUpperInvariant(),$shortTip,$weeklyTip)
    $taskbarTip.SetToolTip($taskbarLabel,('Percentual disponível. ' + $shortReset.Text + ' | Semana: ' + $weeklyReset.Text))
    $tooltip = ('Codex: {0} {1} | 7d {2} disponível' -f $shortName,$shortTip,$weeklyTip)
    $tray.Text = $shortName + '-' + $shortTip + ' | 7d-' + $weeklyTip + ' disponível · Codex'
    $weeklyTray.Text = $tray.Text
    $refresh.Enabled = $true
    $login.Enabled = -not $s.configured
    $logout.Enabled = [bool]$s.configured
}
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 250
$timer.Add_Tick({
    if ($script:job) {
        if ($script:job.HasExited -and $script:output.IsCompleted) {
            try { $script:status = $script:output.Result | ConvertFrom-Json } catch { $script:status = [pscustomobject]@{configured=$false; errors=@('Não foi possível atualizar os dados.')} }
            $script:job.Dispose(); $script:job = $null
            $script:lastRefresh = [datetime]::Now
            Render-Status $script:status
        } elseif ([datetime]::Now -gt $script:deadline) {
            # Kill the entire isolated worker tree, including its app-server.
            & "$env:SystemRoot\System32\taskkill.exe" /PID $script:job.Id /T /F *> $null
            $script:job.Dispose(); $script:job = $null
            $script:lastRefresh = [datetime]::Now
            Render-Status ([pscustomobject]@{configured=$false; errors=@('Tempo limite. Tente novamente.')})
        }
    } elseif (([datetime]::Now - $script:lastRefresh).TotalSeconds -ge 15) { Start-Read 'read' }
})
$refresh.Add_Click({ Start-Read 'read' })
$login.Add_Click({ Start-Read 'login' })
$logout.Add_Click({ Start-Read 'logout' })
$hide.Add_Click({ $form.Hide() })
$form.Add_FormClosing({ param($sender,$e) if ($e.CloseReason -eq 'UserClosing') { $e.Cancel = $true; $form.Hide() } })
$tray.Add_MouseClick({ param($sender,$e) if ($e.Button -eq [Windows.Forms.MouseButtons]::Left) { Show-Panel } })
$menu = New-Object Windows.Forms.ContextMenuStrip
[void]$menu.Items.Add('Abrir painel', $null, { Show-Panel })
[void]$menu.Items.Add('Atualizar', $null, { Start-Read 'read' })
[void]$menu.Items.Add('Sair', $null, { [Windows.Forms.Application]::Exit() })
$tray.ContextMenuStrip = $menu
$weeklyTray.ContextMenuStrip = $menu
$taskbarText.ContextMenuStrip = $menu
$taskbarLabel.ContextMenuStrip = $menu
$weeklyTray.Add_MouseClick({ param($sender,$e) if ($e.Button -eq [Windows.Forms.MouseButtons]::Left) { Show-Panel } })
try {
    Set-TrayIcon $tray '5h' $null
    Set-TrayIcon $weeklyTray 'percentage' $null
    $tray.Visible = $false
    $weeklyTray.Visible = $false
    [void]$taskbarText.PositionOnTaskbar()
    $positionTimer.Start()
    if ($SmokeTest) {
        $script:appearanceLoading = $true
        $originalSize = $fontChoice.SelectedIndex; $originalColor = $colorChoice.SelectedIndex
        foreach ($i in @(0,1,2)) {
            $fontChoice.SelectedIndex = $i
            if ([Math]::Abs($taskbarLabel.Font.SizeInPoints-$fontSizes[$i]) -gt 0.01) { throw 'Tamanho de fonte não aplicado.' }
        }
        foreach ($i in @(0,1,2,3,4,5,6,7,8)) {
            $colorChoice.SelectedIndex = $i
            if ($taskbarLabel.ForeColor.ToArgb() -ne [Drawing.ColorTranslator]::FromHtml($colorValues[$i]).ToArgb()) { throw 'Cor não aplicada ou alterada ao reposicionar.' }
        }
        $originalFile = $appearanceFile; $originalCustom = $script:customColor
        $appearanceFile = Join-Path $env:TEMP ('codex-appearance-test-' + [Guid]::NewGuid().ToString() + '.json')
        try {
            $script:appearanceLoading = $false
            $script:customColor = '#123456'
            $fontChoice.SelectedIndex = 1; $colorChoice.SelectedIndex = 9
            Apply-Appearance
            $persisted = [IO.File]::ReadAllText($appearanceFile) | ConvertFrom-Json
            if ($persisted.size -ne 1 -or $persisted.color -ne 9 -or $persisted.custom_color -ne '#123456') { throw ('Preferências não persistiram: ' + ($persisted | ConvertTo-Json -Compress) + ' / ' + $appearanceMessage.Text) }
            if ($taskbarLabel.ForeColor.ToArgb() -ne [Drawing.ColorTranslator]::FromHtml('#123456').ToArgb()) { throw 'Cor personalizada não aplicada.' }
        } finally {
            [IO.File]::Delete($appearanceFile)
            [IO.File]::Delete($appearanceFile + '.tmp')
            $appearanceFile = $originalFile; $script:customColor = $originalCustom
            $script:appearanceLoading = $true
        }
        $fontChoice.SelectedIndex = $originalSize; $colorChoice.SelectedIndex = $originalColor
        $script:appearanceLoading = $false
        $fixture = [pscustomobject]@{configured=$true;plan='plus';errors=@();quotas=@(
            [pscustomobject]@{bucket_id='codex';slot='primary';window_minutes=300;remaining=86;resets='10/10/2026 às 18:00'},
            [pscustomobject]@{bucket_id='codex';slot='secondary';window_minutes=10080;remaining=97;resets='14/10/2026 às 12:00'}
        ); lifetime_tokens='1.234';daily_tokens='123';daily_date='2026-10-07';sampled_at='07/10/2026 às 18:00'}
        Render-Status $fixture
        if ($panelShort.Label.Text -notmatch '86%' -or $panelWeekly.Label.Text -notmatch '97%') { throw 'Percentuais não exibidos.' }
        if ($tray.Text -notmatch '5h-86% \| 7d-97%' -or $weeklyTray.Text -ne $tray.Text) { throw 'Informações dos ícones incompletas.' }
        if (-not $tray.Icon -or -not $weeklyTray.Icon) { throw 'Ícones não gerados.' }
        if ($taskbarLabel.Text -ne '5H 86% | 7D 97%') { throw 'Texto da barra incorreto.' }
        if ($tray.Visible -or $weeklyTray.Visible -or -not $taskbarText.Visible) { throw 'Somente o texto fora da bandeja deveria aparecer.' }
        $preview = New-Object Drawing.Bitmap($taskbarText.Width,$taskbarText.Height)
        $taskbarText.DrawToBitmap($preview,(New-Object Drawing.Rectangle(0,0,$preview.Width,$preview.Height)))
        $preview.Save((Join-Path $env:TEMP 'codex-taskbar-text.png'),[Drawing.Imaging.ImageFormat]::Png)
        $mouseEnter = $taskbarLabel.GetType().GetMethod('OnMouseEnter',[Reflection.BindingFlags]'Instance,NonPublic')
        [void]$mouseEnter.Invoke($taskbarLabel,[object[]]@([EventArgs]::Empty))
        $taskbarText.DrawToBitmap($preview,(New-Object Drawing.Rectangle(0,0,$preview.Width,$preview.Height)))
        $preview.Save((Join-Path $env:TEMP 'codex-taskbar-hover.png'),[Drawing.Imaging.ImageFormat]::Png)
        $mouseLeave = $taskbarLabel.GetType().GetMethod('OnMouseLeave',[Reflection.BindingFlags]'Instance,NonPublic')
        [void]$mouseLeave.Invoke($taskbarLabel,[object[]]@([EventArgs]::Empty))
        $preview.Dispose()
        Render-Status ([pscustomobject]@{configured=$false;errors=@('Teste sem conta.');quotas=@()})
        if ($tray.Text -match '86%' -or $weeklyTray.Text -match '97%') { throw 'Valores antigos permaneceram após falha.' }
        if ($taskbarLabel.Text -ne '5H — | 7D —') { throw 'Texto não limpo após falha.' }
        Render-Status $fixture
        $script:lastRefresh = [datetime]::Now
        Write-Output 'Texto fora da bandeja, fontes, cores e preferências: OK.'
    } else { Start-Read 'read' }
    $timer.Start()
    if ($ShowPanel) { Show-Panel }
    if ($SmokeTest) {
        $smokeTimer = New-Object Windows.Forms.Timer
        $smokeTimer.Interval = 3000
        $smokeTimer.Add_Tick({ [Windows.Forms.Application]::Exit() })
        $smokeTimer.Start()
    }
    [Windows.Forms.Application]::Run()
} finally {
    $timer.Stop(); $timer.Dispose()
    $positionTimer.Stop(); $positionTimer.Dispose()
    if ($script:job -and -not $script:job.HasExited) { & "$env:SystemRoot\System32\taskkill.exe" /PID $script:job.Id /T /F *> $null }
    $tray.Visible = $false
    $weeklyTray.Visible = $false
    if ($weeklyTray.Icon) { $weeklyTray.Icon.Dispose() }
    $weeklyTray.Dispose()
    if ($tray.Icon) { $tray.Icon.Dispose() }
    $tray.Dispose(); $menu.Dispose(); $taskbarTip.Dispose(); $taskbarText.Dispose(); $form.Dispose()
    foreach ($font in $fontOptions) { $font.Dispose() }
    $mutex.ReleaseMutex(); $mutex.Dispose()
}
