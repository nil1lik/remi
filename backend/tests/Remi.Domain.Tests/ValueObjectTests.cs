using Remi.Domain.Accounts;
using Remi.Domain.Common;
using Remi.Domain.Groups;

namespace Remi.Domain.Tests;

public sealed class ValueObjectTests
{
    [Theory]
    [InlineData("chat.whatsapp.com/AbC123", "https://chat.whatsapp.com/AbC123", ChatApp.WhatsApp)]
    [InlineData("https://T.ME/+AbC", "https://t.me/+AbC", ChatApp.Telegram)]
    [InlineData(" https://telegram.me/remi_grup/ ", "https://telegram.me/remi_grup", ChatApp.Telegram)]
    public void ChatLink_accepts_and_normalizes_group_links(string input, string url, ChatApp app)
    {
        var link = ChatLink.Create(input);
        Assert.True(link.IsSuccess);
        Assert.Equal((url, app), (link.Value.Url, link.Value.App));
    }

    [Theory]
    [InlineData("javascript:alert(1)")]
    [InlineData("http://chat.whatsapp.com/AbC")]
    [InlineData("https://chat.whatsapp.com.evil.example/AbC")]
    [InlineData("https://user@t.me/AbC")]
    [InlineData("https://t.me:444/AbC")]
    [InlineData("https://t.me/AbC#x")]
    [InlineData("https://t.me/AbC?start=x")]
    [InlineData("https://t.me/")]
    [InlineData("https://t.me/a%2Fb")]
    public void ChatLink_rejects_anything_else(string input) => Assert.False(ChatLink.Create(input).IsSuccess);

    [Fact]
    public void Empty_chat_link_means_no_link() => Assert.Null(ChatLink.CreateOptional("  ").Value);

    [Theory]
    [InlineData(0, true)] [InlineData(5, true)] [InlineData(60, true)] [InlineData(120, true)] [InlineData(720, true)]
    [InlineData(3, false)] [InlineData(65, false)] [InlineData(90, false)] [InlineData(780, false)] [InlineData(-5, false)]
    public void Reminder_matches_the_wheel(int minutes, bool allowed) =>
        Assert.Equal(allowed, Reminder.Create(minutes, ReminderKind.Alarm).IsSuccess);

    [Fact]
    public void GroupName_is_trimmed_and_limited()
    {
        Assert.Equal("A1-20", GroupName.Create("  A1-20 ").Value.Value);
        Assert.Equal("required", GroupName.Create("   ").Errors[0].Code);
        Assert.Equal("too_long", GroupName.Create(new string('x', 61)).Errors[0].Code);
        Assert.Equal("invalid_characters", GroupName.Create("A1‮gnp.exe").Errors[0].Code);
    }

    [Fact]
    public void WeeklySchedule_reports_every_problem_with_its_field()
    {
        var bad = WeeklySchedule.Create([0, 3], 1500, 5);
        Assert.Equal(["days", "startMinute", "durationMinutes"], bad.Errors.Select(e => e.Field));

        Assert.Equal("ends_after_midnight", WeeklySchedule.Create([1], 23 * 60, 90).Errors.Single().Code);

        var ok = WeeklySchedule.Create([4, 6], 540, 60).Value;
        Assert.Equal(Weekdays.Thursday | Weekdays.Saturday, ok.Days);
        Assert.Equal([4, 6], ok.IsoDays());
    }

    [Fact]
    public void DateRange_is_ordered_and_at_most_a_year()
    {
        var d = new DateOnly(2026, 11, 13);
        Assert.True(DateRange.Create(d, d).IsSuccess);
        Assert.Equal("end_before_start", DateRange.Create(d, d.AddDays(-1)).Errors[0].Code);
        Assert.Equal("too_long", DateRange.Create(d, d.AddDays(367)).Errors[0].Code);
        Assert.Equal("both_dates_required", DateRange.CreateOptional(d, null).Errors[0].Code);
        Assert.Null(DateRange.CreateOptional(null, null).Value);
    }

    [Theory]
    [InlineData("dark", true)] [InlineData("Dark", false)] [InlineData("1", false)] [InlineData("purple", false)] [InlineData(null, false)]
    public void Enums_accept_only_their_lowercase_names(string? text, bool ok) =>
        Assert.Equal(ok, EnumText.Parse<Theme>(text).IsSuccess);
}
