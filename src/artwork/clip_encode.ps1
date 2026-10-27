# Treasure Radar's in-action clip: turns clip.py's frames into an H.264 MP4 with Windows' own encoder (no ffmpeg).
# Windows PowerShell 5.1 (it has the WinRT bindings): powershell -File clip_encode.ps1 <frames dir> <out.mp4> [fps]
param([string]$Frames, [string]$Out, [int]$Fps = 30)
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
$null = [Windows.Media.Editing.MediaComposition, Windows.Media.Editing, ContentType = WindowsRuntime]
$null = [Windows.Media.MediaProperties.MediaEncodingProfile, Windows.Media.MediaProperties, ContentType = WindowsRuntime]
# WinRT async calls as .NET tasks, waited on
$asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
  $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' }
function Await($op, [Type]$type) { $t = $asTask.MakeGenericMethod($type).Invoke($null, @($op)); $t.Wait(-1) | Out-Null; $t.Result }
$asTaskP = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
  $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperationWithProgress`2' }
function AwaitP($op, [Type]$type, [Type]$prog) { $t = $asTaskP.MakeGenericMethod($type, $prog).Invoke($null, @($op)); $t.Wait(-1) | Out-Null; $t.Result }

$comp = New-Object Windows.Media.Editing.MediaComposition
$each = [TimeSpan]::FromTicks([long](10000000 / $Fps))
$files = Get-ChildItem $Frames -Filter 'frame_*.jpg' | Sort-Object Name
# (the clip list comes through as a plain COM object: its Add is reached through the .NET collection interface)
$add = [System.Collections.Generic.ICollection[Windows.Media.Editing.MediaClip]].GetMethod('Add')
foreach ($f in $files) {
  $sf = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($f.FullName)) ([Windows.Storage.StorageFile])
  $clip = Await ([Windows.Media.Editing.MediaClip]::CreateFromImageFileAsync($sf, $each)) ([Windows.Media.Editing.MediaClip])
  $null = $add.Invoke($comp.Clips, @($clip))
}
"{0} clips, {1}" -f $comp.Clips.Count, $comp.Duration
$dir = Await ([Windows.Storage.StorageFolder]::GetFolderFromPathAsync((Split-Path -Parent $Out))) ([Windows.Storage.StorageFolder])
$file = Await ($dir.CreateFileAsync((Split-Path -Leaf $Out), [Windows.Storage.CreationCollisionOption]::ReplaceExisting)) ([Windows.Storage.StorageFile])
$prof = [Windows.Media.MediaProperties.MediaEncodingProfile]::CreateMp4([Windows.Media.MediaProperties.VideoEncodingQuality]::HD720p)
$prof.Audio = $null
$prof.Video.Bitrate = 1200000
$prof.Video.FrameRate.Numerator = $Fps; $prof.Video.FrameRate.Denominator = 1
$r = AwaitP ($comp.RenderToFileAsync($file, [Windows.Media.Editing.MediaTrimmingPreference]::Precise, $prof)) ([Windows.Media.Transcoding.TranscodeFailureReason]) ([double])
"{0} frames -> {1} ({2})" -f $files.Count, $Out, $r
