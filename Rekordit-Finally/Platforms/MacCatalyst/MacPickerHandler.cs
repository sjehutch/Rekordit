using System.Collections.Specialized;
using System.ComponentModel;
using Microsoft.Maui.Handlers;
using Microsoft.Maui.Platform;
using UIKit;

namespace Rekordit_Finally;

public class MacPickerHandler : PickerHandler
{
    private UIButton? menuButton;
    private Picker? picker;

    protected override void ConnectHandler(MauiPicker platformView)
    {
        base.ConnectHandler(platformView);
        picker = (Picker)VirtualView;
        menuButton = new UIButton(UIButtonType.System)
        {
            Frame = platformView.Bounds,
            AutoresizingMask = UIViewAutoresizing.FlexibleWidth | UIViewAutoresizing.FlexibleHeight,
            HorizontalAlignment = UIControlContentHorizontalAlignment.Right,
            ShowsMenuAsPrimaryAction = true,
            AccessibilityTraits = UIAccessibilityTrait.Button
        };
        menuButton.SetImage(UIImage.GetSystemImage("chevron.down"), UIControlState.Normal);
        platformView.ShouldBeginEditing = _ => false;
        platformView.IsAccessibilityElement = false;
        platformView.AddSubview(menuButton);
        picker.PropertyChanged += OnPickerChanged;
        ((INotifyCollectionChanged)picker.Items).CollectionChanged += OnItemsChanged;
        UpdateMenu();
    }

    private void OnPickerChanged(object? sender, PropertyChangedEventArgs e) => UpdateMenu();
    private void OnItemsChanged(object? sender, NotifyCollectionChangedEventArgs e) => UpdateMenu();

    private void UpdateMenu()
    {
        if (picker is null || menuButton is null)
            return;

        var actions = picker.Items.Select((text, index) =>
        {
            var action = UIAction.Create(text, null, null, _ => picker.SelectedIndex = index);
            action.State = index == picker.SelectedIndex ? UIMenuElementState.On : UIMenuElementState.Off;
            return action;
        }).ToArray();

        menuButton.Menu = UIMenu.Create(actions);
        menuButton.Enabled = picker.IsEnabled && actions.Length > 0;
        menuButton.TintColor = picker.TextColor.ToPlatform();
        menuButton.AccessibilityLabel = $"{picker.Title}, {picker.SelectedItem}";
    }

    protected override void DisconnectHandler(MauiPicker platformView)
    {
        if (picker is not null)
        {
            picker.PropertyChanged -= OnPickerChanged;
            ((INotifyCollectionChanged)picker.Items).CollectionChanged -= OnItemsChanged;
            picker = null;
        }

        menuButton?.RemoveFromSuperview();
        menuButton?.Dispose();
        menuButton = null;
        platformView.ShouldBeginEditing = null;
        base.DisconnectHandler(platformView);
    }
}
