<#
    PCL 2.99.0.1 (415) 下载功能修复补丁（版本专用脚本）
    ------------------------------------------------
    将官方原版 PCL 2.99.0.1 (415) 修复为可正常使用
    “下载 → 原版游戏”与“整合包安装”功能的版本。

    仅适用于官方原版 2.99.0.1 (415)（SHA256:
    0DB34E19D9EEB6D496D20FABE786EC16BBD36BA6B0CCDC8D29CB7E909C114397）。

    一般请通过上级目录的 apply_patch.ps1 调用，它会自动识别版本。
#>

param(
    [Parameter(Mandatory = $false)][string]$InputExe = "",
    [Parameter(Mandatory = $false)][string]$OutputExe = ""
)
$ErrorActionPreference = 'Stop'
Add-Type -Path (Join-Path $PSScriptRoot '..\lib\Mono.Cecil.dll')

$OriginalHash = '0DB34E19D9EEB6D496D20FABE786EC16BBD36BA6B0CCDC8D29CB7E909C114397'
if (-not $InputExe) { $InputExe = Read-Host '请输入官方原版 PCL 2.99.0.1 的 exe 路径' }
if (-not (Test-Path -LiteralPath $InputExe)) { throw ('找不到输入文件：' + $InputExe) }
if (-not $OutputExe) { $OutputExe = Join-Path (Split-Path -Parent (Resolve-Path -LiteralPath $InputExe)) 'Plain Craft Launcher 2 (下载修复版).exe' }
$hash = (Get-FileHash -LiteralPath $InputExe -Algorithm SHA256).Hash
Write-Host ('输入文件: ' + (Resolve-Path -LiteralPath $InputExe))
Write-Host ('SHA256  : ' + $hash)
if ($hash -ne $OriginalHash) { throw '输入文件不是受支持的官方原版 PCL 2.99.0.1 (415)，请使用官方原版。' }

$resolver = New-Object Mono.Cecil.DefaultAssemblyResolver
$rp = New-Object Mono.Cecil.ReaderParameters
$rp.AssemblyResolver = $resolver
$asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($InputExe, $rp)
$mod = $asm.MainModule

$resDir = [System.IO.Path]::Combine($env:TEMP, 'pclfix415_' + [guid]::NewGuid().ToString('N'))
[System.IO.Directory]::CreateDirectory($resDir) | Out-Null
$resRes = $mod.Resources | Where-Object { $_.Name -eq 'PCL.Resources.resources' }
$resStream = $resRes.GetResourceStream()
$resReader = New-Object System.Resources.ResourceReader -ArgumentList (, $resStream)
$extracted = 0
foreach ($entry in $resReader) {
    if ($entry.Value -is [byte[]]) {
        $b = [byte[]]$entry.Value
        if ($b.Length -gt 2 -and $b[0] -eq 0x4D -and $b[1] -eq 0x5A) {
            [System.IO.File]::WriteAllBytes([System.IO.Path]::Combine($resDir, ($entry.Key + '.dll')), $b)
            $extracted++
        }
    }
}
$resReader.Close()
$resolver.AddSearchDirectory($resDir)
Write-Output ('embedded refs extracted: ' + $extracted)

function Get-Type([string]$name) {
    $t = $mod.Types | Where-Object { $_.FullName -eq $name }
    if ($null -eq $t) { throw ('type not found: ' + $name) }
    return $t
}
function Get-Method([string]$typeName, [string]$name, [int]$paramCount) {
    $t = Get-Type $typeName
    $ms = @($t.Methods | Where-Object { $_.Name -eq $name -and $_.Parameters.Count -eq $paramCount })
    if ($ms.Count -eq 0) { throw ('method not found: ' + $typeName + '::' + $name) }
    return $ms[0]
}
function Find-MemberRef([string]$name, [string]$declType, [int]$paramCount) {
    $found = @()
    foreach ($r in $mod.GetMemberReferences()) {
        if ($r.Name -ne $name) { continue }
        if ($r.DeclaringType.FullName -ne $declType) { continue }
        if ($paramCount -ge 0 -and $r.Parameters.Count -ne $paramCount) { continue }
        $found += $r
    }
    return $found
}
function Find-InsOperand($method, [string]$opName, [string]$operandName) {
    foreach ($ins in $method.Body.Instructions) {
        if ($ins.OpCode.Name -ne $opName) { continue }
        if ($null -eq $ins.Operand) { continue }
        if ($ins.Operand -is [Mono.Cecil.Cil.Instruction]) { continue }
        if ($ins.Operand.Name -eq $operandName) { return $ins.Operand }
    }
    return $null
}
function New-Ins($op) { return [Mono.Cecil.Cil.Instruction]::Create($op) }
function New-InsStr($op, [string]$s) { return [Mono.Cecil.Cil.Instruction]::Create($op, $s) }
function New-InsRef($op, $operand) { return [Mono.Cecil.Cil.Instruction]::Create($op, $operand) }
function New-InsTarget($op, $target) { if ($null -eq $target) { $target = [Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Nop) } return [Mono.Cecil.Cil.Instruction]::Create($op, [Mono.Cecil.Cil.Instruction]$target) }

