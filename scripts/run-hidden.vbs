' Runs a command with no window at all, for Scheduled Tasks.
'
' With Windows Terminal as the default terminal (Windows 11), a task that runs a console
' program (powershell.exe -WindowStyle Hidden, py.exe, ...) still opens a visible
' terminal tab: the console is created first and only then hidden, which the terminal
' ignores. wscript.exe has no console, and Run(..., 0) starts the child hidden from the
' first instant.
'
' Usage: wscript.exe //B //Nologo run-hidden.vbs <program> [arguments...]
' Arguments with spaces are passed quoted; the program's exit code is returned.
Option Explicit
Dim shell, i, cmd, arg
If WScript.Arguments.Count < 1 Then WScript.Quit 2
cmd = ""
For i = 0 To WScript.Arguments.Count - 1
    arg = WScript.Arguments(i)
    ' Only what needs it is quoted: some programs (py.exe) parse the raw command line and
    ' do not accept a quoted switch such as "-3".
    If InStr(arg, " ") > 0 Or InStr(arg, """") > 0 Or arg = "" Then arg = """" & Replace(arg, """", """""") & """"
    cmd = cmd & " " & arg
Next
Set shell = CreateObject("WScript.Shell")
WScript.Quit shell.Run(Trim(cmd), 0, True)
