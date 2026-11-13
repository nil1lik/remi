using System.Net;
using System.Net.Http.Json;

namespace Remi.Api.Tests;

public sealed class GroupTests : IClassFixture<RemiFactory>
{
    private readonly RemiFactory _factory;
    public GroupTests(RemiFactory factory) => _factory = factory;

    private static object NewGroup(string name = "A1-20 sınıfı", string? link = "https://chat.whatsapp.com/AbC123xyz",
        int[]? days = null, int reminder = 10, Guid? id = null, int? version = null) => new
    {
        id, name, color = "blue", chatLink = link, days = days ?? [4, 6], startMinute = 540, durationMinutes = 60,
        reminderMinutes = reminder, reminderKind = "notification", version,
    };

    private static async Task<GroupBody> CreateAsync(Session s, object body)
    {
        var response = await s.Client.PostAsJsonAsync("/v1/groups", body);
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        return (await response.Content.ReadFromJsonAsync<GroupBody>())!;
    }

    [Fact]
    public async Task Create_update_delete_with_versions()
    {
        var s = await _factory.SignInAsync("crud");
        var group = await CreateAsync(s, NewGroup());
        Assert.Equal([4, 6], group.Days);
        Assert.Equal("whatsapp", group.ChatApp);
        Assert.Equal(1, group.Version);

        var updated = await s.Client.PutAsJsonAsync($"/v1/groups/{group.Id}", NewGroup(name: "A1-21", version: 1));
        Assert.Equal(HttpStatusCode.OK, updated.StatusCode);
        Assert.Equal(2, (await updated.Content.ReadFromJsonAsync<GroupBody>())!.Version);

        // Başka bir cihaz eski sürümle yazarsa çakışma bildirilir, veri ezilmez.
        var stale = await s.Client.PutAsJsonAsync($"/v1/groups/{group.Id}", NewGroup(name: "Eski", version: 1));
        Assert.Equal(HttpStatusCode.Conflict, stale.StatusCode);

        Assert.Equal(HttpStatusCode.NoContent, (await s.Client.DeleteAsync($"/v1/groups/{group.Id}")).StatusCode);
        var list = await s.Client.GetFromJsonAsync<List<GroupBody>>("/v1/groups");
        Assert.Empty(list!);
    }

    [Fact]
    public async Task Users_cannot_see_or_touch_each_others_groups()
    {
        var owner = await _factory.SignInAsync("owner");
        var intruder = await _factory.SignInAsync("intruder");
        var group = await CreateAsync(owner, NewGroup());

        Assert.Empty((await intruder.Client.GetFromJsonAsync<List<GroupBody>>("/v1/groups"))!);
        Assert.Equal(HttpStatusCode.NotFound,
            (await intruder.Client.PutAsJsonAsync($"/v1/groups/{group.Id}", NewGroup(name: "Ele geçirildi", version: 1))).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await intruder.Client.DeleteAsync($"/v1/groups/{group.Id}")).StatusCode);

        // Başkasının kimliğiyle grup oluşturulamaz ve kime ait olduğu söylenmez.
        var steal = await intruder.Client.PostAsJsonAsync("/v1/groups", NewGroup(id: group.Id));
        Assert.Equal(HttpStatusCode.Conflict, steal.StatusCode);
        Assert.Contains("id_unavailable", await steal.Content.ReadAsStringAsync());

        var sync = await intruder.Client.GetFromJsonAsync<SyncBody>("/v1/sync?since=0");
        Assert.Empty(sync!.Groups);

