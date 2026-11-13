using System.Net;
using System.Net.Http.Json;

namespace Remi.Api.Tests;

public sealed class ProfileTests : IClassFixture<RemiFactory>
{
    private readonly RemiFactory _factory;
    public ProfileTests(RemiFactory factory) => _factory = factory;

    [Fact]
    public async Task Profile_settings_are_saved_and_validated()
    {
        var s = await _factory.SignInAsync("settings");
        var ok = await s.Client.PatchAsJsonAsync("/v1/me",
            new { locale = "ar", theme = "dark", accent = "mint", defaultReminderMinutes = 120, defaultReminderKind = "alarm" });
        Assert.Equal(HttpStatusCode.OK, ok.StatusCode);
        var profile = await s.Client.GetFromJsonAsync<ProfileBody>("/v1/me");
        Assert.Equal(("ar", "dark", "mint", 120, "alarm"),
            (profile!.Locale, profile.Theme, profile.Accent, profile.DefaultReminderMinutes, profile.DefaultReminderKind));

        foreach (var bad in new object[] { new { locale = "de" }, new { theme = "pink" }, new { defaultReminderMinutes = 61 }, new { displayName = new string('a', 41) } })
            Assert.Equal(HttpStatusCode.BadRequest, (await s.Client.PatchAsJsonAsync("/v1/me", bad)).StatusCode);
    }

    [Fact]
    public async Task Teacher_vacation_can_be_started_and_ended()
    {
        var s = await _factory.SignInAsync("vacation");
        var start = await s.Client.PutAsJsonAsync("/v1/me/vacation", new { start = "2026-11-13", end = "2026-11-24" });
        Assert.Equal(HttpStatusCode.OK, start.StatusCode);
        Assert.Equal(new DateOnly(2026, 11, 24), (await start.Content.ReadFromJsonAsync<ProfileBody>())!.VacationEnd);

        Assert.Equal(HttpStatusCode.BadRequest,
            (await s.Client.PutAsJsonAsync("/v1/me/vacation", new { start = "2026-11-24", end = "2026-11-13" })).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest,
            (await s.Client.PutAsJsonAsync("/v1/me/vacation", new { start = "2026-01-01", end = "2027-06-01" })).StatusCode);

        var end = await s.Client.DeleteAsync("/v1/me/vacation");
        Assert.Null((await end.Content.ReadFromJsonAsync<ProfileBody>())!.VacationStart);
    }

    [Fact]
    public async Task Deleting_the_account_removes_everything_and_invalidates_tokens()
    {
        var s = await _factory.SignInAsync("goodbye");
        await s.Client.PostAsJsonAsync("/v1/groups",
            new { name = "Silinecek", days = new[] { 1 }, startMinute = 600, chatLink = "https://t.me/sil" });

        Assert.Equal(HttpStatusCode.NoContent, (await s.Client.DeleteAsync("/v1/me")).StatusCode);

        // Erişim anahtarının süresi dolmamış olsa bile artık işe yaramaz.
        var me = await s.Client.GetAsync("/v1/me");
        Assert.Equal(HttpStatusCode.Unauthorized, me.StatusCode);
        Assert.Contains("account_not_found", await me.Content.ReadAsStringAsync());

        var refresh = await _factory.CreateClient().PostAsJsonAsync("/v1/auth/refresh", new { refreshToken = s.Auth.RefreshToken });
        Assert.Equal(HttpStatusCode.Unauthorized, refresh.StatusCode);

        // Aynı Apple hesabıyla yeniden girişte boş, yeni bir hesap açılır.
        var again = await _factory.SignInAsync("goodbye");
        Assert.NotEqual(s.Auth.Profile.Id, again.Auth.Profile.Id);
        Assert.Empty((await again.Client.GetFromJsonAsync<List<GroupBody>>("/v1/groups"))!);
    }
}
