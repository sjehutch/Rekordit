namespace Rekordit_Finally.Views;

public partial class Home : ContentPage
{
    public Home() => InitializeComponent();

    protected override void OnAppearing()
    {
        base.OnAppearing();
#if MACCATALYST
        Dispatcher.Dispatch(async () =>
        {
            MacCapture.ResizeWindow(420, 260);
            try { MacCapture.InstallMenuBar(); }
            catch (Exception error) { await DisplayAlertAsync("Menu bar unavailable", error.Message, "OK"); }
        });
#endif
    }

    private async void OnSettings(object? sender, EventArgs e) =>
        await Navigation.PushModalAsync(new Settings());

    private async void OnSelectArea(object? sender, EventArgs e)
    {
        SelectButton.IsEnabled = false;
        try
        {
#if MACCATALYST
            await MacCapture.StartAsync();
#else
            await DisplayAlertAsync("Screen capture", "Area recording is available on Mac Catalyst.", "OK");
#endif
        }
        catch (Exception error)
        {
            await DisplayAlertAsync("Could not start capture", error.Message, "OK");
        }
        finally
        {
            SelectButton.IsEnabled = true;
        }
    }
}
