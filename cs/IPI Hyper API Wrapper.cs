using System;
using System.Runtime.InteropServices;

public static class HyperAPIWrapper {
    [DllImport("$dllPath", CharSet = CharSet.Ansi, CallingConvention = CallingConvention.Cdecl)]
    public static extern IntPtr read_hyper_file(string path, string sql, int schema);
    
    [DllImport("$dllPath", CharSet = CharSet.Ansi, CallingConvention = CallingConvention.Cdecl)]
    public static extern void FreeResult(IntPtr ptr);
}