# just for test
function Get-SpaceCount
{
  param(
    [string]$help_string
  )

  $lines = $help_string -split "`n"
  foreach ($l in $lines)
  {
    $count = 0
    foreach ($c in ([string]$l).ToCharArray())
    {
      if(' ' -eq $c)
      {
        $count += 1
      } else
      {
        break
      }
    }
    "(count=$count) $l`n"
  }
}

function Get-TokensWithoutWordToComplete
{
  param(
    [Parameter(Mandatory)]
    [string]$AstString,

    [Parameter()]
    [string]$WordToComplete,

    [Parameter(Mandatory)]
    [int]$CursorPos

  )
  
  $len = [System.Math]::Min($CursorPos, $AstString.Length)
  $tokens = $AstString.Substring(0,$len).Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries)

  # 当 $wordToCmp 不为空的时，tokens 的最后一个就是 $wordToCmp, 我们需要去除它
  if($null -ne $WordToComplete -and $WordToComplete -ne "")
  {
    $tokens = $tokens[0..($tokens.Count-2)]
  }

  return $tokens
}

function ConvertTo-CompletionResult
{
  param(
    [Parameter()]
    [hashtable]$Source=[hashtable]::new(),

    [Parameter()]
    [string]$Filter=""
  )

  $r = $Source.GetEnumerator() 
  | Where-Object { $_.Name -like "${Filter}*" } 
  | Sort-Object {$_.Name} 
  | ForEach-Object {
    [System.Management.Automation.CompletionResult]::new(
      "$($_.Name)",
      "$($_.Name)",
      'ParameterValue',
      "$($_.Value)"
    )
  }
  return @() + $r
}

function Get-Options
{
  [OutputType([system.collections.hashtable])]
  param(
    [Parameter(Mandatory)]
    [string]$HelpString,

    [Parameter(Mandatory)]
    [string[]]$OptionLinePattern,
    
    [Parameter()]
    [string[]]$DescriptionLinePattern = @()
  )

  $lines = $HelpString -split "`n"

  $options = [hashtable]::new()

  $last_option_name = ""

  $ors = $OptionLinePattern | ForEach-Object { [regex]::new($_) }
  $drs = $DescriptionLinePattern | ForEach-Object { [regex]::new($_) }

  foreach ($l in $lines)
  {
    if ($l.Length -lt 1)
    {
      continue
    }
    $found = $false
    foreach ($or in $ors)
    {
      if($or.IsMatch($l))
      {
        $ms = $or.Matches($l)
        if($ms.Count -gt 0)
        {
          $m = $ms[0]
          $option_name = $m.Groups[1].Value
          $option_partial_description = $m.Groups[0].Value.Trim()
          $options["$option_name"]=$option_partial_description
    
          $last_option_name = $option_name
        }
        $found = $true
        break 
      } 
    }
    if($found)
    {
      continue
    }
    # 处理多行描述
    foreach($dr in $drs)
    {
      if($dr.IsMatch($l))
      {
        if($last_option_name -ne "")
        {
          $options["$last_option_name"]="$($options["$last_option_name"])`n$l"
        }
        break
      }
    }
  }
  
  $options
}



# ------ Rust --------------------------

function Enable-RustupCompleter
{
  Invoke-Expression (&rustup completions powershell | Out-String) -ErrorAction Continue
}

function Get-CargoCommands
{
  param(
  )

  $help_string = cargo --list | Out-String
  Get-Options -HelpString $help_string `
    -OptionLinePattern "^\s{4}([\w\-\?@]+).+$" `
    -DescriptionLinePattern "^\s{0}.+$"
}


function Get-CargoOptions
{
  param(
    [Parameter()]
    [ArgumentCompleter(
      {
        param ( $commandName,
          $parameterName,
          $wordToComplete,
          $commandAst,
          $fakeBoundParameters )
        return ConvertTo-CompletionResult -Source (Get-CargoCommands) -Filter $wordToComplete
      }
    )]
    [string]$Command
  )
 
  # 子命令 options
  if($null -ne $Command -and $Command -ne "")
  {
    $help_string = cargo help $Command | Out-String
    Get-Options -HelpString $help_string `
      -OptionLinePattern "^\s+?(\-[\w\-\?@]+).+$" `
      -DescriptionLinePattern "^\s{11}.+$"
  }
  # cargo options
  else
  {
    $help_string = cargo --help | Out-String
    Get-Options -HelpString $help_string `
      -OptionLinePattern "^\s{2}(\-[\w\-\?@]+).+$", "^\s{6}(\-[\w\-\?@]+).+$" `
      -DescriptionLinePattern "^\s{0}.+$"
  }
}

