// =============================================================================
//  CrashWatcher.cs — Cool Engine External Crash Reporter  (v4)
// =============================================================================
//
//  What's new in v4
//  ─────────────────
//  • Syntax highlighting in both dialogs.
//      [USER]  frames → bright green   (most important — look here first)
//      [LIB ]  frames → muted grey     (library code — less relevant)
//      [MOD ]  frames → amber          (mod / HScript — may be the culprit)
//      [C++ ]  frames → muted red      (native layer)
//      Error:  line   → red
//      Context line   → gold
//      Section headers (=== / ---) → blue
//      Cause-chain lines  → orange
//      "← likely crash location" → bright red
//  • "Open log file" button — opens the specific .txt in the default viewer.
//  • Dynamic crash type in the header derived from the report contents.
//  • Crash log file path stored and passed to the dialog.
//
//  ARGUMENTS
//  ─────────
//  Crash mode (default):
//    CrashWatcher.exe --pid <pid> --logdir <dir> [--url <url>]
//
//  Warning mode (non-fatal, game still running):
//    CrashWatcher.exe --mode warning --logfile <path>
//
// =============================================================================

using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

[assembly: System.Reflection.AssemblyTitle("Cool Engine Crash Reporter")]
[assembly: System.Reflection.AssemblyVersion("1.0.0.0")]

namespace CoolEngineCrashWatcher
{
    // =========================================================================
    //  Win32 P/Invoke helpers
    // =========================================================================

    static class NativeMethods
    {
        public const uint PROCESS_SYNCHRONIZE               = 0x00100000;
        public const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x00001000;
        public const uint INFINITE                          = 0xFFFFFFFF;

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr OpenProcess(uint access, bool inherit, int pid);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern uint WaitForSingleObject(IntPtr h, uint ms);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool GetExitCodeProcess(IntPtr h, out uint code);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool CloseHandle(IntPtr h);
    }

    // =========================================================================
    //  Entry point
    // =========================================================================

    static class Program
    {
        const int EXIT_CODE_UNKNOWN = int.MinValue;

        [STAThread]
        static void Main(string[] args)
        {
            int    gamePid   = -1;
            string logDir    = "./crash/";
            string reportUrl = "https://github.com/The-Cool-Engine-Crew/FNF-Cool-Engine/issues";
            string mode      = "crash";
            string logFile   = null;

            for (int i = 0; i < args.Length - 1; i++)
            {
                switch (args[i])
                {
                    case "--pid":     int.TryParse(args[i+1], out gamePid); break;
                    case "--logdir":  logDir    = args[i+1]; break;
                    case "--url":     reportUrl = args[i+1]; break;
                    case "--mode":    mode      = args[i+1].ToLowerInvariant(); break;
                    case "--logfile": logFile   = args[i+1]; break;
                }
            }

            // ── Warning mode (non-fatal) ──────────────────────────────────────
            if (mode == "warning")
            {
                string text = ReadFile(logFile);
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.Run(new WarningDialog(text, logFile));
                return;
            }

            // ── Crash mode (default) ──────────────────────────────────────────
            if (gamePid <= 0) return;

            int exitCode = WaitForProcess(gamePid);
            if (exitCode == 0) return;

            Thread.Sleep(1500);

            bool show = (exitCode != EXIT_CODE_UNKNOWN)
                ? true
                : HasRecentLog(logDir, 30);

            if (!show) return;

            string logFilePath;
            string crashText = ReadLatestLog(logDir, exitCode, out logFilePath);

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new CrashDialog(crashText, logDir, reportUrl, exitCode, logFilePath));
        }

        // -------------------------------------------------------------------------

        static int WaitForProcess(int pid)
        {
            IntPtr h = NativeMethods.OpenProcess(
                NativeMethods.PROCESS_SYNCHRONIZE | NativeMethods.PROCESS_QUERY_LIMITED_INFORMATION,
                false, pid);
            if (h == IntPtr.Zero) return EXIT_CODE_UNKNOWN;
            try
            {
                NativeMethods.WaitForSingleObject(h, NativeMethods.INFINITE);
                uint code;
                return NativeMethods.GetExitCodeProcess(h, out code) ? (int)code : EXIT_CODE_UNKNOWN;
            }
            catch { return EXIT_CODE_UNKNOWN; }
            finally { NativeMethods.CloseHandle(h); }
        }