# Patch A
$mA = Get-Method 'PCL.PageDownloadInstall' 'LoaderInit' 0
$ia = $mA.Body.GetILProcessor()
$ldstrIns = $null
foreach ($ins in $mA.Body.Instructions) {
    if ($ins.OpCode.Code -eq [Mono.Cecil.Cil.Code]::Ldstr -and [string]$ins.Operand -eq '关闭下载') { $ldstrIns = $ins; break }
}
if ($null -eq $ldstrIns) { throw 'PatchA: ldstr not found' }
$newobjLoader = $null
$cur = $ldstrIns
while ($null -ne $cur) {
    if ($cur.OpCode.Code -eq [Mono.Cecil.Cil.Code]::Newobj -and $cur.Operand -is [Mono.Cecil.MethodReference] -and $cur.Operand.Name -eq '.ctor' -and ([string]$cur.Operand.DeclaringType.FullName).StartsWith('PCL.ModLoader/LoaderTask' + [char]96)) { $newobjLoader = $cur; break }
    $cur = $cur.Next
}
if ($null -eq $newobjLoader) { throw 'PatchA: LoaderTask ctor not found' }
$dlField = (Get-Type 'PCL.ModDownload').Fields | Where-Object { $_.Name -eq 'DlClientListLoader' }
if ($null -eq $dlField) { throw 'PatchA: field not found' }
$toRemove = New-Object System.Collections.ArrayList
$cur = $ldstrIns
while ($true) { $toRemove.Add($cur) | Out-Null; if ($cur -eq $newobjLoader) { break }; $cur = $cur.Next }
$afterA = $newobjLoader.Next
foreach ($r in $toRemove) { $ia.Remove($r) }
$ia.InsertBefore($afterA, (New-InsRef ([Mono.Cecil.Cil.OpCodes]::Ldsfld) $dlField))
Write-Output 'Patch A done'

