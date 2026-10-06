using CommunityToolkit.Maui;

namespace Rekordit_Finally;

public static class MauiProgram
{
    public static MauiApp CreateMauiApp() => MauiApp.CreateBuilder()
        .UseMauiApp<App>()
        .UseMauiCommunityToolkit()
#if MACCATALYST
        .ConfigureMauiHandlers(handlers => handlers.AddHandler<Picker, MacPickerHandler>())
#endif
        .Build();
}