Register-ArgumentCompleter -Native -CommandName "cargo" -ScriptBlock {
  param($wordToCmp, $ast, $cursorPos)

  # 从 tokens 中 find <command>
  $tokens = Get-TokensWithoutWordToComplete -AstString "$ast" -WordToComplete $wordToCmp -CursorPos $cursorPos

  # --target
  $last_token = $tokens[($tokens.Count - 1)]
  if($last_token -eq "--target")
  {
    $filter = $wordToCmp
    $r = rustc --print target-list 
    | Where-Object { $_.StartsWith("$filter") }
    | Sort-Object $_
    return @() + $r
  }

  $commands = Get-CargoCommands
  foreach ($t in $tokens)
  {
    if($commands.ContainsKey($t))
    {
      $command = $t
      break
    }
  }
  
  # cargo <command>
  if($null -ne $command -and $command -ne "")
  {
    # 1. -<option>
    if ($wordToCmp.StartsWith('-'))
    {
      return ConvertTo-CompletionResult -Source (Get-CargoOptions -Command $command) -Filter $wordToCmp
    }
    
    # 2. command 是 help, 补全 command
    if($command -eq "help")
    {
      # command
      return ConvertTo-CompletionResult -Source ($commands) -Filter $wordToCmp
    }
  }
  # cargo
  else
  {
    # 1. -<option>
    if ($wordToCmp.StartsWith('-'))
    {
      return ConvertTo-CompletionResult -Source (Get-CargoOptions) -Filter $wordToCmp
    }
    # 2. command
    else
    {
      # command
      return ConvertTo-CompletionResult -Source ($commands) -Filter $wordToCmp
    }
  }
}



# ------ java/javac --------------------


function Get-JavaOptions
{
  param(

  )

  $help_string = java -h 2>&1 | Out-String
  Get-Options -HelpString $help_string `
    -OptionLinePattern "^\s{4}(\-[\w\-\?@]+).+$" `
    -DescriptionLinePattern "^\s{18}.+"
}


function Get-JavaXOptions
{
  param(

  )

  $help_string = java -X 2>&1 | Out-String
  Get-Options -HelpString $help_string `
    -OptionLinePattern "^\s{4}(\-[\w\-\?@]+).+$" `
    -DescriptionLinePattern "^\s{22}.+$"
}

function Get-JavacOptions
{
  param(

  )

  $help_string = javac --help 2>&1 | Out-String
  $r = Get-Options -HelpString $help_string `
    -OptionLinePattern "^\s{2}(\-[\w\-\?@:]+).+$" `
    -DescriptionLinePattern "^\s{8}.+$"

  $help_string = javac -X 2>&1 | Out-String
  $r2 = Get-Options -HelpString $help_string `
    -OptionLinePattern "^\s{2}(\-[\w\-\?@:]+).+$" `
    -DescriptionLinePattern "^\s{8}.+$"
  
  return $r + $r2
}


Register-ArgumentCompleter -Native -CommandName "java" -ScriptBlock {
  param($wordToCmp, $ast, $cursorPos)
  # 1. -X<option>
  if ($wordToCmp.StartsWith('-X'))
  {
    return ConvertTo-CompletionResult -Source (Get-JavaXOptions) -Filter $wordToCmp
  }

  # 2. -<option>
  if($wordToCmp.StartsWith('-'))
  {
    $opts = [hashtable]::new()
    (Get-JavaOptions).GetEnumerator() | ForEach-Object { $opts.Add($_.Name,$_.Value) }
    (Get-JavaXOptions).GetEnumerator() | Where-Object { -not $_.Name.StartsWith('-X') } | ForEach-Object { $opts.Add($_.Name,$_.Value) }
    return ConvertTo-CompletionResult -Source ($opts) -Filter $wordToCmp
  }
}

Register-ArgumentCompleter -Native -CommandName "javac" -ScriptBlock {
  param($wordToCmp, $ast, $cursorPos)

  # 1. -<option>
  if($wordToCmp.StartsWith('-'))
  {
    return ConvertTo-CompletionResult -Source (Get-JavacOptions) -Filter $wordToCmp
  }

}

# ------ Gradle ------------------------

function Format-GradleProjectName
{
  param (
    [Parameter()]
    [string]$Name = ''
  )

  $Name.StartsWith(":") ? $Name : ":$Name"
}


