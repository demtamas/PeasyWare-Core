namespace PeasyWare.Application.Scanning;

/// <summary>
/// Parses GS1-128 barcode scan strings into structured <see cref="GtinScanResult"/> values.
///
/// Handles the label format used by Britvic (and standard GS1-128 in general):
///
///   Top barcode:    (01)05010102200142(10)001440487A
///   Bottom barcode: (00)150101027125056378(15)261130
///
/// Raw scanner output may include:
///   - Human-readable parentheses around AIs:  (01)...  (10)...
///   - FNC1 separator characters (\x1D or ~) between variable-length fields
///   - No delimiters at all for fixed-length AIs that are immediately followed by the next AI
///
/// The parser is deliberately defensive — unknown AIs are skipped rather than
/// causing a failure, so future label changes degrade gracefully.
/// </summary>
public static class GtinParser
{
    // FNC1 group separator — used between variable-length fields in raw scanner output
    private const char Fnc1  = '\x1D';
    private const char Tilde = '~';  // Some scanners emit ~ instead

    // --------------------------------------------------
    // Public entry point
    // --------------------------------------------------

    /// <summary>
    /// Parses a raw GS1-128 scan string.
    /// Returns an invalid result (never throws) if the input cannot be parsed.
    /// </summary>
    public static GtinScanResult Parse(string? rawScan)
    {
        if (string.IsNullOrWhiteSpace(rawScan))
            return GtinScanResult.Invalid("Scan input is empty.");

        try
        {
            var normalised = Normalise(rawScan);
            return ParseNormalised(normalised);
        }
        catch (Exception ex)
        {
            return GtinScanResult.Invalid($"Parse error: {ex.Message}");
        }
    }

    // --------------------------------------------------
    // Normalisation
    // --------------------------------------------------

    /// <summary>
    /// Converts scanner output to a consistent format for parsing.
    ///
    /// Strategies handled:
    ///   "(01)12345..." → remove parentheses, leave digits
    ///   "~"            → replace with FNC1
    ///   Whitespace     → strip
    /// </summary>
    private static string Normalise(string raw)
    {
        raw = raw.Replace(Tilde, Fnc1);

        if (raw.Contains('('))
            return ExpandParenthesisNotation(raw);

        return raw.Trim();
    }

    /// <summary>
    /// Converts "(01)value(10)value..." to a flat string the parser can walk.
    /// Variable-length AIs get a FNC1 appended after their value.
    /// </summary>
    private static string ExpandParenthesisNotation(string raw)
    {
        var sb = new System.Text.StringBuilder();
        var i  = 0;

        while (i < raw.Length)
        {
            if (raw[i] == '(')
            {
                var close = raw.IndexOf(')', i);
                if (close < 0) break;

                var ai = raw.Substring(i + 1, close - i - 1);
                sb.Append(ai);
                i = close + 1;

                var nextOpen = raw.IndexOf('(', i);
                var value    = nextOpen < 0
                    ? raw.Substring(i)
                    : raw.Substring(i, nextOpen - i);

                sb.Append(value);
                i += value.Length;

                if (IsVariableLength(ai))
                    sb.Append(Fnc1);
            }
            else
            {
                i++;
            }
        }

        return sb.ToString();
    }

    // --------------------------------------------------
    // Core parser — walks the normalised string
    // --------------------------------------------------

    private static GtinScanResult ParseNormalised(string data)
    {
        string?  sscc      = null;
        string?  gtin      = null;
        string?  batch     = null;
        DateOnly? bbe      = null;
        int?     quantity  = null;

        var pos        = 0;
        var recognised = 0;

        while (pos < data.Length)
        {
            if (data[pos] == Fnc1) { pos++; continue; }

            string? ai     = null;
            int     aiLen  = 0;

            foreach (var len in new[] { 2, 3, 4 })
            {
                if (pos + len > data.Length) continue;
                var candidate = data.Substring(pos, len);
                if (IsKnownAi(candidate)) { ai = candidate; aiLen = len; break; }
            }

            if (ai is null) { pos++; continue; }

            pos += aiLen;

            switch (ai)
            {
                case "00":
                    if (pos + 18 <= data.Length)
                    {
                        sscc = data.Substring(pos, 18);
                        pos += 18;
                        recognised++;
                    }
                    break;

                case "01":
                    if (pos + 14 <= data.Length)
                    {
                        gtin = data.Substring(pos, 14);
                        pos += 14;
                        recognised++;
                    }
                    break;

                case "10":
                    batch = ReadVariable(data, ref pos, 20);
                    if (batch is not null) recognised++;
                    break;

                case "15":
                case "17":
                    if (pos + 6 <= data.Length)
                    {
                        var dateStr = data.Substring(pos, 6);
                        bbe = ParseGs1Date(dateStr, lastDayOfMonth: ai == "15");
                        pos += 6;
                        if (bbe is not null) recognised++;
                    }
                    break;

                case "37":
                    var qtyStr = ReadVariable(data, ref pos, 8);
                    if (int.TryParse(qtyStr, out var qty))
                    {
                        quantity = qty;
                        recognised++;
                    }
                    break;

                default:
                    pos = SkipUnhandledAi(data, pos, ai);
                    break;
            }
        }

        if (recognised == 0)
            return GtinScanResult.Empty();

        return new GtinScanResult
        {
            Sscc       = sscc,
            Gtin       = gtin,
            Batch      = batch,
            BestBefore = bbe,
            Quantity   = quantity,
            IsValid    = true
        };
    }

