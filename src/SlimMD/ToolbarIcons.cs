using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;

namespace SlimMD;

/// <summary>
/// Small toolbar icons drawn with GDI+ — the app ships no image assets, so
/// every glyph is designed on a 16x16 grid, rendered at 4x and downscaled
/// for crisp anti-aliased strokes at any DPI.
/// </summary>
internal static class ToolbarIcons
{
    private static readonly Color Ink = Color.FromArgb(55, 60, 68);
    private static readonly Color Paper = Color.White;

    /// <summary>Logical icon size (16px) scaled to the current system DPI.</summary>
    public static int IconSize()
    {
        try
        {
            var dpi = (int)GetDpiForSystem();
            if (dpi < 96) dpi = 96;
            return (int)Math.Round(16 * dpi / 96.0);
        }
        catch
        {
            return 16;
        }
    }

    [DllImport("user32.dll")]
    private static extern uint GetDpiForSystem();

    // ------------------------------------------------------------- glyphs

    /// <summary>New document: a page with a folded corner.</summary>
    public static Bitmap New(int size) => Render(size, g =>
    {
        var page = new GraphicsPath();
        page.AddPolygon(new[]
        {
            new PointF(2.5f, 1.5f), new PointF(9.9f, 1.5f), new PointF(13.5f, 5.1f),
            new PointF(13.5f, 14.5f), new PointF(2.5f, 14.5f),
        });
        FillStroke(g, page);
        g.DrawPath(Pen(1f), new GraphicsPath(new[]
        {
            new PointF(9.9f, 1.5f), new PointF(9.9f, 5.1f), new PointF(13.5f, 5.1f),
        }, new byte[] { 0, 1, 1 }));
    });

    /// <summary>Open: a folder.</summary>
    public static Bitmap Open(int size) => Render(size, g =>
    {
        var back = new GraphicsPath();
        back.AddPolygon(new[]
        {
            new PointF(1.5f, 2.8f), new PointF(6f, 2.8f), new PointF(7.4f, 4.8f),
            new PointF(14.5f, 4.8f), new PointF(14.5f, 7.6f), new PointF(1.5f, 7.6f),
        });
        FillStroke(g, back);

        var front = new GraphicsPath();
        front.AddPolygon(new[]
        {
            new PointF(1.5f, 6.4f), new PointF(14.5f, 6.4f),
            new PointF(14.5f, 14f), new PointF(1.5f, 14f),
        });
        FillStroke(g, front);
    });

    /// <summary>Save: a floppy disk.</summary>
    public static Bitmap Save(int size) => Render(size, Floppy);

    /// <summary>Save As: two overlapping floppies (save a copy / new name) —
    /// fills the grid diagonally so it matches the visual weight of the rest.</summary>
    public static Bitmap SaveAs(int size) => Render(size, g =>
    {
        // Back disk (top left): solid, with its shutter showing above the front disk.
        using (var back = RoundRect(1.5f, 1.5f, 9.6f, 9.6f, 1.2f))
        {
            using var ink = new SolidBrush(Ink);
            g.FillPath(ink, back);
        }
        using (var paper = new SolidBrush(Paper))
        {
            g.FillRectangle(paper, 7.3f, 1.5f, 2.1f, 2.8f);
        }

        // Front disk (bottom right): white ring first to carve it out of the back one.
        using (var ring = RoundRect(5.4f, 5.4f, 9.1f, 9.1f, 1.1f))
        {
            using var gap = new Pen(Paper, 1.6f);
            g.DrawPath(gap, ring);
        }
        using (var front = RoundRect(5.4f, 5.4f, 9.1f, 9.1f, 1.1f))
        {
            using var ink = new SolidBrush(Ink);
            g.FillPath(ink, front);
            using var paper = new SolidBrush(Paper);
            g.FillRectangle(paper, 10.7f, 5.4f, 2.2f, 3f);    // shutter
            g.FillRectangle(ink, 11.9f, 5.4f, 1f, 2f);         // slider notch
            g.FillRectangle(paper, 7.25f, 10.5f, 5.4f, 3.1f);  // label
        }
    });

    /// <summary>Export: an upload tray with an arrow leaving it.</summary>
    public static Bitmap Export(int size) => Render(size, g =>
    {
        var box = new GraphicsPath();
        box.AddPolygon(new[]
        {
            new PointF(1.5f, 9.2f), new PointF(14.5f, 9.2f),
            new PointF(12.7f, 14.5f), new PointF(3.3f, 14.5f),
        });
        FillStroke(g, box);

        using var shaft = Pen(1.4f);
        g.DrawLine(shaft, 8f, 4.8f, 8f, 8.6f);

        var head = new GraphicsPath();
        head.AddPolygon(new[]
        {
            new PointF(5.3f, 6f), new PointF(10.7f, 6f), new PointF(8f, 1.9f),
        });
        using var fill = new SolidBrush(Ink);
        g.FillPath(fill, head);
    });

    /// <summary>Edit: a pencil.</summary>
    public static Bitmap Edit(int size) => Render(size, g =>
        Pencil(g, new PointF(2.6f, 13.4f), new PointF(14.4f, 1.6f), 1.7f, 3.2f));

