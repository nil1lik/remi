namespace Remi.Domain.Common;

/// <summary>Tutarlılık sınırı: değişiklikler yalnız kökün yöntemleriyle yapılır.</summary>
public abstract class AggregateRoot<TId> where TId : struct
{
    public TId Id { get; protected init; }
}
