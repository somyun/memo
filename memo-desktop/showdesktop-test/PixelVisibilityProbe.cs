using System.Drawing;

namespace ShowDesktopTest;

internal static class PixelVisibilityProbe
{
    public static PixelVisibilityResult Sample(Rectangle screenBounds, Color expectedColor, int tolerance = 16)
    {
        if (screenBounds.Width <= 0 || screenBounds.Height <= 0)
            return PixelVisibilityResult.Unavailable("empty-bounds");

        var samplePoints = new[]
        {
            new Point(screenBounds.Left + screenBounds.Width / 2, screenBounds.Top + screenBounds.Height / 2),
            new Point(screenBounds.Left + Math.Max(2, screenBounds.Width / 4), screenBounds.Top + Math.Max(2, screenBounds.Height / 4)),
            new Point(screenBounds.Right - Math.Max(3, screenBounds.Width / 4), screenBounds.Top + Math.Max(2, screenBounds.Height / 4)),
            new Point(screenBounds.Left + Math.Max(2, screenBounds.Width / 4), screenBounds.Bottom - Math.Max(3, screenBounds.Height / 4)),
            new Point(screenBounds.Right - Math.Max(3, screenBounds.Width / 4), screenBounds.Bottom - Math.Max(3, screenBounds.Height / 4))
        };

        var colors = new List<Color>();
        var matches = 0;

        try
        {
            foreach (var point in samplePoints)
            {
                using var bitmap = new Bitmap(1, 1);
                using var graphics = Graphics.FromImage(bitmap);
                graphics.CopyFromScreen(point, Point.Empty, new Size(1, 1));
                var color = bitmap.GetPixel(0, 0);
                colors.Add(color);
                if (ColorDistance(color, expectedColor) <= tolerance)
                    matches++;
            }
        }
        catch (Exception ex)
        {
            return new PixelVisibilityResult(false, screenBounds, expectedColor, colors.ToArray(), matches, samplePoints.Length, ex.GetType().Name);
        }

        return new PixelVisibilityResult(matches >= 3, screenBounds, expectedColor, colors.ToArray(), matches, samplePoints.Length, "sampled");
    }

    private static int ColorDistance(Color a, Color b)
    {
        return Math.Abs(a.R - b.R) + Math.Abs(a.G - b.G) + Math.Abs(a.B - b.B);
    }
}
