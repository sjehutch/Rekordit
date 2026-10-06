namespace Rekordit_Finally;

public class App : Application
{
    internal const string AppearancePreference = "appearance";

    public App()
    {
        UserAppTheme = (AppTheme)Math.Clamp(Preferences.Default.Get(AppearancePreference, 0), 0, 2);
    }

    protected override Window CreateWindow(IActivationState? activationState) =>
        new(new AppShell()) { Title = "Screen to GIF", Width = 420, Height = 260, MinimumWidth = 380, MinimumHeight = 240 };
}