# Patch B
$mB = Get-Method 'PCL.ModModpack' 'ModpackInstall' 3
$bodyB = $mB.Body
$ilB = $bodyB.GetILProcessor()
$blockedLdstr = $null
foreach ($ins in $bodyB.Instructions) {
    if ($ins.OpCode.Code -eq [Mono.Cecil.Cil.Code]::Ldstr -and [string]$ins.Operand -like '为遵守相关法律法规*') { $blockedLdstr = $ins; break }
}
if ($null -eq $blockedLdstr) { throw 'PatchB: blocked ldstr not found' }
$newobjEx = $blockedLdstr.Next
$throwIns = $newobjEx.Next
$finallyStart = $throwIns.Next
if ($throwIns.OpCode.Code -ne [Mono.Cecil.Cil.Code]::Throw) { throw 'PatchB: layout unexpected' }
$resultVar = New-Object Mono.Cecil.Cil.VariableDefinition -ArgumentList (, $mB.ReturnType)
$bodyB.Variables.Add($resultVar) | Out-Null
$loggerInfo = (Find-MemberRef 'Info' 'MeloongCore.Logger' 3)[0]
if ($null -eq $loggerInfo) { throw 'PatchB: Logger.Info not found' }
$srcPathStr = 'E:\Projects\PCL\本体代码\Plain Craft Launcher 2\Modules\Minecraft\ModModpack.vb'
$installMethods = @{}
foreach ($m in (Get-Type 'PCL.ModModpack').Methods) { if ($m.Name -like 'InstallPack*') { $installMethods[$m.Name] = $m } }
$retBlock = New-InsRef ([Mono.Cecil.Cil.OpCodes]::Ldloc) $resultVar
$retIns = New-Ins ([Mono.Cecil.Cil.OpCodes]::Ret)
function New-CaseIns([string]$logText, $target, [bool]$useInstanceName, [bool]$useLogo, [bool]$useBase) {
    $list = New-Object System.Collections.ArrayList
    $list.Add((New-InsStr ([Mono.Cecil.Cil.OpCodes]::Ldstr) $logText)) | Out-Null
    $list.Add((New-Ins ([Mono.Cecil.Cil.OpCodes]::Ldc_I4_0))) | Out-Null
    $list.Add((New-InsStr ([Mono.Cecil.Cil.OpCodes]::Ldstr) $srcPathStr)) | Out-Null
    $list.Add((New-InsRef ([Mono.Cecil.Cil.OpCodes]::Call) $loggerInfo)) | Out-Null
    $list.Add((New-Ins ([Mono.Cecil.Cil.OpCodes]::Ldarg_0))) | Out-Null
    $list.Add((New-InsRef ([Mono.Cecil.Cil.OpCodes]::Ldloc) $bodyB.Variables[1])) | Out-Null
    if ($useBase) { $list.Add((New-InsRef ([Mono.Cecil.Cil.OpCodes]::Ldloc) $bodyB.Variables[2])) | Out-Null }
    if ($useInstanceName) { $list.Add((New-Ins ([Mono.Cecil.Cil.OpCodes]::Ldarg_1))) | Out-Null }
    if ($useLogo) { $list.Add((New-Ins ([Mono.Cecil.Cil.OpCodes]::Ldarg_2))) | Out-Null }
    $list.Add((New-InsRef ([Mono.Cecil.Cil.OpCodes]::Call) $target)) | Out-Null
    $list.Add((New-InsRef ([Mono.Cecil.Cil.OpCodes]::Stloc) $resultVar)) | Out-Null
    $list.Add((New-InsTarget ([Mono.Cecil.Cil.OpCodes]::Leave) $retBlock)) | Out-Null
    return $list
}
$case0 = New-CaseIns '整合包种类：CurseForge' $installMethods['InstallPackCurseForge'] $true $true $true
$case1 = New-CaseIns '整合包种类：HMCL' $installMethods['InstallPackHMCL'] $false $false $true
$case2 = New-CaseIns '整合包种类：MMC' $installMethods['InstallPackMMC'] $false $false $true
$case3 = New-CaseIns '整合包种类：MCBBS' $installMethods['InstallPackMCBBS'] $true $false $true
$case4 = New-CaseIns '整合包种类：Modrinth' $installMethods['InstallPackModrinth'] $true $true $true
$case9 = New-CaseIns '整合包种类：带启动器的压缩包' $installMethods['InstallPackLauncherPack'] $false $false $true
$caseD = New-CaseIns '整合包种类：未能识别，假定为压缩包' $installMethods['InstallPackCompress'] $false $false $false
$targets = [Mono.Cecil.Cil.Instruction[]]::new(10)
$targets[0] = $case0[0]; $targets[1] = $case1[0]; $targets[2] = $case2[0]; $targets[3] = $case3[0]; $targets[4] = $case4[0]
$targets[5] = $caseD[0]; $targets[6] = $caseD[0]; $targets[7] = $caseD[0]; $targets[8] = $caseD[0]; $targets[9] = $case9[0]
$switchIns = [Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Switch, $targets)
$v4 = $bodyB.Variables[4]
$ldlocNum = New-InsRef ([Mono.Cecil.Cil.OpCodes]::Ldloc) $v4
$ldc0 = New-Ins ([Mono.Cecil.Cil.OpCodes]::Ldc_I4_0)
$switchLdloc = New-InsRef ([Mono.Cecil.Cil.OpCodes]::Ldloc) $v4
$bgeIns = New-InsTarget ([Mono.Cecil.Cil.OpCodes]::Bge_S) $switchLdloc
$brDefault = New-InsTarget ([Mono.Cecil.Cil.OpCodes]::Br) $caseD[0]
foreach ($ins in $bodyB.Instructions) {
    if ($ins.Operand -is [Mono.Cecil.Cil.Instruction] -and $ins.Operand -eq $blockedLdstr) { $ins.Operand = $ldlocNum }
}
foreach ($eh in $bodyB.ExceptionHandlers) {
    if ($eh.TryEnd -eq $blockedLdstr) { $eh.TryEnd = $ldlocNum }
    if ($eh.HandlerEnd -eq $blockedLdstr) { $eh.HandlerEnd = $ldlocNum }
}
$ilB.Remove($throwIns); $ilB.Remove($newobjEx); $ilB.Remove($blockedLdstr)
$all = New-Object System.Collections.ArrayList
foreach ($x in @($ldlocNum,$ldc0,$bgeIns,$brDefault,$switchLdloc,$switchIns)) { $all.Add($x) | Out-Null }
foreach ($c in @($case0,$case1,$case2,$case3,$case4,$case9,$caseD)) { foreach ($i in $c) { $all.Add($i) | Out-Null } }
foreach ($i in $all) { $ilB.InsertBefore($finallyStart, [Mono.Cecil.Cil.Instruction]$i) }
$last = $bodyB.Instructions[$bodyB.Instructions.Count - 1]
$ilB.InsertAfter($last, [Mono.Cecil.Cil.Instruction]$retBlock)
$ilB.InsertAfter($retBlock, [Mono.Cecil.Cil.Instruction]$retIns)
foreach ($eh in $bodyB.ExceptionHandlers) {
    if ($eh.HandlerType -eq [Mono.Cecil.Cil.ExceptionHandlerType]::Finally -and $eh.HandlerStart -eq $finallyStart) { $eh.HandlerEnd = $retBlock }
}
Write-Output 'Patch B done'

