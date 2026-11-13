using Microsoft.EntityFrameworkCore;
using Remi.Domain.Accounts;
using Remi.Domain.Groups;
using Remi.Domain.Sessions;

namespace Remi.Infrastructure.Persistence;

/// <summary>
/// Domain modelinin PostgreSQL eşlemesi. Value object'ler tek sütuna dönüştürülür ya da gömülü (complex) tip
/// olarak saklanır; domain sınıfları veritabanından habersizdir.
/// </summary>
public sealed class RemiDbContext(DbContextOptions<RemiDbContext> options) : DbContext(options)
{
    public DbSet<Account> Accounts => Set<Account>();
    public DbSet<Group> Groups => Set<Group>();
    public DbSet<RefreshToken> RefreshTokens => Set<RefreshToken>();

    protected override void OnModelCreating(ModelBuilder b)
    {
        b.Entity<Account>(e =>
        {
            e.ToTable("accounts");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasConversion(id => id.Value, v => new AccountId(v));
            e.Property(x => x.DisplayName).HasConversion(n => n.Value, v => DisplayName.Restore(v)).HasMaxLength(DisplayName.MaxLength);
            e.ComplexProperty(x => x.Preferences, p =>
            {
                p.Property(x => x.Locale).HasConversion<string>().HasMaxLength(8);
                p.Property(x => x.Theme).HasConversion<string>().HasMaxLength(16);
                p.Property(x => x.Accent).HasConversion<string>().HasMaxLength(16);
                p.ComplexProperty(x => x.DefaultReminder, r =>
                {
                    r.Property(x => x.MinutesBefore);
                    r.Property(x => x.Kind).HasConversion<string>().HasMaxLength(16);
                });
            });
            e.Property<DateOnly?>("_vacationStart").HasColumnName("VacationStart");
            e.Property<DateOnly?>("_vacationEnd").HasColumnName("VacationEnd");
            e.Ignore(x => x.Vacation);
            // Eşzamanlı iki değişiklik aynı revizyon numarasını alamasın.
            e.Property(x => x.Revision).IsConcurrencyToken();

            e.OwnsMany(x => x.Logins, l =>
            {
                l.ToTable("account_logins");
                l.WithOwner().HasForeignKey("AccountId");
                l.Property<int>("Id");
                l.HasKey("Id");
                l.Property(x => x.Provider).HasConversion<string>().HasMaxLength(16);
                l.Property(x => x.Subject).HasMaxLength(ExternalIdentity.MaxSubjectLength);
                l.HasIndex(x => new { x.Provider, x.Subject }).IsUnique();
            });
            e.Navigation(x => x.Logins).HasField("_logins").UsePropertyAccessMode(PropertyAccessMode.Field);
        });

        b.Entity<Group>(e =>
        {
            e.ToTable("groups");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasConversion(id => id.Value, v => new GroupId(v));
            e.Property(x => x.OwnerId).HasConversion(id => id.Value, v => new AccountId(v));
            e.HasOne<Account>().WithMany().HasForeignKey(x => x.OwnerId).OnDelete(DeleteBehavior.Cascade);
            e.Property(x => x.Name).HasConversion(n => n.Value, v => GroupName.Restore(v)).HasMaxLength(GroupName.MaxLength);
            e.Property(x => x.Color).HasConversion<string>().HasMaxLength(16);
            e.Property(x => x.ChatLink).HasConversion(l => l!.Url, v => ChatLink.Restore(v)).HasMaxLength(ChatLink.MaxLength);
            e.ComplexProperty(x => x.Schedule, s =>
            {
                s.Property(x => x.Days).HasConversion<int>();
                s.Property(x => x.StartMinute);
                s.Property(x => x.DurationMinutes);
            });
            e.ComplexProperty(x => x.Reminder, r =>
            {
                r.Property(x => x.MinutesBefore);
                r.Property(x => x.Kind).HasConversion<string>().HasMaxLength(16);
            });
            e.Property<DateOnly?>("_holidayStart").HasColumnName("HolidayStart");
            e.Property<DateOnly?>("_holidayEnd").HasColumnName("HolidayEnd");
            e.Ignore(x => x.Holiday);
            e.Property(x => x.Version).IsConcurrencyToken();
            e.HasIndex(x => new { x.OwnerId, x.Revision });
        });

        b.Entity<RefreshToken>(e =>
        {
            e.ToTable("refresh_tokens");
            e.HasKey(x => x.Id);
            e.Property(x => x.AccountId).HasConversion(id => id.Value, v => new AccountId(v));
            e.HasOne<Account>().WithMany().HasForeignKey(x => x.AccountId).OnDelete(DeleteBehavior.Cascade);
            e.Property(x => x.TokenHash).HasMaxLength(64);
            e.HasIndex(x => x.TokenHash).IsUnique();
            e.HasIndex(x => x.FamilyId);
            // Aynı anahtarla yarışan iki yenileme isteğinden yalnız biri kazanır; diğeri çalınma sayılır.
            e.Property(x => x.ReplacedById).IsConcurrencyToken();
        });
    }
}