function Get-GradleProjectsName
{
  param (
    [Parameter()]
    [string]$ParentProjectName = ''
  )

  $parent_project_name = Format-GradleProjectName -Name $ParentProjectName
  $filter = $parent_project_name.EndsWith(':') ? $parent_project_name  : "${parent_project_name}:"
  
  # 读取 settings.gradle 解析获取全部 projects name
  $content = Get-Content './settings.gradle'
  $r = [regex]::new("include\s+(['`"])(\S+?)\1")
  $all_projects_name = $r.Matches($content) 
  | ForEach-Object { Format-GradleProjectName -Name $_.Groups[2].Value }
  | Sort-Object -Unique

  # 过滤出子 project
  $all_projects_name
  | Where-Object { $_.Length -gt $filter.Length -and $_.StartsWith($filter) } 
  | ForEach-Object { ($_.Substring($filter.Length).Split(':'))[0] } 
  | Sort-Object -Unique
}

function Get-GradleTasks
{
  param(
    [Parameter()]
    [string]$ProjectName = ''
  )

  # :app -> app
  $project_name = $ProjectName.StartsWith(":") ? $ProjectName.Substring(1) : $ProjectName
  
  # ./.gradle-tasks-cache 缓存 gralew tasks --all 输出
  $str = Get-Content -Path "./.gradle-tasks-cache" -Raw
  if($null -eq $str -or "" -eq $str)
  {
    # $str = ./gradlew "${project_name}:tasks" | Out-String
    
    $str = ./gradlew tasks --all | Out-String
    Set-Content -Path "./.gradle-tasks-cache" -Value $str 
  }

  # 正则：从 gradlew tasks --all 输出中解析出 tasks [(@{Group,Name,Description})]
  $p = "(\w[^\r\n]+?)\r?\n\-+?\r?\n(([^\r\n]+\r?\n)+?)\r?\n"
  $r = [regex]::new($p)

  $ms = $r.Matches($str)

  foreach ($m in $ms)
  {
    $g = $m.Groups[1].Value
    if($g -eq "Rules")
    {
      continue
    }

    $v = $m.Groups[2].Value.Trim()
    $line = $v.Split("`r`n")
    foreach ($l in $line)
    {
      $t = $l.Split(" - ", 2)
      $t_name = $t[0]
      # root project
      if($project_name -eq '')
      {
        # root project task name not contains ":"
        if(-not $t_name.Contains(":"))
        {
          [pscustomobject]@{
            Group = $g
            Name = $t_name
            Description = $t[1]
          }
        }
      }
      # not root project
      else
      {
        # project name is the prefix of task name
        $len = $t_name.LastIndexOf(":")  
        if($len -gt 0 -and $t_name.Substring(0,$len) -eq $project_name)
        {
          [pscustomobject]@{
            Group = $g
            Name = $t_name.Substring($len+1)
            Description = $t[1]
          }
        }
      }
    }
  }
}

function Get-GradleOptions
{

  param(
  )

  $help_string = ./gradlew -X 2>&1 | Out-String
  Get-Options -HelpString $help_string `
    -OptionLinePattern "^\s{0}(\-[\w\-\?@:]+).+$" `
    -DescriptionLinePattern "^\s{0}.+$"
}