# Patch C
$mC = Get-Method 'PCL.ModModpack' 'ModpackInstall' 0
$bodyC = $mC.Body
$ilC = $bodyC.GetILProcessor()
$retC = $bodyC.Instructions[$bodyC.Instructions.Count - 1]
$oldC = @($bodyC.Instructions)
foreach ($ins in $oldC) { if ($ins -ne $retC) { $ilC.Remove($ins) } }
$strVar = New-Object Mono.Cecil.Cil.VariableDefinition -ArgumentList (, $mod.TypeSystem.String)
$bodyC.Variables.Add($strVar) | Out-Null
$closureType = (Get-Type 'PCL.ModModpack').NestedTypes | Where-Object { $_.Name -eq '_Closure$__0-0' }
$closureCtor = $closureType.Methods | Where-Object { $_.Name -eq '.ctor' -and $_.Parameters.Count -eq 0 }
$closureLambda = $closureType.Methods | Where-Object { $_.Name -eq '_Lambda$__0' -and $_.Parameters.Count -eq 0 }
$closureField = $closureType.Fields | Where-Object { $_.Name -eq '$VB$Local_File' }
$selectFile = (Find-MemberRef 'SelectFile' 'MeloongCore.Wpf.Dialogs' 4)[0]
$actionCtor = $null
foreach ($r in $mod.GetMemberReferences()) { if ($r.Name -eq '.ctor' -and $r.DeclaringType.FullName -eq 'System.Action' -and $r.Parameters.Count -eq 2) { $actionCtor = $r; break } }
$firstOrDefault = $null
foreach ($r in $mod.GetMemberReferences()) { if ($r.Name -eq 'FirstOrDefault' -and $r.DeclaringType.FullName -eq 'System.Linq.Enumerable' -and $r.Parameters.Count -eq 1) { $firstOrDefault = $r; break } }
$gim = New-Object Mono.Cecil.GenericInstanceMethod -ArgumentList (, $firstOrDefault)
$gim.GenericArguments.Add($mod.TypeSystem.String) | Out-Null
$isNullEmpty = (Find-MemberRef 'IsNullOrEmpty' 'System.String' 1)[0]
$modBase = Get-Type 'PCL.ModBase'
$runInThread = $modBase.Methods | Where-Object { $_.Name -eq 'RunInThread' -and $_.Parameters.Count -eq 1 }
$BT = [char]96
$tupleName = 'System.ValueTuple' + $BT + '2<System.String[],System.String>'
$tupleCtor = $null
foreach ($r in $mod.GetMemberReferences()) { if ($r.Name -eq '.ctor' -and $r.DeclaringType.FullName -eq $tupleName) { $tupleCtor = $r; break } }
$tupleType = $tupleCtor.DeclaringType
$oneOfName = 'MeloongCore.OneOf' + $BT + '2<System.Collections.Generic.IEnumerable' + $BT + '1<System.ValueTuple' + $BT + '2<System.String[],System.String>>,System.String>'
$opImplicit = $null
foreach ($r in $mod.GetMemberReferences()) {
    if ($r.Name -eq 'op_Implicit' -and $r.DeclaringType.FullName -eq $oneOfName -and $r.Parameters.Count -eq 1) {
        $pt = $r.Parameters[0].ParameterType
        if ($pt -is [Mono.Cecil.GenericParameter] -and $pt.Position -eq 0) { $opImplicit = $r; break }
    }
}
$nullableName = 'System.Nullable' + $BT + '1<' + $oneOfName + '>'
$nullableCtor = $null
foreach ($r in $mod.GetMemberReferences()) { if ($r.Name -eq '.ctor' -and $r.DeclaringType.FullName -eq $nullableName -and $r.Parameters.Count -eq 1) { $nullableCtor = $r; break } }
$newInsList = New-Object System.Collections.ArrayList
function AddI($ins) { $script:newInsList.Add($ins) | Out-Null }
AddI (New-InsStr ([Mono.Cecil.Cil.OpCodes]::Ldstr) '选择整合包压缩文件')
AddI (New-Ins ([Mono.Cecil.Cil.OpCodes]::Ldc_I4_0))
AddI (New-Ins ([Mono.Cecil.Cil.OpCodes]::Ldnull))
AddI (New-Ins ([Mono.Cecil.Cil.OpCodes]::Ldc_I4_1))
AddI (New-InsRef ([Mono.Cecil.Cil.OpCodes]::Newarr) $tupleType)
AddI (New-Ins ([Mono.Cecil.Cil.OpCodes]::Dup))
AddI (New-Ins ([Mono.Cecil.Cil.OpCodes]::Ldc_I4_0))
AddI (New-Ins ([Mono.Cecil.Cil.OpCodes]::Ldc_I4_3))
AddI (New-InsRef ([Mono.Cecil.Cil.OpCodes]::Newarr) $mod.TypeSystem.String)
AddI (New-Ins ([Mono.Cecil.Cil.OpCodes]::Dup))
AddI (New-Ins ([Mono.Cecil.Cil.OpCodes]::Ldc_I4_0))
AddI (New-InsStr ([Mono.Cecil.Cil.OpCodes]::Ldstr) 'rar')
AddI (New-Ins ([Mono.Cecil.Cil.OpCodes]::Stelem_Ref))
AddI (New-Ins ([Mono.Cecil.Cil.OpCodes]::Dup))
AddI (New-Ins ([Mono.Cecil.Cil.OpCodes]::Ldc_I4_1))
AddI (New-InsStr ([Mono.Cecil.Cil.OpCodes]::Ldstr) 'zip')
AddI (New-Ins ([Mono.Cecil.Cil.OpCodes]::Stelem_Ref))
AddI (New-Ins ([Mono.Cecil.Cil.OpCodes]::Dup))
AddI (New-Ins ([Mono.Cecil.Cil.OpCodes]::Ldc_I4_2))
AddI (New-InsStr ([Mono.Cecil.Cil.OpCodes]::Ldstr) 'mrpack')
AddI (New-Ins ([Mono.Cecil.Cil.OpCodes]::Stelem_Ref))
AddI (New-InsStr ([Mono.Cecil.Cil.OpCodes]::Ldstr) '整合包文件')
AddI (New-InsRef ([Mono.Cecil.Cil.OpCodes]::Newobj) $tupleCtor)
AddI ([Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Stelem_Any, [Mono.Cecil.TypeReference]$tupleType))
AddI (New-InsRef ([Mono.Cecil.Cil.OpCodes]::Call) $opImplicit)
AddI (New-InsRef ([Mono.Cecil.Cil.OpCodes]::Newobj) $nullableCtor)
AddI (New-InsRef ([Mono.Cecil.Cil.OpCodes]::Call) $selectFile)
AddI (New-InsRef ([Mono.Cecil.Cil.OpCodes]::Call) $gim)
AddI (New-InsRef ([Mono.Cecil.Cil.OpCodes]::Stloc) $strVar)
AddI (New-InsRef ([Mono.Cecil.Cil.OpCodes]::Ldloc) $strVar)
AddI (New-InsRef ([Mono.Cecil.Cil.OpCodes]::Call) $isNullEmpty)
AddI (New-InsTarget ([Mono.Cecil.Cil.OpCodes]::Brtrue_S) $retC)
AddI (New-InsRef ([Mono.Cecil.Cil.OpCodes]::Newobj) $closureCtor)
AddI (New-InsRef ([Mono.Cecil.Cil.OpCodes]::Stloc) $bodyC.Variables[0])
AddI (New-InsRef ([Mono.Cecil.Cil.OpCodes]::Ldloc) $bodyC.Variables[0])
AddI (New-InsRef ([Mono.Cecil.Cil.OpCodes]::Ldloc) $strVar)
AddI (New-InsRef ([Mono.Cecil.Cil.OpCodes]::Stfld) $closureField)
AddI (New-InsRef ([Mono.Cecil.Cil.OpCodes]::Ldloc) $bodyC.Variables[0])
AddI (New-InsRef ([Mono.Cecil.Cil.OpCodes]::Ldftn) $closureLambda)
AddI (New-InsRef ([Mono.Cecil.Cil.OpCodes]::Newobj) $actionCtor)
AddI (New-InsRef ([Mono.Cecil.Cil.OpCodes]::Call) $runInThread)
foreach ($i in $newInsList) { $ilC.InsertBefore($retC, [Mono.Cecil.Cil.Instruction]$i) }
Write-Output 'Patch C done'