    /// <summary>Language: a globe (meridian + equator + latitudes).</summary>
    public static Bitmap Language(int size) => Render(size, g =>
    {
        using var globe = new GraphicsPath();
        globe.AddEllipse(1.5f, 1.5f, 13f, 13f);
        FillStroke(g, globe);

        using var thin = Pen(0.9f);
        var meridian = new GraphicsPath();
        meridian.AddEllipse(5.3f, 1.5f, 5.4f, 13f);
        g.DrawPath(thin, meridian);
        g.DrawLine(thin, 1.5f, 8f, 14.5f, 8f);
        // Latitude arcs: flatter ellipses clipped visually by the globe outline.
        g.DrawArc(thin, 1.9f, -0.5f, 12.2f, 17f, 200f, 140f);
        g.DrawArc(thin, 1.9f, -0.5f, 12.2f, 17f, 20f, 140f);
    });

    /// <summary>About: an information circle.</summary>
    public static Bitmap About(int size) => Render(size, g =>
    {
        using var circle = new GraphicsPath();
        circle.AddEllipse(1.5f, 1.5f, 13f, 13f);
        FillStroke(g, circle);

        using var fill = new SolidBrush(Ink);
        g.FillEllipse(fill, 6.95f, 3.7f, 2.1f, 2.1f);
        g.FillRectangle(fill, 7.15f, 6.5f, 1.7f, 5.6f);
    });

    // ------------------------------------------------------------ plumbing

    private delegate void Paint(Graphics g);

    private static Bitmap Render(int size, Paint paint)
    {
        const int over = 4;   // supersampling factor
        var big = new Bitmap(size * over, size * over);
        using (var g = Graphics.FromImage(big))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            g.ScaleTransform(size * over / 16f, size * over / 16f);
            paint(g);
        }

        var small = new Bitmap(size, size);
        using (var g = Graphics.FromImage(small))
        {
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            g.DrawImage(big, 0, 0, size, size);
        }

        big.Dispose();
        return small;
    }

    private static Pen Pen(float width) => new(Ink, width)
    {
        LineJoin = LineJoin.Round,
        StartCap = LineCap.Round,
        EndCap = LineCap.Round,
    };

    private static void FillStroke(Graphics g, GraphicsPath path)
    {
        using var fill = new SolidBrush(Paper);
        using var pen = Pen(1f);
        g.FillPath(fill, path);
        g.DrawPath(pen, path);
    }

    private static void Floppy(Graphics g)
    {
        using var body = RoundRect(1.5f, 1.5f, 13f, 13f, 1.2f);
        using var ink = new SolidBrush(Ink);
        g.FillPath(ink, body);

        using var white = new SolidBrush(Paper);
        // Label at the bottom, shutter + slider notch at the top right.
        g.FillRectangle(white, 4.2f, 8.8f, 7.6f, 4.8f);
        g.FillRectangle(white, 8.6f, 1.5f, 3.6f, 4.9f);
        g.FillRectangle(ink, 10.4f, 1.5f, 1.8f, 3f);
    }

    /// <summary>A pencil from <paramref name="end"/> (eraser) to <paramref name="tip"/>.</summary>
    private static void Pencil(Graphics g, PointF end, PointF tip, float halfWidth, float tipLength)
    {
        var dx = tip.X - end.X;
        var dy = tip.Y - end.Y;
        var len = (float)Math.Sqrt(dx * dx + dy * dy);
        if (len <= 0) return;
        var ux = dx / len;
        var uy = dy / len;
        var px = -uy * halfWidth;
        var py = ux * halfWidth;
        var bodyEnd = new PointF(tip.X - ux * tipLength, tip.Y - uy * tipLength);

        var body = new GraphicsPath();
        body.AddPolygon(new[]
        {
            new PointF(end.X + px, end.Y + py),
            new PointF(bodyEnd.X + px, bodyEnd.Y + py),
            new PointF(bodyEnd.X - px, bodyEnd.Y - py),
            new PointF(end.X - px, end.Y - py),
        });
        FillStroke(g, body);

        var point = new GraphicsPath();
        point.AddPolygon(new[]
        {
            new PointF(bodyEnd.X + px, bodyEnd.Y + py),
            new PointF(bodyEnd.X - px, bodyEnd.Y - py),
            tip,
        });
        using var ink = new SolidBrush(Ink);
        g.FillPath(ink, point);

        // Ferrule line near the eraser end.
        var fx = end.X + ux * 3.2f;
        var fy = end.Y + uy * 3.2f;
        using var pen = Pen(0.9f);
        g.DrawLine(pen, fx + px, fy + py, fx - px, fy - py);
    }

    private static GraphicsPath RoundRect(float x, float y, float w, float h, float r)
    {
        var p = new GraphicsPath();
        p.AddArc(x, y, r * 2, r * 2, 180, 90);
        p.AddArc(x + w - r * 2, y, r * 2, r * 2, 270, 90);
        p.AddArc(x + w - r * 2, y + h - r * 2, r * 2, r * 2, 0, 90);
        p.AddArc(x, y + h - r * 2, r * 2, r * 2, 90, 90);
        p.CloseFigure();
        return p;
    }
}
