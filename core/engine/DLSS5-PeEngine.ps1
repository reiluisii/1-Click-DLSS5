# ==============================================================================
# 1 Click DLSS 5 — Neural PE Analysis & Binary Inspection Engine
# ==============================================================================

try {
    if (-not ([System.Management.Automation.PSTypeName]'DLSS5PeEngine').Type) {
        Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Text;
using System.Collections.Generic;

public static class DLSS5PeEngine {
    public static string GetArchitecture(string path) {
        try {
            using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
            using (var br = new BinaryReader(fs)) {
                if (fs.Length < 0x40) return "UNKNOWN";
                if (br.ReadUInt16() != 0x5A4D) return "UNKNOWN";
                fs.Seek(0x3C, SeekOrigin.Begin);
                uint peOffset = br.ReadUInt32();
                if (peOffset + 6 > fs.Length) return "UNKNOWN";
                fs.Seek(peOffset, SeekOrigin.Begin);
                if (br.ReadUInt32() != 0x00004550) return "UNKNOWN";
                ushort machine = br.ReadUInt16();
                if (machine == 0x8664 || machine == 0xAA64) return "X64";
                if (machine == 0x014C) return "X86";
                return "UNKNOWN";
            }
        } catch { return "UNKNOWN"; }
    }

    public static List<string> GetImports(string path) {
        var imports = new List<string>();
        try {
            using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
            using (var br = new BinaryReader(fs)) {
                if (fs.Length < 0x40) return imports;
                if (br.ReadUInt16() != 0x5A4D) return imports;
                fs.Seek(0x3C, SeekOrigin.Begin);
                uint peOffset = br.ReadUInt32();
                if (peOffset + 0x100 > fs.Length) return imports;
                fs.Seek(peOffset, SeekOrigin.Begin);
                if (br.ReadUInt32() != 0x00004550) return imports;
                fs.Seek(peOffset + 0x18, SeekOrigin.Begin);
                ushort magic = br.ReadUInt16();
                bool is64 = (magic == 0x020B);
                uint numRvaAndSizesOffset = peOffset + (is64 ? 0x88u : 0x78u);
                if (numRvaAndSizesOffset + 4 > fs.Length) return imports;
                fs.Seek(numRvaAndSizesOffset, SeekOrigin.Begin);
                uint numRvaAndSizes = br.ReadUInt32();
                if (numRvaAndSizes < 2) return imports;
                uint dataDirsOffset = numRvaAndSizesOffset + 4;
                fs.Seek(dataDirsOffset + 8, SeekOrigin.Begin);
                uint importRva = br.ReadUInt32();
                uint importSize = br.ReadUInt32();
                uint delayRva = 0;
                if (numRvaAndSizes >= 14) {
                    fs.Seek(dataDirsOffset + (13 * 8), SeekOrigin.Begin);
                    delayRva = br.ReadUInt32();
                }

                fs.Seek(peOffset + 0x06, SeekOrigin.Begin);
                ushort numSections = br.ReadUInt16();
                fs.Seek(peOffset + 0x14, SeekOrigin.Begin);
                ushort sizeOfOptHeader = br.ReadUInt16();
                uint sectionTableOffset = peOffset + 0x18 + sizeOfOptHeader;

                var sections = new List<SectionHeader>();
                for (int i = 0; i < numSections; i++) {
                    fs.Seek(sectionTableOffset + (i * 40), SeekOrigin.Begin);
                    byte[] nameBytes = br.ReadBytes(8);
                    fs.Seek(sectionTableOffset + (i * 40) + 8, SeekOrigin.Begin);
                    uint virtSize = br.ReadUInt32();
                    uint virtAddr = br.ReadUInt32();
                    uint rawSize = br.ReadUInt32();
                    uint rawAddr = br.ReadUInt32();
                    sections.Add(new SectionHeader { VirtAddr = virtAddr, VirtSize = virtSize, RawAddr = rawAddr, RawSize = rawSize });
                }

                ReadDescriptorTable(fs, br, sections, importRva, imports, false);
                if (delayRva != 0) {
                    ReadDescriptorTable(fs, br, sections, delayRva, imports, true);
                }
            }
        } catch {}
        return imports;
    }

    private class SectionHeader {
        public uint VirtAddr;
        public uint VirtSize;
        public uint RawAddr;
        public uint RawSize;
    }

    private static uint RvaToFileOffset(List<SectionHeader> sections, uint rva) {
        foreach (var s in sections) {
            if (rva >= s.VirtAddr && rva < s.VirtAddr + Math.Max(s.VirtSize, s.RawSize)) {
                return s.RawAddr + (rva - s.VirtAddr);
            }
        }
        return 0;
    }

    private static void ReadDescriptorTable(FileStream fs, BinaryReader br, List<SectionHeader> sections, uint tableRva, List<string> imports, bool isDelay) {
        if (tableRva == 0) return;
        uint fileOffset = RvaToFileOffset(sections, tableRva);
        if (fileOffset == 0 || fileOffset >= fs.Length) return;

        int descSize = isDelay ? 32 : 20;
        int maxDescriptors = 256;
        for (int i = 0; i < maxDescriptors; i++) {
            uint curOffset = fileOffset + (uint)(i * descSize);
            if (curOffset + descSize > fs.Length) break;
            fs.Seek(curOffset, SeekOrigin.Begin);
            if (!isDelay) {
                uint origFirstThunk = br.ReadUInt32();
                uint timeStamp = br.ReadUInt32();
                uint forwarderChain = br.ReadUInt32();
                uint nameRva = br.ReadUInt32();
                uint firstThunk = br.ReadUInt32();
                if (nameRva == 0 && firstThunk == 0) break;
                uint nameFileOffset = RvaToFileOffset(sections, nameRva);
                if (nameFileOffset != 0 && nameFileOffset < fs.Length) {
                    string name = ReadAsciiString(fs, nameFileOffset);
                    if (!string.IsNullOrEmpty(name) && !imports.Contains(name.ToLowerInvariant())) {
                        imports.Add(name.ToLowerInvariant());
                    }
                }
            } else {
                uint attrs = br.ReadUInt32();
                uint nameRva = br.ReadUInt32();
                uint hmod = br.ReadUInt32();
                uint iatRva = br.ReadUInt32();
                uint intRva = br.ReadUInt32();
                if (nameRva == 0) break;
                uint nameFileOffset = RvaToFileOffset(sections, nameRva);
                if (nameFileOffset != 0 && nameFileOffset < fs.Length) {
                    string name = ReadAsciiString(fs, nameFileOffset);
                    if (!string.IsNullOrEmpty(name) && !imports.Contains(name.ToLowerInvariant())) {
                        imports.Add(name.ToLowerInvariant());
                    }
                }
            }
        }
    }

    private static string ReadAsciiString(FileStream fs, uint offset) {
        fs.Seek(offset, SeekOrigin.Begin);
        var sb = new StringBuilder();
        for (int i = 0; i < 256; i++) {
            int b = fs.ReadByte();
            if (b <= 0) break;
            sb.Append((char)b);
        }
        return sb.ToString();
    }

    public static List<string> FindMarkers(string path, string[] markers) {
        var found = new List<string>();
        if (markers == null || markers.Length == 0 || !File.Exists(path)) return found;

        var markerBytes = new List<KeyValuePair<string, byte[]>>();
        foreach (var m in markers) {
            markerBytes.Add(new KeyValuePair<string, byte[]>(m, Encoding.ASCII.GetBytes(m)));
        }

        try {
            using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite)) {
                long maxScan = Math.Min(fs.Length, 80L * 1024 * 1024);
                int bufferSize = 4 * 1024 * 1024;
                byte[] buffer = new byte[bufferSize];
                long bytesRemaining = maxScan;
                byte[] overlap = new byte[256];
                int overlapLen = 0;

                while (bytesRemaining > 0 && found.Count < markers.Length) {
                    int toRead = (int)Math.Min(bufferSize, bytesRemaining);
                    int read = fs.Read(buffer, 0, toRead);
                    if (read <= 0) break;

                    byte[] scanBlock;
                    if (overlapLen > 0) {
                        scanBlock = new byte[overlapLen + read];
                        Buffer.BlockCopy(overlap, 0, scanBlock, 0, overlapLen);
                        Buffer.BlockCopy(buffer, 0, scanBlock, overlapLen, read);
                    } else {
                        scanBlock = buffer;
                    }

                    int scanLen = (overlapLen > 0) ? (overlapLen + read) : read;
                    for (int m = 0; m < markerBytes.Count; m++) {
                        var kvp = markerBytes[m];
                        if (found.Contains(kvp.Key)) continue;
                        if (BufferContains(scanBlock, scanLen, kvp.Value)) {
                            found.Add(kvp.Key);
                        }
                    }

                    int keep = Math.Min(256, read);
                    Buffer.BlockCopy(buffer, read - keep, overlap, 0, keep);
                    overlapLen = keep;
                    bytesRemaining -= read;
                }
            }
        } catch {}
        return found;
    }

    private static bool BufferContains(byte[] haystack, int haystackLen, byte[] needle) {
        if (needle.Length > haystackLen) return false;
        byte first = needle[0];
        int max = haystackLen - needle.Length;
        for (int i = 0; i <= max; i++) {
            if (haystack[i] == first) {
                bool match = true;
                for (int j = 1; j < needle.Length; j++) {
                    if (haystack[i + j] != needle[j]) { match = false; break; }
                }
                if (match) return true;
            }
        }
        return false;
    }

    public static bool IsAddonReShade(string path) {
        if (!File.Exists(path)) return false;
        try {
            string ver = System.Diagnostics.FileVersionInfo.GetVersionInfo(path).FileDescription ?? "";
            var markers = FindMarkers(path, new string[] { "Searching for add-ons", "ReShade" });
            return markers.Contains("Searching for add-ons") || (ver.IndexOf("ReShade", StringComparison.OrdinalIgnoreCase) >= 0 && markers.Contains("Searching for add-ons"));
        } catch { return false; }
    }

    public static string GetFileVersion(string path) {
        if (!File.Exists(path)) return "";
        try {
            var info = System.Diagnostics.FileVersionInfo.GetVersionInfo(path);
            if (!string.IsNullOrEmpty(info.FileVersion)) return info.FileVersion.Trim();
            if (!string.IsNullOrEmpty(info.ProductVersion)) return info.ProductVersion.Trim();
            return "";
        } catch { return ""; }
    }

    public static int CompareVersions(string v1, string v2) {
        if (string.IsNullOrEmpty(v1) && string.IsNullOrEmpty(v2)) return 0;
        if (string.IsNullOrEmpty(v1)) return -1;
        if (string.IsNullOrEmpty(v2)) return 1;
        try {
            var p1 = ParseVersion(v1);
            var p2 = ParseVersion(v2);
            for (int i = 0; i < Math.Max(p1.Length, p2.Length); i++) {
                int val1 = i < p1.Length ? p1[i] : 0;
                int val2 = i < p2.Length ? p2[i] : 0;
                if (val1 != val2) return val1.CompareTo(val2);
            }
            return 0;
        } catch { return 0; }
    }

    private static int[] ParseVersion(string text) {
        var parts = new List<int>();
        var m = System.Text.RegularExpressions.Regex.Matches(text, @"\d+");
        foreach (System.Text.RegularExpressions.Match match in m) {
            int val;
            if (int.TryParse(match.Value, out val)) parts.Add(val);
        }
        return parts.ToArray();
    }
}
"@
    }
} catch {}

function Get-PeArchitecture {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return "UNKNOWN" }
    return [DLSS5PeEngine]::GetArchitecture($Path)
}

function Test-ValidPe {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $arch = [DLSS5PeEngine]::GetArchitecture($Path)
    return ($arch -eq "X64" -or $arch -eq "X86")
}

function Get-FileVersionString {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [DLSS5PeEngine]::GetFileVersion($Path)
}

function Compare-VersionStrings {
    param([string]$VersionA, [string]$VersionB)
    return [DLSS5PeEngine]::CompareVersions($VersionA, $VersionB)
}
