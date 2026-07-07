using System;
using System.Linq;
using System.Text.RegularExpressions;

namespace PeasyWare.Application.Utilities;

/// <summary>
/// Wildcard pattern matching for bin code / SKU searches.
/// Supports * (any run of characters) and ? (any single character).
/// Without wildcards, falls back to a plain case-insensitive substring match.
/// </summary>
public static class WildcardMatcher
{
    public static bool Matches(string input, string pattern)
    {
        if (string.IsNullOrEmpty(pattern))
            return true;

        if (!pattern.Contains('*') && !pattern.Contains('?'))
            return input.Contains(pattern, StringComparison.OrdinalIgnoreCase);

        var regexPattern = "^" + string.Concat(pattern.Select(c =>
            c switch
            {
                '*' => ".*",
                '?' => ".",
                _   => Regex.Escape(c.ToString())
            })) + "$";

        return Regex.IsMatch(input, regexPattern, RegexOptions.IgnoreCase);
    }
}