        var mine = await owner.Client.GetFromJsonAsync<List<GroupBody>>("/v1/groups");
        Assert.Equal("A1-20 sınıfı", Assert.Single(mine!).Name);
    }

    [Theory]
    [InlineData("javascript:alert(1)")]
    [InlineData("http://chat.whatsapp.com/AbC123")]
    [InlineData("https://evil.example/AbC123")]
    [InlineData("https://chat.whatsapp.com.evil.example/AbC123")]
    [InlineData("https://user:pass@chat.whatsapp.com/AbC123")]
    [InlineData("https://chat.whatsapp.com:8443/AbC123")]
    [InlineData("https://chat.whatsapp.com/")]
    [InlineData("https://t.me/x?url=https://evil.example")]
    [InlineData("whatsapp://send?text=hi")]
    [InlineData("data:text/html,<script>alert(1)</script>")]
    public async Task Unsafe_or_foreign_chat_links_are_rejected(string link)
    {
        var s = await _factory.SignInAsync("links");
        var response = await s.Client.PostAsJsonAsync("/v1/groups", NewGroup(link: link));
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Contains("chatLink", await response.Content.ReadAsStringAsync());
    }

    [Theory]
    [InlineData("chat.whatsapp.com/AbC123xyz", "https://chat.whatsapp.com/AbC123xyz", "whatsapp")]
    [InlineData("https://T.ME/joinchat/Xy-Z_9", "https://t.me/joinchat/Xy-Z_9", "telegram")]
    [InlineData("https://t.me/+AbCdEf", "https://t.me/+AbCdEf", "telegram")]
    [InlineData("  https://telegram.me/remi_grup  ", "https://telegram.me/remi_grup", "telegram")]
    public async Task Chat_links_are_normalized(string input, string expected, string app)
    {
        var s = await _factory.SignInAsync("normalize");
        var group = await CreateAsync(s, NewGroup(link: input));
        Assert.Equal(expected, group.ChatLink);
        Assert.Equal(app, group.ChatApp);
    }

    [Theory]
    [InlineData(7)]
    [InlineData(61)]
    [InlineData(90)]
    [InlineData(780)]
    [InlineData(-5)]
    public async Task Reminder_outside_the_wheel_is_rejected(int minutes)
    {
        var s = await _factory.SignInAsync("reminders");
        var response = await s.Client.PostAsJsonAsync("/v1/groups", NewGroup(reminder: minutes));
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(60)]
    [InlineData(120)]
    [InlineData(720)]
    public async Task Reminder_on_the_wheel_is_accepted(int minutes)
    {
        var s = await _factory.SignInAsync("reminders-ok");
        Assert.Equal(minutes, (await CreateAsync(s, NewGroup(reminder: minutes))).ReminderMinutes);
    }

    [Fact]
    public async Task Invalid_fields_are_rejected()
    {
        var s = await _factory.SignInAsync("fields");
        foreach (var body in new object[]
        {
            NewGroup(name: ""),
            NewGroup(name: new string('x', 61)),
            NewGroup(name: "A1‮gnp.exe"),
            NewGroup(name: "A1\u0000"),
            NewGroup(days: []),
            NewGroup(days: [0]),
            NewGroup(days: [8]),
            new { name = "Gece", days = new[] { 1 }, startMinute = 1400, durationMinutes = 60 },
            new { name = "Renk", color = "#ff0000", days = new[] { 1 }, startMinute = 600 },
            new { name = "Tatil", days = new[] { 1 }, startMinute = 600, holidayStart = "2026-12-10", holidayEnd = "2026-12-01" },
        })
        {
            var response = await s.Client.PostAsJsonAsync("/v1/groups", body);
            Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        }
    }

    [Fact]
    public async Task Sync_returns_only_changes_since_cursor_including_deletions()
    {
        var s = await _factory.SignInAsync("sync");
        var full = await s.Client.GetFromJsonAsync<SyncBody>("/v1/sync?since=0");
        Assert.NotNull(full!.Profile);

        var a = await CreateAsync(s, NewGroup(name: "A"));
        var b = await CreateAsync(s, NewGroup(name: "B"));
        var afterCreate = await s.Client.GetFromJsonAsync<SyncBody>($"/v1/sync?since={full.Cursor}");
        Assert.Equal(["A", "B"], afterCreate!.Groups.Select(g => g.Name));
        Assert.Null(afterCreate.Profile);

        await s.Client.DeleteAsync($"/v1/groups/{a.Id}");
        var afterDelete = await s.Client.GetFromJsonAsync<SyncBody>($"/v1/sync?since={afterCreate.Cursor}");
        var tombstone = Assert.Single(afterDelete!.Groups);
        Assert.Equal(a.Id, tombstone.Id);
        Assert.True(tombstone.Deleted);
        Assert.Equal("", tombstone.Name);

        var fresh = await s.Client.GetFromJsonAsync<SyncBody>("/v1/sync?since=0");
        Assert.Equal(b.Id, Assert.Single(fresh!.Groups).Id);
    }

    [Fact]
    public async Task Client_generated_id_is_honored_and_duplicates_conflict()
    {
        var s = await _factory.SignInAsync("offline");
        var id = Guid.NewGuid();
        Assert.Equal(id, (await CreateAsync(s, NewGroup(id: id))).Id);
        var again = await s.Client.PostAsJsonAsync("/v1/groups", NewGroup(id: id));
        Assert.Equal(HttpStatusCode.Conflict, again.StatusCode);
        Assert.Contains("already_exists", await again.Content.ReadAsStringAsync());
    }
}