# Patch D
$mD = (Get-Type 'PCL.PageDownloadLeft').Methods | Where-Object { $_.Name -eq '.ctor' -and $_.Parameters.Count -eq 0 }
$bodyD = $mD.Body
$ilD = $bodyD.GetILProcessor()
$initCall = $null
foreach ($ins in $bodyD.Instructions) {
    if ($ins.OpCode.Code -eq [Mono.Cecil.Cil.Code]::Call -and $ins.Operand -is [Mono.Cecil.MethodReference] -and $ins.Operand.Name -eq 'InitializeComponent') { $initCall = $ins; break }
}
if ($null -eq $initCall) { throw 'PatchD: init call not found' }
$retD = $bodyD.Instructions[$bodyD.Instructions.Count - 1]
$cur = $initCall.Next
while ($cur -ne $retD) { $nxt = $cur.Next; $ilD.Remove($cur); $cur = $nxt }
Write-Output 'Patch D done'

# Patch E
$mE = Get-Method 'PCL.PageLaunchLeft' 'RefreshButtonsUI' 0
$bodyE = $mE.Body
$ilE = $bodyE.GetILProcessor()
$mRef = Get-Method 'PCL.PageSelectRight' 'BtnEmptyDownload_Loaded' 0
$settingsGet = Find-InsOperand $mRef 'call' 'Get'
$hiddenForceShow = Find-InsOperand $mRef 'call' 'get_HiddenForceShow'
if ($null -eq $settingsGet -or $null -eq $hiddenForceShow) { throw 'PatchE: refs missing' }
$instrs = @($bodyE.Instructions)
$findIdx = -1
for ($i = 0; $i -lt $instrs.Count; $i++) {
    $ins = $instrs[$i]
    if ($ins.OpCode.Code -eq [Mono.Cecil.Cil.Code]::Call -and $ins.Operand -is [Mono.Cecil.MethodReference] -and $ins.Operand.Name -eq 'get_McInstanceSelected' -and $i+1 -lt $instrs.Count -and $instrs[$i+1].OpCode.Code -eq [Mono.Cecil.Cil.Code]::Brtrue_S) { $findIdx = $i; break }
}
if ($findIdx -lt 0) { throw 'PatchE: pattern not found' }
$brtrueIns = $instrs[$findIdx + 1]
$ldc1 = $instrs[$findIdx + 2]
$stloc0 = $instrs[$findIdx + 3]
$brShort = $instrs[$findIdx + 4]
$ldc3 = $instrs[$findIdx + 5]
$stloc0b = $instrs[$findIdx + 6]
$afterE = $stloc0b.Next
if ($ldc1.OpCode.Code -ne [Mono.Cecil.Cil.Code]::Ldc_I4_1 -or $ldc3.OpCode.Code -ne [Mono.Cecil.Cil.Code]::Ldc_I4_3) { throw 'PatchE: layout unexpected' }
$E1 = New-InsStr ([Mono.Cecil.Cil.OpCodes]::Ldstr) 'UiHiddenPageDownload'
$E2 = New-Ins ([Mono.Cecil.Cil.OpCodes]::Ldnull)
$E3 = New-InsRef ([Mono.Cecil.Cil.OpCodes]::Call) $settingsGet
$E4 = New-InsTarget ([Mono.Cecil.Cil.OpCodes]::Brfalse_S) $null
$E5 = New-InsRef ([Mono.Cecil.Cil.OpCodes]::Call) $hiddenForceShow
$E6 = New-InsTarget ([Mono.Cecil.Cil.OpCodes]::Brtrue_S) $null
$E7 = New-Ins ([Mono.Cecil.Cil.OpCodes]::Ldc_I4_1)
$E8 = New-InsRef ([Mono.Cecil.Cil.OpCodes]::Stloc) $bodyE.Variables[0]
$E9 = New-InsTarget ([Mono.Cecil.Cil.OpCodes]::Br_S) $afterE
$E10 = New-Ins ([Mono.Cecil.Cil.OpCodes]::Ldc_I4_2)
$E11 = New-InsRef ([Mono.Cecil.Cil.OpCodes]::Stloc) $bodyE.Variables[0]
$E12 = New-InsTarget ([Mono.Cecil.Cil.OpCodes]::Br_S) $afterE
$E13 = New-Ins ([Mono.Cecil.Cil.OpCodes]::Ldc_I4_3)
$E14 = New-InsRef ([Mono.Cecil.Cil.OpCodes]::Stloc) $bodyE.Variables[0]
$E4.Operand = [Mono.Cecil.Cil.Instruction]$E10
$E6.Operand = [Mono.Cecil.Cil.Instruction]$E10
$brtrueIns.Operand = [Mono.Cecil.Cil.Instruction]$E13
$ilE.Remove($stloc0b); $ilE.Remove($ldc3); $ilE.Remove($brShort); $ilE.Remove($stloc0); $ilE.Remove($ldc1)
foreach ($x in @($E1,$E2,$E3,$E4,$E5,$E6,$E7,$E8,$E9,$E10,$E11,$E12,$E13,$E14)) { $ilE.InsertBefore($afterE, [Mono.Cecil.Cil.Instruction]$x) }
Write-Output 'Patch E done'

