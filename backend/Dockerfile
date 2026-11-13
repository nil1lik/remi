# Derleme
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY Remi.slnx ./
COPY src/Remi.Domain/Remi.Domain.csproj src/Remi.Domain/
COPY src/Remi.Application/Remi.Application.csproj src/Remi.Application/
COPY src/Remi.Infrastructure/Remi.Infrastructure.csproj src/Remi.Infrastructure/
COPY src/Remi.Api/Remi.Api.csproj src/Remi.Api/
RUN dotnet restore src/Remi.Api/Remi.Api.csproj
COPY src/ src/
RUN dotnet publish src/Remi.Api/Remi.Api.csproj -c Release -o /app --no-restore

# Çalıştırma: yalnız çalışma zamanı, yetkisiz kullanıcı
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
COPY --from=build /app ./
ENV ASPNETCORE_HTTP_PORTS=8080 \
    DOTNET_EnableDiagnostics=0
USER $APP_UID
EXPOSE 8080
ENTRYPOINT ["dotnet", "Remi.Api.dll"]
