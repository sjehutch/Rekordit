namespace Rekordit_Finally.Views;

public partial class Settings : ContentPage
{
    private bool ready;

    public Settings()
    {
        InitializeComponent();
        FrameRatePicker.SelectedIndex = Math.Clamp(Preferences.Default.Get("frameRateIndex", 1), 0, 3);
        CursorSwitch.IsToggled = Preferences.Default.Get("showCursor", true);
        AppearancePicker.SelectedIndex = (int)(Application.Current?.UserAppTheme ?? AppTheme.Unspecified);
        ready = true;
    }

    private void OnChanged(object? sender, EventArgs e)
    {
        if (!ready)
            return;

        Preferences.Default.Set("frameRateIndex", FrameRatePicker.SelectedIndex);
        Preferences.Default.Set("showCursor", CursorSwitch.IsToggled);
        Preferences.Default.Set(App.AppearancePreference, AppearancePicker.SelectedIndex);
        if (Application.Current is { } app)
            app.UserAppTheme = (AppTheme)AppearancePicker.SelectedIndex;
    }

    private async void OnDone(object? sender, EventArgs e) => await Navigation.PopModalAsync();

    protected override void OnAppearing()
    {
        base.OnAppearing();
        if (Window is { } window) { window.Width = 460; window.Height = 360; }
#if MACCATALYST
        Dispatcher.Dispatch(() => MacCapture.ResizeWindow(460, 360));
#endif
    }

    protected override void OnDisappearing()
    {
        base.OnDisappearing();
        if (Window is { } window) { window.Width = 420; window.Height = 260; }
#if MACCATALYST
        Dispatcher.Dispatch(() => MacCapture.ResizeWindow(420, 260));
#endif
    }
}