    // --------------------------------------------------
    // Helpers
    // --------------------------------------------------

    private static string? ReadVariable(string data, ref int pos, int maxLength)
    {
        var start = pos;
        var end   = pos;

        while (end < data.Length && end - start < maxLength)
        {
            if (data[end] == Fnc1) break;
            if (end > start && end + 1 < data.Length && IsKnownAiAt(data, end)) break;
            end++;
        }

        if (end == start) return null;

        var value = data.Substring(start, end - start);
        pos = end;

        if (pos < data.Length && data[pos] == Fnc1)
            pos++;

        return value;
    }

    /// <summary>
    /// Parses a GS1 date string (YYMMDD).
    /// Year: YY 00-49 → 2000+YY, YY 50-99 → 1900+YY.
    /// Day 00 or AI 15 → last day of month.
    /// </summary>
    private static DateOnly? ParseGs1Date(string yymmdd, bool lastDayOfMonth = false)
    {
        if (yymmdd.Length != 6) return null;

        if (!int.TryParse(yymmdd.Substring(0, 2), out var yy)) return null;
        if (!int.TryParse(yymmdd.Substring(2, 2), out var mm)) return null;
        if (!int.TryParse(yymmdd.Substring(4, 2), out var dd)) return null;

        if (mm < 1 || mm > 12) return null;

        var year = yy <= 49 ? 2000 + yy : 1900 + yy;

        if (dd == 0 || lastDayOfMonth)
            dd = DateTime.DaysInMonth(year, mm);

        if (dd < 1 || dd > DateTime.DaysInMonth(year, mm)) return null;

        return new DateOnly(year, mm, dd);
    }

    private static int SkipUnhandledAi(string data, int pos, string ai)
    {
        var fixedLen = FixedLengthForAi(ai);
        if (fixedLen > 0)
            return Math.Min(pos + fixedLen, data.Length);

        while (pos < data.Length && data[pos] != Fnc1)
            pos++;
        if (pos < data.Length && data[pos] == Fnc1)
            pos++;

        return pos;
    }

    // --------------------------------------------------
    // AI tables
    // --------------------------------------------------

    private static bool IsKnownAi(string ai) => ai switch
    {
        "00" or "01" or "02"                                         => true,
        "10" or "11" or "12" or "13" or "15" or "17"                => true,
        "20" or "21" or "22"                                         => true,
        "30" or "37"                                                 => true,
        "310" or "311" or "312" or "313" or "314" or "315" or "316" => true,
        "320" or "321" or "322" or "323" or "324" or "325" or "326" => true,
        _                                                            => false
    };

    private static bool IsVariableLength(string ai) => ai switch
    {
        "00" or "01" or "02"         => false,
        "15" or "17"                 => false,
        "11" or "12" or "13"         => false,
        _                            => true
    };

    private static int FixedLengthForAi(string ai) => ai switch
    {
        "00" => 18,
        "01" => 14,
        "02" => 14,
        "11" => 6, "12" => 6, "13" => 6, "15" => 6, "17" => 6,
        "20" => 2,
        _    => 0
    };

    private static bool IsKnownAiAt(string data, int pos)
    {
        foreach (var len in new[] { 2, 3, 4 })
        {
            if (pos + len > data.Length) continue;
            if (IsKnownAi(data.Substring(pos, len))) return true;
        }
        return false;
    }
}