Register-ArgumentCompleter -Native -CommandName "gradlew" -ScriptBlock {
  param($wordToCmp, $ast, $cursorPos)

  $tokens = -split $ast
  $tokens_count = $tokens.Count

  # 1. 只有 .\gradle 一个 token 时
  if ($tokens_count -eq 1 -and $wordToCmp -eq '')
  {
    return @(
      [System.Management.Automation.CompletionResult]::new(':', ':<task>', 'ParameterValue', ':<task>')
      [System.Management.Automation.CompletionResult]::new('-', '-<option>', 'ParameterValue', '-<option>')
    )
  }

  # 2. -<option>
  if ($wordToCmp.StartsWith('-'))
  {
    return ConvertTo-CompletionResult -Source (Get-GradleOptions) -Filter $wordToCmp
  }
  # 3. :<task>
  if ($wordToCmp.StartsWith(':'))
  {
    $index = $wordToCmp.LastIndexOf(':')
    $parent_project_name = $wordToCmp.Substring(0, $index)
    $filter = $wordToCmp.Substring($index + 1)
    $prefix = $parent_project_name + ":"

    # task 
    $r = Get-GradleTasks -ProjectName "$parent_project_name"
    | Where-Object { $_.Name -Like "${filter}*" } 
    | ForEach-Object { 
      [System.Management.Automation.CompletionResult]::new(
        "${prefix}$($_.Name)", 
        "$($_.Name) ($($_.Group))", 
        'ParameterValue',
        "`"$($_.Description)`""
      )
    }

    # project path
    $r2 = Get-GradleProjectsName -ParentProjectName "$parent_project_name"
    | Where-Object { $_ -Like "${filter}*" } 
    | ForEach-Object { 
      [System.Management.Automation.CompletionResult]::new(
        "${prefix}$_", 
        "$_ (project)", 
        'ParameterValue',
        "$_" 
      ) 
    }

    return @() + $r + $r2
  }
  
}




# ------ Julia -------------------------

function Get-JuliaOptions
{
  param(

  )

  $help_string = julia -h 2>&1 | Out-String

  Get-Options -HelpString $help_string `
    -OptionLinePattern "^\s{1}(\-[\w\-\?@]+).+$" `
    -DescriptionLinePattern "^\s{28}.+$"

}

Register-ArgumentCompleter -Native -CommandName "julia" -ScriptBlock {
  param($wordToCmp, $ast, $cursorPos)

  # 1. -<option>
  if($wordToCmp.StartsWith('-'))
  {
    return ConvertTo-CompletionResult -Source (Get-JuliaOptions) -Filter $wordToCmp
  }
}


# ------ nimble ------------------------

function Get-NimbleOptions
{
  param(

  )

  $help_string = nimble --help | Out-String
  Get-Options -HelpString $help_string `
    -OptionLinePattern "^\s{2}(\-[\w\-\?@]+).+$", "^\s{6}(\-[\w\-\?@]+).+$" `
    -DescriptionLinePattern "^\s{34}.+$"
}

function Get-NimbleCommands
{
  param(

  )

  $help_string = nimble --help | Out-String
  $help_string = [regex]::new("Commands:([\s\S]+)Nimble Options:").Matches($help_string)[0].Groups[1].Value
  Get-Options -HelpString $help_string `
    -OptionLinePattern "^\s{2}(\w[\w\-\?@]*).+$" `
    -DescriptionLinePattern "^\s{34}.+$", "^\s{15}.+$"
}

function Get-NimbleTasks 
{
  param(
    
  )

  $help_string = nimble tasks | Out-String

  $r = [hashtable]::new()

  if($help_string.Contains("Error"))
  {
    return $r 
  }

  foreach($l in $help_string.split("`n"))
  {
    if($l.Length -le 0)
    {
      continue
    }
    $split = $l.Split(" ", 2)
    $name = $split[0]
    $description = $split[1].Trim()
    $r["$name"] = $description
  }

  return $r
}


Register-ArgumentCompleter -Native -CommandName "nimble" -ScriptBlock {
  param($wordToCmp, $ast, $cursorPos)

  # 从 tokens 中 find <command>
  $tokens = Get-TokensWithoutWordToComplete -AstString "$ast" -WordToComplete $wordToCmp -CursorPos $cursorPos
  $commands = Get-NimbleCommands
  foreach ($t in $tokens)
  {
    if($commands.ContainsKey($t))
    {
      $command = $t
      break
    }
  }
  
  # nimble <command>
  if($null -ne $command -and $command -ne "")
  {
    # TODO: command option
  }
  # nimble
  else
  {
    # 1. -<option>
    if ($wordToCmp.StartsWith('-'))
    {
      return ConvertTo-CompletionResult -Source (Get-NimbleOptions) -Filter $wordToCmp
    }
    # 2. command
    else
    {
      # task
      $filter = $wordToCmp
      $r = (Get-NimbleTasks).GetEnumerator() 
      | Where-Object { $_.Name -like "${filter}*" } 
      | Sort-Object {$_.Name} 
      | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new(
          "$($_.Name)",
          "$($_.Name) (task)",
          'ParameterValue',
          "$($_.Value)"
        )
      }

      # command
      $r2 = ConvertTo-CompletionResult -Source ($commands) -Filter $wordToCmp

      return @() + $r + $r2
    }
  }
}

# ------ zig ---------------------------

function Get-ZigCommands
{
  param(
    
  )

  $help_string = zig help | Out-String
  Get-Options -HelpString $help_string `
    -OptionLinePattern "^\s{2}(\w[\w\-\?@]+).+$" `

}

function Get-ZigOptions
{
  param(
    [Parameter()]
    [ArgumentCompleter(
      {
        param ( $commandName,
          $parameterName,
          $wordToComplete,
          $commandAst,
          $fakeBoundParameters )
        return ConvertTo-CompletionResult -Source (Get-ZigCommands) -Filter $wordToCmp
      }
    )]
    [string]$Command
  )
    
  # zig <command> options
  if($null -ne $Command -and $Command -ne "")
  {
    $help_string = zig "$Command" --help | Out-String
    Get-Options -HelpString $help_string `
      -OptionLinePattern "^\s{2}(\-[\w\-\?@]+).+$" `
      -DescriptionLinePattern "^\s{3,}.+$"
  } 
  # zig options
  else
  {
    $help_string = zig help | Out-String
    Get-Options -HelpString $help_string `
      -OptionLinePattern "^\s{2}(\-[\w\-\?@]+).+$" `
      -DescriptionLinePattern "^\s{3,}.+$"
  }
}

function Get-ZigTargets 
{
  param(

  )
  (zig targets | ConvertFrom-Json).libc
}

Register-ArgumentCompleter -Native -CommandName "zig" -ScriptBlock {
  param($wordToCmp, $ast, $cursorPos)

  # 从 tokens 中 find <command>
  $tokens = Get-TokensWithoutWordToComplete -AstString "$ast" -WordToComplete $wordToCmp -CursorPos $cursorPos

  $last_token = $tokens[($tokens.Count-1)]
  if($last_token -eq "-target")
  {
    $filter = $wordToCmp
    $r = Get-ZigTargets
    | Where-Object { $_ -like "$filter*" }
    | Sort-Object $_
    return @() + $r
  }
  
  $commands = Get-ZigCommands

  foreach ($t in $tokens)
  {
    if($commands.ContainsKey($t))
    {
      $command = $t
      break
    }
  }
  
  # zig <command>
  if($null -ne $command -and $command -ne "")
  {
    # option
    if($wordToCmp.StartsWith("-"))
    {
      return ConvertTo-CompletionResult -Source (Get-ZigOptions -Command $command) -Filter $wordToCmp
    }
  }
  # zig
  else
  {
    # option
    if($wordToCmp.StartsWith("-"))
    {
      return ConvertTo-CompletionResult -Source (Get-ZigOptions) -Filter $wordToCmp
    }
    # command
    else
    {
      return ConvertTo-CompletionResult -Source ($commands) -Filter $wordToCmp
    }
  }
}

# ------ Crystal -----------------------

function CrystalCommandArgumentCompleter
{
  param ( $commandName,
    $parameterName,
    $wordToComplete,
    $commandAst,
    $fakeBoundParameters )

  $tokens = @() + $fakeBoundParameters["Commands"]
  if($tokens.Count -gt 1)
  {
    $commands = @() + $tokens[0..($tokens.Count-2)] 
    $filter = $tokens[($tokens.Count-1)]
  } else
  {
    $commands = @()
    $filter = $tokens[0] 
  }

  return ConvertTo-CompletionResult -Source (Get-CrystalCommands -Commands $commands) -Filter $filter
}

function Get-CrystalCommands
{
  param(
    [Parameter()]
    [ArgumentCompleter({ CrystalCommandArgumentCompleter @args })]
    [string[]]$Commands=@()
  )

  $help_string = & "crystal" $Commands "--help" | Out-String
  $r = Get-Options -HelpString $help_string `
    -OptionLinePattern "^\s{4}(\w[\w\-\?@]+).+$"
  $r.Remove("crystal")
  return $r
}

function Get-CrystalOptions
{
  param(
    [Parameter()]
    [ArgumentCompleter({ CrystalCommmndArgumentCompleter @args })]
    [string[]]$Commands=@()
  )

  $help_string = & "crystal" $Commands "--help" | Out-String
  Get-Options -HelpString $help_string `
    -OptionLinePattern "^\s{4}(\-[\w\-\?@]+).+$"
}

Register-ArgumentCompleter -Native -CommandName "crystal" -ScriptBlock {
  param($wordToCmp, $ast, $cursorPos)

  # 从 tokens 中 find commands
  $tokens = Get-TokensWithoutWordToComplete -AstString "$ast" -WordToComplete $wordToCmp -CursorPos $cursorPos
  $commands = @()
  $tmp = Get-CrystalCommands
  foreach ($token in $tokens)
  {
    if($tmp.ContainsKey($token))
    {
      $commands += $token
      $tmp = Get-CrystalCommands -Commands $commands
    }
  }

  # complete option
  if($wordToCmp.StartsWith("-"))
  {
    return ConvertTo-CompletionResult -Source (Get-CrystalOptions -Commands $commands) -Filter $wordToCmp
  }
  # complete command
  else
  {
    return ConvertTo-CompletionResult -Source ($tmp) -Filter $wordToCmp
  }
}
