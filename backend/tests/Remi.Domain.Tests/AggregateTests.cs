using Remi.Domain.Accounts;
using Remi.Domain.Common;
using Remi.Domain.Groups;
using Remi.Domain.Sessions;

namespace Remi.Domain.Tests;

public sealed class AggregateTests
{
    private static readonly DateTimeOffset Now = new(2026, 11, 13, 9, 0, 0, TimeSpan.Zero);

    private static Account NewAccount(string sub = "teacher") =>
        Account.Register(ExternalIdentity.Create(IdentityProvider.Apple, sub).Value, DisplayName.Create("Hocam").Value, Locale.Tr, Now);

    private static GroupDetails Details(string name = "A1-20", DateRange? holiday = null) => new(
        GroupName.Create(name).Value, GroupColor.Blue, ChatLink.Create("https://t.me/a1").Value,
        WeeklySchedule.Create([4, 6], 540, 60).Value, Reminder.Default, holiday);

    [Fact]
    public void Every_change_gets_a_new_revision_from_the_owner()
    {
        var owner = NewAccount();
        var start = owner.Revision;
        var group = Group.Create(GroupId.New(), owner, Details(), Now);
        Assert.Equal(start + 1, group.Revision);

        Assert.True(group.Update(owner, 1, Details("A1-21"), Now).IsSuccess);
        Assert.Equal((2, start + 2), (group.Version, group.Revision));
        Assert.Equal(start + 2, owner.Revision);
    }

    [Fact]
    public void Stale_version_cannot_overwrite()
    {
        var owner = NewAccount();
        var group = Group.Create(GroupId.New(), owner, Details(), Now);
        group.Update(owner, 1, Details("Yeni"), Now);

        var stale = group.Update(owner, 1, Details("Eski"), Now);
        Assert.Equal((ErrorKind.Conflict, "version_mismatch"), (stale.Errors[0].Kind, stale.Errors[0].Code));
        Assert.Equal("Yeni", group.Name.Value);
    }

    [Fact]
    public void Another_account_cannot_change_or_delete_the_group()
    {
        var owner = NewAccount("owner");
        var other = NewAccount("other");
        var group = Group.Create(GroupId.New(), owner, Details(), Now);

        Assert.Equal(ErrorKind.NotFound, group.Update(other, 1, Details("X"), Now).Errors[0].Kind);
        Assert.Equal(ErrorKind.NotFound, group.Delete(other, null, Now).Errors[0].Kind);
        Assert.False(group.IsDeleted);
    }

    [Fact]
    public void Deleting_wipes_personal_data_but_keeps_a_tombstone()
    {
        var owner = NewAccount();
        var group = Group.Create(GroupId.New(), owner, Details(holiday: DateRange.Create(new(2026, 12, 1), new(2026, 12, 7)).Value), Now);
        Assert.True(group.Delete(owner, 1, Now).IsSuccess);
        Assert.True(group.IsDeleted);
        Assert.Equal("", group.Name.Value);
        Assert.Null(group.ChatLink);
        Assert.Null(group.Holiday);
        Assert.Equal(ErrorKind.NotFound, group.Delete(owner, null, Now).Errors[0].Kind);
    }

    [Fact]
    public void Group_is_paused_by_its_own_holiday_or_the_teachers_vacation()
    {
        var owner = NewAccount();
        var group = Group.Create(GroupId.New(), owner, Details(holiday: DateRange.Create(new(2026, 11, 16), new(2026, 11, 20)).Value), Now);

        Assert.True(group.IsPausedOn(new(2026, 11, 18), owner));
        Assert.False(group.IsPausedOn(new(2026, 11, 25), owner));

        owner.StartVacation(DateRange.Create(new(2026, 11, 24), new(2026, 11, 30)).Value);
        Assert.True(group.IsPausedOn(new(2026, 11, 25), owner));

        owner.EndVacation();
        Assert.False(group.IsPausedOn(new(2026, 11, 25), owner));
    }

    [Fact]
    public void Profile_changes_move_the_profile_revision()
    {
        var owner = NewAccount();
        var before = owner.ProfileRevision;
        owner.Personalize(null, owner.Preferences with { Theme = Theme.Dark });
        Assert.True(owner.ProfileRevision > before);
        Assert.Equal("Hocam", owner.DisplayName.Value);
    }

    [Fact]
    public void Refresh_token_rotates_once_and_never_again()
    {
        var token = RefreshToken.Issue(AccountId.New(), Guid.NewGuid(), "hash1", Now, TimeSpan.FromDays(60));
        var next = token.Rotate("hash2", Now, TimeSpan.FromDays(60));

        Assert.True(token.WasUsedOrRevoked);
        Assert.Equal(token.FamilyId, next.FamilyId);
        Assert.Equal(next.Id, token.ReplacedById);
        Assert.Throws<InvalidOperationException>(() => token.Rotate("hash3", Now, TimeSpan.FromDays(60)));
        Assert.True(next.IsExpired(Now.AddDays(61)));
    }
}
