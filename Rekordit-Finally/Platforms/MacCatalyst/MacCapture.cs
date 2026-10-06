using System.Runtime.InteropServices;
using Foundation;
using UIKit;
using CoreGraphics;

namespace Rekordit_Finally;

internal static class MacCapture
{
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void Completed(IntPtr error);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void Begin(int fps, int cursor, int dark, int quick, Completed completed);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void MenuAction(int action);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void InstallMenu(MenuAction action);
    private static readonly MenuAction menuAction = OnMenuAction;
    private static bool menuInstalled;
    private static bool quickSession;
    private static NSBundle? bridge;
    private static Begin? begin;
    private static readonly Completed completed = OnCompleted;
    private static TaskCompletionSource? completion;
    private static UIWindow? mainWindow;

    public static void ResizeWindow(double width, double height)
    {
        if (Application.Current?.Windows.FirstOrDefault()?.Handler?.PlatformView is not UIWindow window ||
            window.WindowScene is not { } scene || !OperatingSystem.IsMacCatalystVersionAtLeast(16))
            return;

        if (scene.SizeRestrictions is { } sizes)
        {
            sizes.AllowsFullScreen = false;
            sizes.MinimumSize = new CGSize(380, 240);
            sizes.MaximumSize = new CGSize(width, height);
        }
        var frame = scene.EffectiveGeometry.SystemFrame;
        scene.RequestGeometryUpdate(new UIWindowSceneGeometryPreferencesMac(new CGRect(frame.X, frame.Y, width, height)),
            error => System.Diagnostics.Debug.WriteLine(error.LocalizedDescription));
    }

    private static string LoadBridge()
    {
        var path = Path.Combine(NSBundle.MainBundle.ResourcePath ?? throw new InvalidOperationException("The app resources could not be located."), "CaptureBridge.bundle");
        bridge ??= NSBundle.FromPath(path) ?? throw new InvalidOperationException("The capture bridge is missing. Rebuild the Mac Catalyst app.");
        if (!bridge.Load())
            throw new InvalidOperationException("The native capture bridge could not be loaded.");
        begin ??= Marshal.GetDelegateForFunctionPointer<Begin>(NativeLibrary.GetExport(
            NativeLibrary.Load(Path.Combine(path, "Contents", "MacOS", "CaptureBridge")), "rekordit_begin"));

        return path;
    }

    public static void InstallMenuBar()
    {
        if (menuInstalled) return;
        var path = LoadBridge();
        var install = Marshal.GetDelegateForFunctionPointer<InstallMenu>(NativeLibrary.GetExport(
            NativeLibrary.Load(Path.Combine(path, "Contents", "MacOS", "CaptureBridge")), "rekordit_install_menu"));
        install(menuAction);
        menuInstalled = true;
    }

    [ObjCRuntime.MonoPInvokeCallback(typeof(MenuAction))]
    private static void OnMenuAction(int action) => MainThread.BeginInvokeOnMainThread(async () =>
    {
        if (completion is not null) return;
        var page = Shell.Current;
        try
        {
            if (action == 0) await StartAsync(quick: true);
            else
            {
                if (Application.Current?.Windows.FirstOrDefault()?.Handler?.PlatformView is UIWindow window)
                {
                    window.Hidden = false;
                    window.MakeKeyAndVisible();
                }
                if (page.Navigation.ModalStack.Count == 0)
                    await page.Navigation.PushModalAsync(new Views.Settings());
            }
        }
        catch (Exception error)
        {
            await page.DisplayAlertAsync("Recording", error.Message, "OK");
        }
    });

    public static Task StartAsync(bool quick = false)
    {
        if (completion is not null)
            throw new InvalidOperationException("A recording session is already open.");
        LoadBridge();
        quickSession = quick;
        var fps = new[] { 5, 10, 15, 30 }[Math.Clamp(Preferences.Default.Get("frameRateIndex", 1), 0, 3)];
        mainWindow = Application.Current?.Windows.FirstOrDefault()?.Handler?.PlatformView as UIWindow;
        completion = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var result = completion.Task;
        if (mainWindow is not null)
            mainWindow.Hidden = true;
        var app = Application.Current;
        var theme = app?.UserAppTheme == AppTheme.Unspecified ? app.RequestedTheme : app?.UserAppTheme;
        begin!(fps, Preferences.Default.Get("showCursor", true) ? 1 : 0,
            theme == AppTheme.Dark ? 1 : 0, quick ? 1 : 0, completed);
        return result;
    }

    [ObjCRuntime.MonoPInvokeCallback(typeof(Completed))]
    private static void OnCompleted(IntPtr error)
    {
        var message = error == IntPtr.Zero ? null : Marshal.PtrToStringUTF8(error);
        MainThread.BeginInvokeOnMainThread(() =>
        {
            if (mainWindow is not null)
            {
                if (!quickSession || message is not null)
                {
                    mainWindow.Hidden = false;
                    mainWindow.MakeKeyAndVisible();
                }
                mainWindow = null;
            }
            var finished = completion;
            completion = null;
            if (message is not null) finished?.TrySetException(new InvalidOperationException(message));
            else finished?.TrySetResult();
        });
    }
}
