namespace Rekordit_Finally.Views;

public partial class Home : ContentPage
{
    public Home()
    {
        InitializeComponent();
        DisplayPicker.SelectedIndex = 0;
        FrameRatePicker.SelectedIndex = 1;
        WidthPicker.SelectedIndex = 2;
        AppearancePicker.SelectedIndex = (int)(Application.Current?.UserAppTheme ?? AppTheme.Unspecified);
    }

    private void OnAppearanceChanged(object? sender, EventArgs e)
    {
        if (Application.Current is not { } app || AppearancePicker.SelectedIndex < 0)
            return;

        app.UserAppTheme = (AppTheme)AppearancePicker.SelectedIndex;
        Preferences.Default.Set(App.AppearancePreference, AppearancePicker.SelectedIndex);
    }
}
