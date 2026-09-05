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
[assembly: AssemblyVersion("3.0.1.0")]
[assembly: AssemblyFileVersion("3.0.1.0")]

namespace OneClickDLSS5
{
    static class Program
    {
        [STAThread]
        static int Main(string[] args)
        {

            string baseDir = AppDomain.CurrentDomain.BaseDirectory;
            string scriptPath = Path.Combine(baseDir, @"core\1-Click-DLSS5.ps1");
            bool isPt = System.Globalization.CultureInfo.CurrentUICulture.TwoLetterISOLanguageName.Equals("pt", StringComparison.OrdinalIgnoreCase);

            if (!File.Exists(scriptPath))
            {
                string altScript = Path.Combine(baseDir, "1-Click-DLSS5.ps1");
                if (File.Exists(altScript))
                {
                    scriptPath = altScript;
                }
                else
                {
                    string notFoundMsg = isPt 
                        ? "Não foi possível localizar o script principal do 1 Click DLSS 5 em:\n" + scriptPath 
                        : "Could not locate the main 1 Click DLSS 5 script at:\n" + scriptPath;
                    string notFoundTitle = isPt ? "1 Click DLSS 5 - Arquivo Não Encontrado" : "1 Click DLSS 5 - Script Not Found";
                    MessageBox.Show(
                        notFoundMsg,
                        notFoundTitle,
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Error);
                    return 1;
                }
            }

            // Seleciona o interpretador PowerShell mais recente disponível
            string psExe = "powershell.exe";
            string[] pwshCandidates = new string[]
            {
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), @"PowerShell\7\pwsh.exe"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Microsoft\PowerShell\7\pwsh.exe"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), @"PowerShell\7\pwsh.exe")
            };
            foreach (string cand in pwshCandidates)
            {
                if (!string.IsNullOrEmpty(cand) && File.Exists(cand))
                {
                    psExe = cand;
                    break;
                }
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
                psi.StandardErrorEncoding = System.Text.Encoding.UTF8;

                using (Process proc = Process.Start(psi))
                {
                    string stderr = proc.StandardError.ReadToEnd();
                    proc.WaitForExit();

                    if (proc.ExitCode != 0 && !string.IsNullOrEmpty(stderr) && !stderr.Contains("OperationCanceledException"))
                    {
                        string errMsg = isPt
                            ? "Ocorreu um erro durante a inicialização do 1 Click DLSS 5:\n\n" + stderr
                            : "An error occurred during 1 Click DLSS 5 startup:\n\n" + stderr;
                        string errTitle = isPt ? "1 Click DLSS 5 - Erro" : "1 Click DLSS 5 - Error";
                        MessageBox.Show(
                            errMsg,
                            errTitle,
                            MessageBoxButtons.OK,
                            MessageBoxIcon.Warning);
                    }
                    return proc.ExitCode;
                }
            }
            catch (Exception ex)
            {
                string failMsg = isPt
                    ? "Falha ao iniciar o 1 Click DLSS 5:\n\n" + ex.Message
                    : "Failed to launch 1 Click DLSS 5:\n\n" + ex.Message;
                string failTitle = isPt ? "1 Click DLSS 5 - Falha Crítica" : "1 Click DLSS 5 - Launch Failure";
                MessageBox.Show(
                    failMsg,
                    failTitle,
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
                return 1;
            }
        }
    }
}
