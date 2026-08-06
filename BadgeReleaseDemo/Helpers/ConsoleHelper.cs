// <copyright file="ConsoleHelper.cs" company="Microsoft">
//     Copyright (c) Microsoft Corporation. All rights reserved.
// </copyright>

namespace BadgeReleaseDemo.Helpers;

/// <summary>
/// Lightweight console helpers with Unicode indicators and colored text.
/// </summary>
public static class ConsoleHelper
{
    public static void WriteHeader(string title)
    {
        Console.ForegroundColor = ConsoleColor.Cyan;
        Console.WriteLine();
        Console.WriteLine(new string('═', 60));
        Console.WriteLine($"  {title}");
        Console.WriteLine(new string('═', 60));
        Console.ResetColor();
    }

    public static void WriteStep(string emoji, string description)
    {
        Console.ForegroundColor = ConsoleColor.White;
        Console.WriteLine();
        Console.Write($"  {emoji} ");
        Console.ForegroundColor = ConsoleColor.Cyan;
        Console.WriteLine(description);
        Console.ResetColor();
    }

    public static void WriteSuccess(string message)
    {
        Console.ForegroundColor = ConsoleColor.Green;
        Console.WriteLine($"  ✅ {message}");
        Console.ResetColor();
    }

    public static void WriteError(string message)
    {
        Console.ForegroundColor = ConsoleColor.Red;
        Console.WriteLine($"  ❌ {message}");
        Console.ResetColor();
    }

    public static void WriteInfo(string message)
    {
        Console.ForegroundColor = ConsoleColor.DarkGray;
        Console.WriteLine($"     {message}");
        Console.ResetColor();
    }

    public static void WriteWarning(string message)
    {
        Console.ForegroundColor = ConsoleColor.Yellow;
        Console.WriteLine($"  ⚠️  {message}");
        Console.ResetColor();
    }

    public static void WriteProgress(string message)
    {
        Console.ForegroundColor = ConsoleColor.DarkYellow;
        Console.WriteLine($"  ⏳ {message}");
        Console.ResetColor();
    }

    public static string Prompt(string message)
    {
        Console.ForegroundColor = ConsoleColor.Yellow;
        Console.Write($"  ➤ {message}: ");
        Console.ResetColor();
        return Console.ReadLine()?.Trim() ?? string.Empty;
    }

    public static bool PromptYesNo(string message)
    {
        Console.ForegroundColor = ConsoleColor.Yellow;
        Console.Write($"  ➤ {message} (y/n): ");
        Console.ResetColor();
        var input = Console.ReadLine()?.Trim().ToLowerInvariant();
        return input == "y" || input == "yes";
    }

    public static void WriteKeyValue(string key, string? value)
    {
        Console.ForegroundColor = ConsoleColor.DarkGray;
        Console.Write($"     {key}: ");
        Console.ForegroundColor = ConsoleColor.White;
        Console.WriteLine(value ?? "(null)");
        Console.ResetColor();
    }
}