        static bool HasRecentLog(string logDir, double maxAgeSecs)
        {
            try
            {
                if (!Directory.Exists(logDir)) return false;
                var logs = Directory.GetFiles(logDir, "*.txt")
                                    .Select(f => new FileInfo(f))
                                    .OrderByDescending(f => f.LastWriteTime)
                                    .ToArray();
                return logs.Length > 0 &&
                       (DateTime.Now - logs[0].LastWriteTime).TotalSeconds < maxAgeSecs;
            }
            catch { return false; }
        }

        static string ReadLatestLog(string logDir, int exitCode, out string logFilePath)
        {
            logFilePath = null;
            try
            {
                if (Directory.Exists(logDir))
                {
                    var logs = Directory.GetFiles(logDir, "*.txt")
                                        .Select(f => new FileInfo(f))
                                        .OrderByDescending(f => f.LastWriteTime)
                                        .ToArray();
                    if (logs.Length > 0 && (DateTime.Now - logs[0].LastWriteTime).TotalSeconds < 60)
                    {
                        logFilePath = logs[0].FullName;
                        return File.ReadAllText(logs[0].FullName);
                    }
                }
            }
            catch { }

            string code = (exitCode == EXIT_CODE_UNKNOWN)
                ? "unknown (exited before watcher attached)"
                : "0x" + ((uint)exitCode).ToString("X8") + " (" + exitCode + ")";

            return
                "===========================================\n" +
                "       COOL ENGINE — CRASH REPORT\n" +
                "===========================================\n\n" +
                "The game terminated unexpectedly.\n\n" +
                "Exit code : " + code + "\n\n" +
                "No crash log was generated.\n" +
                "This usually means the crash occurred before CrashHandler could write a log,\n" +
                "or the crash log directory is not accessible.\n\n" +
                "Common causes:\n" +
                "  • Native access violation (null pointer at C++ level)\n" +
                "  • Stack overflow with no stack space left to run the handler\n" +
                "  • Process killed externally (task manager, antivirus, etc.)\n\n" +
                "Try running the game from a terminal to see if any output appears before the crash.";
        }

        static string ReadFile(string path)
        {
            try { if (!string.IsNullOrEmpty(path) && File.Exists(path)) return File.ReadAllText(path); }
            catch { }
            return "A warning was reported but the log file could not be read.";
        }

        // -------------------------------------------------------------------------
        //  Crash-type detection (used by CrashDialog for the dynamic header text)

        public static string DetectCrashType(string text)
        {
            if (string.IsNullOrEmpty(text)) return "The game has crashed";
            if (Contains(text, "Null Object Reference") || Contains(text, "Null Function Pointer")
                || Contains(text, "Field Access on Null"))
                return "Null Reference — The game has crashed";
            if (Contains(text, "Stack Overflow"))
                return "Stack Overflow — The game has crashed";
            if (Contains(text, "Out of Memory"))
                return "Out of Memory — The game has crashed";
            if (Contains(text, "Access Violation"))
                return "Access Violation — The game has crashed";
            if (Contains(text, "UncaughtErrorEvent"))
                return "Uncaught Exception — The game has crashed";
            if (Contains(text, "Assertion Failed"))
                return "Assertion Failed — The game has crashed";
            return "The game has crashed";
        }

