using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace Remi.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class Initial : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "accounts",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    DisplayName = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    Revision = table.Column<long>(type: "bigint", nullable: false),
                    ProfileRevision = table.Column<long>(type: "bigint", nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    VacationEnd = table.Column<DateOnly>(type: "date", nullable: true),
                    VacationStart = table.Column<DateOnly>(type: "date", nullable: true),
                    Preferences_Accent = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    Preferences_Locale = table.Column<string>(type: "character varying(8)", maxLength: 8, nullable: false),
                    Preferences_Theme = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    Preferences_DefaultReminder_Kind = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    Preferences_DefaultReminder_MinutesBefore = table.Column<int>(type: "integer", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_accounts", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "account_logins",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    Provider = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    Subject = table.Column<string>(type: "character varying(255)", maxLength: 255, nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    LastUsedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    AccountId = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_account_logins", x => x.Id);
                    table.ForeignKey(
                        name: "FK_account_logins_accounts_AccountId",
                        column: x => x.AccountId,
                        principalTable: "accounts",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "groups",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    OwnerId = table.Column<Guid>(type: "uuid", nullable: false),
                    Name = table.Column<string>(type: "character varying(60)", maxLength: 60, nullable: false),
                    Color = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    ChatLink = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    Version = table.Column<int>(type: "integer", nullable: false),
                    Revision = table.Column<long>(type: "bigint", nullable: false),
                    IsDeleted = table.Column<bool>(type: "boolean", nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    HolidayEnd = table.Column<DateOnly>(type: "date", nullable: true),
                    HolidayStart = table.Column<DateOnly>(type: "date", nullable: true),
                    Reminder_Kind = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    Reminder_MinutesBefore = table.Column<int>(type: "integer", nullable: false),
                    Schedule_Days = table.Column<int>(type: "integer", nullable: false),
                    Schedule_DurationMinutes = table.Column<int>(type: "integer", nullable: false),
                    Schedule_StartMinute = table.Column<int>(type: "integer", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_groups", x => x.Id);
                    table.ForeignKey(
                        name: "FK_groups_accounts_OwnerId",
                        column: x => x.OwnerId,
                        principalTable: "accounts",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "refresh_tokens",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    AccountId = table.Column<Guid>(type: "uuid", nullable: false),
                    FamilyId = table.Column<Guid>(type: "uuid", nullable: false),
                    TokenHash = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    ExpiresAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    RevokedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    ReplacedById = table.Column<Guid>(type: "uuid", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_refresh_tokens", x => x.Id);
                    table.ForeignKey(
                        name: "FK_refresh_tokens_accounts_AccountId",
                        column: x => x.AccountId,
                        principalTable: "accounts",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_account_logins_AccountId",
                table: "account_logins",
                column: "AccountId");

            migrationBuilder.CreateIndex(
                name: "IX_account_logins_Provider_Subject",
                table: "account_logins",
                columns: new[] { "Provider", "Subject" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_groups_OwnerId_Revision",
                table: "groups",
                columns: new[] { "OwnerId", "Revision" });

            migrationBuilder.CreateIndex(
                name: "IX_refresh_tokens_AccountId",
                table: "refresh_tokens",
                column: "AccountId");

            migrationBuilder.CreateIndex(
                name: "IX_refresh_tokens_FamilyId",
                table: "refresh_tokens",
                column: "FamilyId");

            migrationBuilder.CreateIndex(
                name: "IX_refresh_tokens_TokenHash",
                table: "refresh_tokens",
                column: "TokenHash",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "account_logins");

            migrationBuilder.DropTable(
                name: "groups");

            migrationBuilder.DropTable(
                name: "refresh_tokens");

            migrationBuilder.DropTable(
                name: "accounts");
        }
    }
}
