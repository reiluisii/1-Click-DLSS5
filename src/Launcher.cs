using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Windows.Forms;

[assembly: AssemblyTitle("1 Click DLSS 5")]
[assembly: AssemblyDescription("Universal Neural Control Center • DLSS 5 (DLSS-NR) Installer")]
[assembly: AssemblyConfiguration("")]
[assembly: AssemblyCompany("1 Click DLSS 5 Project")]
[assembly: AssemblyProduct("1 Click DLSS 5")]
[assembly: AssemblyCopyright("Copyright (c) 2026 MIT License")]
[assembly: AssemblyTrademark("DLSS 5 Neural Control Center")]
[assembly: AssemblyVersion("2.5.3.0")]
[assembly: AssemblyFileVersion("2.5.3.0")]

namespace OneClickDLSS5
{
    static class Program
    {
        [DllImport("user32.dll")]
        private static extern bool SetProcessDpiAwarenessContext(int dpiFlag);

        [STAThread]
        static int Main(string[] args)
        {
            try
            {
                SetProcessDpiAwarenessContext(-4); // DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2
            }
            catch { }

            string baseDir = AppDomain.CurrentDomain.BaseDirectory;
            string scriptPath = Path.Combine(baseDir, @"core\1-Click-DLSS5.ps1");

            if (!File.Exists(scriptPath))
            {
                string altScript = Path.Combine(baseDir, "1-Click-DLSS5.ps1");
                if (File.Exists(altScript))
                {
                    scriptPath = altScript;
                }
                else
                {
                    MessageBox.Show(
                        "Could not find the main 1 Click DLSS 5 script at:\n" + scriptPath,
                        "1 Click DLSS 5 - File Not Found",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Error);
                    return 1;
                }
            }

            // Seleciona o interpretador PowerShell mais recente disponível
            string psExe = "powershell.exe";
            string pwsh7 = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), @"PowerShell\7\pwsh.exe");
            if (File.Exists(pwsh7))
            {
                psExe = pwsh7;
            }

            try
            {
                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = psExe;
                psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -STA -File \"" + scriptPath + "\"";
                psi.WorkingDirectory = baseDir;
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                psi.WindowStyle = ProcessWindowStyle.Normal;
                psi.RedirectStandardError = true;

                using (Process proc = Process.Start(psi))
                {
                    string stderr = proc.StandardError.ReadToEnd();
                    proc.WaitForExit();

                    if (proc.ExitCode != 0 && !string.IsNullOrEmpty(stderr) && !stderr.Contains("OperationCanceledException"))
                    {
                        MessageBox.Show(
                            "An error occurred while starting 1 Click DLSS 5:\n\n" + stderr,
                            "1 Click DLSS 5 - Error",
                            MessageBoxButtons.OK,
                            MessageBoxIcon.Warning);
                    }
                    return proc.ExitCode;
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show(
                    "Failed to start 1 Click DLSS 5:\n\n" + ex.Message,
                    "1 Click DLSS 5 - Critical Failure",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
                return 1;
            }
        }
    }
}
