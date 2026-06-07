using System.Drawing;

namespace ShowDesktopTest;

internal sealed record PixelVisibilityResult(
    bool IsVisible,
    Rectangle ScreenBounds,
    Color ExpectedColor,
    Color[] SampledColors,
    int MatchingSamples,
    int TotalSamples,
    string Reason)
{
    public static PixelVisibilityResult Unavailable(string reason)
    {
        return new PixelVisibilityResult(false, Rectangle.Empty, Color.Empty, Array.Empty<Color>(), 0, 0, reason);
    }
}