# Patch F
$mF = (Get-Type 'PCL.PageResource').Methods | Where-Object { $_.Name -eq 'set_PageType' }
$bodyF = $mF.Body
$ilF = $bodyF.GetILProcessor()
$instrsF = @($bodyF.Instructions)
$getBtn = $null
foreach ($ins in $instrsF) {
    if ($ins.OpCode.Code -eq [Mono.Cecil.Cil.Code]::Callvirt -and $ins.Operand -is [Mono.Cecil.MethodReference] -and $ins.Operand.Name -eq 'get_BtnSearchInstallModPack') { $getBtn = $ins; break }
}
if ($null -eq $getBtn) { throw 'PatchF: get button not found' }
$setVisF = $null
$cur = $getBtn.Next
while ($null -ne $cur) { if ($cur.OpCode.Code -eq [Mono.Cecil.Cil.Code]::Callvirt -and $cur.Operand -is [Mono.Cecil.MethodReference] -and $cur.Operand.Name -eq 'set_Visibility') { $setVisF = $cur; break }; $cur = $cur.Next }
if ($null -eq $setVisF) { throw 'PatchF: set_Visibility not found' }
$cur = $getBtn.Next
$ldarg1F = $null
while ($cur -ne $setVisF) { if ($cur.OpCode.Code -eq [Mono.Cecil.Cil.Code]::Ldarg_1) { $ldarg1F = $cur; break }; $cur = $cur.Next }
if ($null -eq $ldarg1F) { throw 'PatchF: ldarg.1 not found' }
$cur = $ldarg1F
while ($cur -ne $setVisF) { $nxt = $cur.Next; $ilF.Remove($cur); $cur = $nxt }
$F1 = New-Ins ([Mono.Cecil.Cil.OpCodes]::Ldarg_1)
$F2 = New-Ins ([Mono.Cecil.Cil.OpCodes]::Ldc_I4_2)
$F3 = New-InsTarget ([Mono.Cecil.Cil.OpCodes]::Beq_S) $null
$F4 = New-Ins ([Mono.Cecil.Cil.OpCodes]::Ldc_I4_2)
$F5 = New-InsTarget ([Mono.Cecil.Cil.OpCodes]::Br_S) $setVisF
$F6 = New-Ins ([Mono.Cecil.Cil.OpCodes]::Ldc_I4_0)
$F3.Operand = [Mono.Cecil.Cil.Instruction]$F6
foreach ($x in @($F1,$F2,$F3,$F4,$F5,$F6)) { $ilF.InsertBefore($setVisF, [Mono.Cecil.Cil.Instruction]$x) }
Write-Output 'Patch F done'

