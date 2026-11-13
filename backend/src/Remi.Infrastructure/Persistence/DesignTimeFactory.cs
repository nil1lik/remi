using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace Remi.Infrastructure.Persistence;

/// <summary>Yalnız "dotnet ef migrations add" için: göç dosyası üretirken veritabanına bağlanılmaz.</summary>
internal sealed class DesignTimeFactory : IDesignTimeDbContextFactory<RemiDbContext>
{
    public RemiDbContext CreateDbContext(string[] args) =>
        new(new DbContextOptionsBuilder<RemiDbContext>().UseNpgsql("Host=localhost;Database=remi_design").Options);
}