        static bool Contains(string text, string value)
        {
            return text.IndexOf(value, StringComparison.OrdinalIgnoreCase) >= 0;
        }
    }

    // =========================================================================
    //  Log syntax highlighter
    //  Shared between CrashDialog and WarningDialog.
    //  Clears the RichTextBox and re-fills it line by line with colours.
    // =========================================================================

    static class LogHighlighter
    {
        // Colour palette (matches the dark theme of both dialogs)
        static readonly Color ColDefault  = Color.FromArgb(220, 220, 224);
        static readonly Color ColHeader   = Color.FromArgb( 90, 170, 255); // blue
        static readonly Color ColSection  = Color.FromArgb( 70, 140, 210); // lighter blue
        static readonly Color ColError    = Color.FromArgb(255,  70,  55); // red
        static readonly Color ColContext  = Color.FromArgb(220, 185,  70); // gold
        static readonly Color ColUser     = Color.FromArgb(150, 255, 160); // green
        static readonly Color ColLib      = Color.FromArgb(110, 110, 120); // muted grey
        static readonly Color ColMod      = Color.FromArgb(255, 200,  50); // amber
        static readonly Color ColCpp      = Color.FromArgb(200, 110, 110); // muted red
        static readonly Color ColCrashLoc = Color.FromArgb(255,  80,  60); // bright red
        static readonly Color ColCause    = Color.FromArgb(255, 165,  40); // orange
        static readonly Color ColMuted    = Color.FromArgb(150, 150, 160); // grey
        static readonly Color ColWarning  = Color.FromArgb(255, 190,   0); // amber (warning mode)

        public static void Apply(RichTextBox rtb, string text)
        {
            rtb.SuspendLayout();
            rtb.Clear();

            if (string.IsNullOrEmpty(text))
            {
                rtb.ResumeLayout();
                return;
            }

            // Split preserving empty lines
            string[] lines = text.Split('\n');

            foreach (string raw in lines)
            {
                string line = raw.TrimEnd('\r');
                Color  col  = GetLineColor(line);

                // The "← likely crash location" suffix on a [USER] line gets its
                // own colour to make it pop.
                int markerIdx = line.IndexOf("← likely crash location", StringComparison.Ordinal);
                if (markerIdx > 0 && col == ColUser)
                {
                    // prefix part
                    rtb.SelectionColor = ColUser;
                    rtb.AppendText(line.Substring(0, markerIdx));
                    // marker part
                    rtb.SelectionColor = ColCrashLoc;
                    rtb.AppendText(line.Substring(markerIdx));
                    rtb.SelectionColor = ColDefault;
                    rtb.AppendText("\n");
                }
                else
                {
                    rtb.SelectionColor = col;
                    rtb.AppendText(line + "\n");
                }
            }

            rtb.SelectionColor = ColDefault;
            rtb.ResumeLayout();
        }

        static Color GetLineColor(string line)
        {
            if (string.IsNullOrEmpty(line))
                return ColDefault;

            string trimmed = line.TrimStart();

            // Section headers
            if (trimmed.StartsWith("==="))
                return ColHeader;
            if (trimmed.StartsWith("---"))
                return ColSection;

            // Frame tags
            if (trimmed.Contains("[USER]"))  return ColUser;
            if (trimmed.Contains("[LIB ]"))  return ColLib;
            if (trimmed.Contains("[MOD ]"))  return ColMod;
            if (trimmed.Contains("[C++ ]"))  return ColCpp;

            // Key-value labels at the start of a line
            if (StartsWith(line, "Error    :"))  return ColError;
            if (StartsWith(line, "Context  :"))  return ColContext;

            // Script-error structured fields (from CrashHandler.flushScriptWarnings)
            if (StartsWith(line, "Script   :"))  return ColUser;     // green  — script path
            if (StartsWith(line, "Function :"))  return ColMod;      // amber  — function name
            if (StartsWith(line, "Line     :"))  return ColContext;   // gold   — line number
            if (StartsWith(line, "Source   :"))  return ColCause;    // orange — source snippet

            // Cause chain
            if (trimmed.StartsWith("[") && trimmed.Contains("] ") && line.StartsWith("  ["))
                return ColCause;

            // Warning indicator
            if (trimmed.StartsWith("⚠"))
                return ColWarning;

            // Metadata lines (Version, Date, System, GPU, …)
            if (StartsWithAny(line,
                "Version  :", "Date     :", "System   :", "CPU Cores:",
                "GPU      :", "GL       :", "Flixel   :", "OpenFL   :",
                "Memory   :", "Window   :", "Crash dir:", "State    :",
                "FPS      :", "Song     :", "Difficulty:"))
                return ColMuted;

            return ColDefault;
        }

        static bool StartsWith(string line, string prefix)
        {
            return line.StartsWith(prefix, StringComparison.Ordinal);
        }

        static bool StartsWithAny(string line, params string[] prefixes)
        {
            foreach (var p in prefixes)
                if (line.StartsWith(p, StringComparison.Ordinal)) return true;
            return false;
        }
    }

    // =========================================================================
    //  Shared colour constants (used by both dialog classes)
    // =========================================================================

    static class Theme
    {
        public static readonly Color BgDark      = Color.FromArgb( 28,  28,  30);
        public static readonly Color BgPanel     = Color.FromArgb( 44,  44,  46);
        public static readonly Color TextPrimary = Color.FromArgb(220, 220, 224);
        public static readonly Color TextMuted   = Color.FromArgb(160, 160, 168);
        public static readonly Color BtnBg       = Color.FromArgb( 58,  58,  60);
        public static readonly Color BtnHover    = Color.FromArgb( 72,  72,  74);
        public static readonly Color AccentRed   = Color.FromArgb(255,  59,  48);
        public static readonly Color AccentAmber = Color.FromArgb(255, 190,   0);

        public static Font GetMonoFont()
        {
            var f = new Font("Cascadia Code", 8.5f);
            return f.Name == "Cascadia Code" ? f : new Font("Consolas", 9f);
        }

        public static Button MakeButton(string text, Color foreColor, EventHandler onClick)
        {
            var btn = new Button
            {
                Text          = text,
                AutoSize      = true,
                MinimumSize   = new Size(120, 32),
                BackColor     = BtnBg,
                ForeColor     = foreColor,
                FlatStyle     = FlatStyle.Flat,
                Font          = new Font("Segoe UI", 8.5f),
                Cursor        = Cursors.Hand,
                Margin        = new Padding(0, 0, 8, 0),
            };
            btn.FlatAppearance.BorderSize         = 0;
            btn.FlatAppearance.MouseOverBackColor = BtnHover;
            btn.FlatAppearance.MouseDownBackColor = BgPanel;
            btn.Click += onClick;
            return btn;
        }
    }

    // =========================================================================
    //  Crash dialog  (💥  fatal crash, game is gone)
    // =========================================================================

    sealed class CrashDialog : Form
    {
        [DllImport("shell32.dll")]
        static extern IntPtr ShellExecute(IntPtr h, string op, string file, string p, string dir, int show);

        readonly string _logDir;
        readonly string _reportUrl;
        readonly string _crashText;
        readonly string _logFilePath;   // may be null if no log was found
        RichTextBox _textBox;

        public CrashDialog(string crashText, string logDir, string reportUrl, int exitCode, string logFilePath)
        {
            _crashText   = crashText   ?? "";
            _logDir      = logDir      ?? "./crash/";
            _reportUrl   = reportUrl   ?? "";
            _logFilePath = logFilePath;
            BuildUI(exitCode);
        }

        void BuildUI(int exitCode)
        {
            Text            = "Cool Engine — Crash Reporter";
            Size            = new Size(800, 580);
            MinimumSize     = new Size(640, 420);
            StartPosition   = FormStartPosition.CenterScreen;
            BackColor       = Theme.BgDark;
            ForeColor       = Theme.TextPrimary;
            Font            = new Font("Segoe UI", 9f);
            FormBorderStyle = FormBorderStyle.Sizable;
            Icon            = SystemIcons.Error;

            // ── Header ───────────────────────────────────────────────────────
            var header = new Panel
            {
                Dock      = DockStyle.Top,
                Height    = 70,
                BackColor = Theme.BgPanel,
                Padding   = new Padding(16, 0, 16, 0),
            };

            var iconLbl = new Label
            {
                Text     = "💥",
                Font     = new Font("Segoe UI Emoji", 22f),
                ForeColor = Theme.AccentRed,
                AutoSize = true,
                Location = new Point(16, 14),
            };

            // Dynamic title derived from the crash report contents
            var titleLbl = new Label
            {
                Text      = Program.DetectCrashType(_crashText),
                Font      = new Font("Segoe UI Semibold", 13f, FontStyle.Bold),
                ForeColor = Theme.TextPrimary,
                AutoSize  = true,
                Location  = new Point(60, 12),
            };

            var subLbl = new Label
            {
                Text      = "Exit code: 0x" + exitCode.ToString("X8")
                            + "   —   A crash report has been saved.",
                Font      = new Font("Segoe UI", 8.5f),
                ForeColor = Theme.TextMuted,
                AutoSize  = true,
                Location  = new Point(61, 40),
            };

            header.Controls.AddRange(new Control[] { iconLbl, titleLbl, subLbl });

            // ── Text area ────────────────────────────────────────────────────
            var textPanel = new Panel
            { Dock = DockStyle.Fill, Padding = new Padding(12, 8, 12, 8), BackColor = Theme.BgDark };

            _textBox = new RichTextBox
            {
                Dock        = DockStyle.Fill,
                ReadOnly    = true,
                Font        = Theme.GetMonoFont(),
                BackColor   = Theme.BgPanel,
                ForeColor   = Theme.TextPrimary,
                BorderStyle = BorderStyle.None,
                ScrollBars  = RichTextBoxScrollBars.Vertical,
                WordWrap    = false,
                Padding     = new Padding(8),
            };
            textPanel.Controls.Add(_textBox);

            // ── Button bar ───────────────────────────────────────────────────
            var bar = new Panel
            { Dock = DockStyle.Bottom, Height = 52, BackColor = Theme.BgPanel, Padding = new Padding(12, 8, 12, 8) };

            var btnCopy   = Theme.MakeButton("📋  Copy Report", Theme.TextPrimary, OnCopy);
            var btnFolder = Theme.MakeButton("📁  Open Folder", Theme.TextPrimary, OnOpenFolder);
            var btnLog    = Theme.MakeButton("📄  Open Log File", Theme.TextPrimary, OnOpenLogFile);
            var btnBug    = Theme.MakeButton("🐞  Report Bug",   Theme.TextPrimary, OnReportBug);
            var btnClose  = Theme.MakeButton("✕  Close",         Theme.AccentRed,  (s, e) => Close());

            // Hide "Open log file" if we have no path
            if (string.IsNullOrEmpty(_logFilePath)) btnLog.Visible = false;

            var leftFlow = new FlowLayoutPanel
            { Dock = DockStyle.Fill, FlowDirection = FlowDirection.LeftToRight, WrapContents = false };
            leftFlow.Controls.AddRange(new Control[] { btnCopy, btnFolder, btnLog, btnBug });

            var rightFlow = new FlowLayoutPanel
            { Dock = DockStyle.Right, FlowDirection = FlowDirection.RightToLeft, AutoSize = true };
            rightFlow.Controls.Add(btnClose);

            bar.Controls.Add(leftFlow);
            bar.Controls.Add(rightFlow);

            Controls.Add(textPanel);
            Controls.Add(bar);
            Controls.Add(header);

            // Apply syntax highlighting and auto-scroll to first [USER] frame
            Load += (s, e) =>
            {
                LogHighlighter.Apply(_textBox, _crashText);

                // Scroll to the first [USER] frame so the crash location is visible
                int idx = _crashText.IndexOf("[USER]", StringComparison.Ordinal);
                _textBox.SelectionStart = idx > 0 ? idx : 0;
                _textBox.ScrollToCaret();
            };
        }

        void OnCopy(object s, EventArgs e)
        {
            try
            {
                Clipboard.SetText(_crashText);
                var btn = (Button)s;
                string orig = btn.Text;
                btn.Text = "✔  Copied!";
                var t = new System.Windows.Forms.Timer { Interval = 1500 };
                t.Tick += (_, __) => { btn.Text = orig; t.Stop(); };
                t.Start();
            }
            catch { }
        }

        void OnOpenFolder(object s, EventArgs e)
        {
            try
            {
                string path = Path.GetFullPath(_logDir);
                if (Directory.Exists(path))
                    ShellExecute(IntPtr.Zero, "open", path, null, null, 1);
                else
                    MessageBox.Show("Crash folder not found:\n" + path, "Folder not found",
                        MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
            catch { }
        }

        void OnOpenLogFile(object s, EventArgs e)
        {
            try
            {
                if (!string.IsNullOrEmpty(_logFilePath) && File.Exists(_logFilePath))
                    Process.Start(_logFilePath);
                else
                    MessageBox.Show("Log file not found.", "File not found",
                        MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
            catch { }
        }

        void OnReportBug(object s, EventArgs e)
        {
            try { Process.Start(_reportUrl); } catch { }
        }

        protected override void OnPaint(PaintEventArgs e) { base.OnPaint(e); }
    }

    // =========================================================================
    //  Warning dialog  (⚠️  non-fatal script error, game still running)
    // =========================================================================

    sealed class WarningDialog : Form
    {
        readonly string _warningText;
        readonly string _logFilePath;
        RichTextBox _textBox;

        public WarningDialog(string warningText, string logFilePath)
        {
            _warningText = warningText ?? "(no details)";
            _logFilePath = logFilePath;
            BuildUI();
        }

        void BuildUI()
        {
            // ── Detect mode: batch load warnings vs. single runtime warning ──
            bool isBatchLoad = _warningText.Contains("SCRIPT LOAD WARNINGS");
            int  errorCount  = 0;
            if (isBatchLoad)
            {
                // Count "--- Error N of M ---" blocks to get the total
                int idx = 0;
                while ((idx = _warningText.IndexOf("--- Error ", idx, StringComparison.Ordinal)) >= 0)
                { errorCount++; idx++; }
            }

            string windowTitle   = isBatchLoad ? "Cool Engine — Script Load Errors" : "Cool Engine — Script Warning";
            string headerTitle   = isBatchLoad
                ? (errorCount > 1 ? errorCount + " script errors found — game continues" : "Script error found — game continues")
                : "Script error — game continues";
            string sub1Text      = isBatchLoad
                ? "These errors occurred while loading scripts at startup."
                : "This is a non-fatal warning. The game is still running normally.";
            string sub2Text      = isBatchLoad
                ? "The game will continue, but affected scripts may not work."
                : "Press OK to dismiss and continue.";

            Text            = windowTitle;
            Size            = new Size(860, 580);
            MinimumSize     = new Size(660, 400);
            StartPosition   = FormStartPosition.CenterScreen;
            BackColor       = Theme.BgDark;
            ForeColor       = Theme.TextPrimary;
            Font            = new Font("Segoe UI", 9f);
            FormBorderStyle = FormBorderStyle.Sizable;
            Icon            = SystemIcons.Warning;

            // ── Header ───────────────────────────────────────────────────────
            var header = new Panel
            {
                Dock      = DockStyle.Top,
                Height    = 80,
                BackColor = Theme.BgPanel,
                Padding   = new Padding(16, 0, 16, 0),
            };

            var iconLbl = new Label
            {
                Text      = isBatchLoad ? "🚨" : "⚠️",
                Font      = new Font("Segoe UI Emoji", 22f),
                ForeColor = isBatchLoad ? Theme.AccentRed : Theme.AccentAmber,
                AutoSize  = true,
                Location  = new Point(16, 16),
            };

            var titleLbl = new Label
            {
                Text      = headerTitle,
                Font      = new Font("Segoe UI Semibold", 13f, FontStyle.Bold),
                ForeColor = Theme.TextPrimary,
                AutoSize  = true,
                Location  = new Point(60, 12),
            };

            var sub1 = new Label
            {
                Text      = sub1Text,
                Font      = new Font("Segoe UI", 8.5f),
                ForeColor = Theme.TextMuted,
                AutoSize  = true,
                Location  = new Point(61, 40),
            };

            var sub2 = new Label
            {
                Text      = sub2Text,
                Font      = new Font("Segoe UI", 8.5f),
                ForeColor = Theme.TextMuted,
                AutoSize  = true,
                Location  = new Point(61, 58),
            };

            header.Controls.AddRange(new Control[] { iconLbl, titleLbl, sub1, sub2 });

            // ── Text area ────────────────────────────────────────────────────
            var textPanel = new Panel
            { Dock = DockStyle.Fill, Padding = new Padding(12, 8, 12, 8), BackColor = Theme.BgDark };

            _textBox = new RichTextBox
            {
                Dock        = DockStyle.Fill,
                ReadOnly    = true,
                Font        = Theme.GetMonoFont(),
                BackColor   = Theme.BgPanel,
                ForeColor   = Theme.TextPrimary,
                BorderStyle = BorderStyle.None,
                ScrollBars  = RichTextBoxScrollBars.Vertical,
                WordWrap    = false,
                Padding     = new Padding(8),
            };
            textPanel.Controls.Add(_textBox);

            // ── Button bar ───────────────────────────────────────────────────
            var bar = new Panel
            { Dock = DockStyle.Bottom, Height = 52, BackColor = Theme.BgPanel, Padding = new Padding(12, 8, 12, 8) };

            var btnCopy = Theme.MakeButton("📋  Copy", Theme.TextPrimary, OnCopy);
            var btnLog  = Theme.MakeButton("📄  Open Log File", Theme.TextPrimary, OnOpenLogFile);
            var btnOk   = Theme.MakeButton("✔  OK — Continue", Theme.AccentAmber, (s, e) => Close());
            btnOk.MinimumSize = new Size(150, 32);

            if (string.IsNullOrEmpty(_logFilePath)) btnLog.Visible = false;

            var leftFlow = new FlowLayoutPanel
            { Dock = DockStyle.Fill, FlowDirection = FlowDirection.LeftToRight, WrapContents = false };
            leftFlow.Controls.AddRange(new Control[] { btnCopy, btnLog });

            var rightFlow = new FlowLayoutPanel
            { Dock = DockStyle.Right, FlowDirection = FlowDirection.RightToLeft, AutoSize = true };
            rightFlow.Controls.Add(btnOk);

            bar.Controls.Add(leftFlow);
            bar.Controls.Add(rightFlow);

            Controls.Add(textPanel);
            Controls.Add(bar);
            Controls.Add(header);

            AcceptButton = btnOk;
            KeyPreview   = true;
            KeyDown     += (s, e) => { if (e.KeyCode == Keys.Escape || e.KeyCode == Keys.Return) Close(); };

            Load += (s, e) =>
            {
                LogHighlighter.Apply(_textBox, _warningText);
                // Scroll to the error line
                int idx = FindLine(_warningText, "Error    :");
                _textBox.SelectionStart = idx > 0 ? idx : 0;
                _textBox.ScrollToCaret();
            };
        }

        static int FindLine(string text, string prefix)
        {
            int idx = text.IndexOf("\n" + prefix, StringComparison.Ordinal);
            return idx > 0 ? idx + 1 : text.IndexOf(prefix, StringComparison.Ordinal);
        }

        void OnCopy(object s, EventArgs e)
        {
            try
            {
                Clipboard.SetText(_warningText);
                var btn = (Button)s;
                string orig = btn.Text;
                btn.Text = "✔  Copied!";
                var t = new System.Windows.Forms.Timer { Interval = 1500 };
                t.Tick += (_, __) => { btn.Text = orig; t.Stop(); };
                t.Start();
            }
            catch { }
        }

        void OnOpenLogFile(object s, EventArgs e)
        {
            try
            {
                if (!string.IsNullOrEmpty(_logFilePath) && File.Exists(_logFilePath))
                    Process.Start(_logFilePath);
                else
                    MessageBox.Show("Log file not found.", "File not found",
                        MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
            catch { }
        }
    }
}
