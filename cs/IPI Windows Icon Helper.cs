using System;
using System.Runtime.InteropServices;

public class IconHelper {
    [DllImport("shell32.dll", CharSet = CharSet.Auto)]
    public static extern IntPtr ExtractIcon(
        IntPtr hInst,
        string lpszExeFileName,
        int nIconIndex
    );
}