# Patch G
$mG = Get-Method 'PCL.PageInstanceModDisabled' 'BtnDownload_Loaded' 0
$bodyG = $mG.Body
$ilG = $bodyG.GetILProcessor()
$instrsG = @($bodyG.Instructions)
if ($instrsG[0].OpCode.Code -ne [Mono.Cecil.Cil.Code]::Ldc_I4_2 -or $instrsG[1].OpCode.Code -ne [Mono.Cecil.Cil.Code]::Stloc_0) { throw 'PatchG: layout unexpected' }
$frmSelectRight = (Get-Type 'PCL.ModMain').Fields | Where-Object { $_.Name -eq 'FrmSelectRight' }
$showHidden = (Get-Type 'PCL.PageSelectRight').Fields | Where-Object { $_.Name -eq 'ShowHidden' }
if ($null -eq $frmSelectRight -or $null -eq $showHidden) { throw 'PatchG: fields missing' }
$afterG = $instrsG[2]
$ilG.Remove($instrsG[1]); $ilG.Remove($instrsG[0])
$G1 = New-InsStr ([Mono.Cecil.Cil.OpCodes]::Ldstr) 'UiHiddenPageDownload'
$G2 = New-Ins ([Mono.Cecil.Cil.OpCodes]::Ldnull)
$G3 = New-InsRef ([Mono.Cecil.Cil.OpCodes]::Call) $settingsGet
$G4 = New-InsTarget ([Mono.Cecil.Cil.OpCodes]::Brfalse_S) $null
$G5 = New-InsRef ([Mono.Cecil.Cil.OpCodes]::Call) $hiddenForceShow
$G6 = New-InsTarget ([Mono.Cecil.Cil.OpCodes]::Brfalse_S) $null
$G7 = New-InsRef ([Mono.Cecil.Cil.OpCodes]::Ldsfld) $frmSelectRight
$G8 = New-InsTarget ([Mono.Cecil.Cil.OpCodes]::Brfalse_S) $null
$G9 = New-InsRef ([Mono.Cecil.Cil.OpCodes]::Ldsfld) $frmSelectRight
$G10 = New-InsRef ([Mono.Cecil.Cil.OpCodes]::Ldfld) $showHidden
$G11 = New-InsTarget ([Mono.Cecil.Cil.OpCodes]::Br_S) $null
$G12 = New-Ins ([Mono.Cecil.Cil.OpCodes]::Ldc_I4_0)
$G13 = New-InsTarget ([Mono.Cecil.Cil.OpCodes]::Brtrue_S) $null
$G14 = New-Ins ([Mono.Cecil.Cil.OpCodes]::Ldc_I4_0)
$G15 = New-InsTarget ([Mono.Cecil.Cil.OpCodes]::Br_S) $null
$G16 = New-Ins ([Mono.Cecil.Cil.OpCodes]::Ldc_I4_2)
$G17 = New-InsRef ([Mono.Cecil.Cil.OpCodes]::Stloc) $bodyG.Variables[0]
$G4.Operand = [Mono.Cecil.Cil.Instruction]$G7
$G6.Operand = [Mono.Cecil.Cil.Instruction]$G16
$G8.Operand = [Mono.Cecil.Cil.Instruction]$G12
$G11.Operand = [Mono.Cecil.Cil.Instruction]$G13
$G13.Operand = [Mono.Cecil.Cil.Instruction]$G16
$G15.Operand = [Mono.Cecil.Cil.Instruction]$G17
foreach ($x in @($G1,$G2,$G3,$G4,$G5,$G6,$G7,$G8,$G9,$G10,$G11,$G12,$G13,$G14,$G15,$G16,$G17)) { $ilG.InsertBefore($afterG, [Mono.Cecil.Cil.Instruction]$x) }
Write-Output 'Patch G done'

# Patch H: PageSelectRight.McInstanceListUI 空版本列表的“下载游戏”按钮
$mH = Get-Method 'PCL.PageSelectRight' 'McInstanceListUI' 1
$bodyH = $mH.Body
$ilH = $bodyH.GetILProcessor()
$occ = @()
foreach ($ins in $bodyH.Instructions) {
    if ($ins.OpCode.Code -eq [Mono.Cecil.Cil.Code]::Callvirt -and $ins.Operand -is [Mono.Cecil.MethodReference] -and $ins.Operand.Name -eq 'get_BtnEmptyDownload') { $occ += $ins }
}
if ($occ.Count -ne 2) { throw ('PatchH: expected 2 occurrences, got ' + $occ.Count) }
$ldc2 = $occ[1].Next
if ($ldc2.OpCode.Code -ne [Mono.Cecil.Cil.Code]::Ldc_I4_2) { throw 'PatchH: layout unexpected' }
$ilH.Replace($ldc2, (New-Ins ([Mono.Cecil.Cil.OpCodes]::Ldc_I4_0)))
Write-Output 'Patch H done (empty-state download button visible)'

$asm.Write($OutputExe)
if (Test-Path -LiteralPath $resDir) { Remove-Item -LiteralPath $resDir -Recurse -Force -ErrorAction SilentlyContinue }
Write-Output ('WROTE ' + $OutputExe + ' size=' + (Get-Item $OutputExe).Length)
