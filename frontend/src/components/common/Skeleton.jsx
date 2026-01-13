/**
 * Skeleton Component
 * Generic loading skeleton for shimmer effect
 */
export function Skeleton({ width = '100%', height = '1rem', style = {} }) {
    return (
        <div
            className="skeleton"
            style={{ width, height, borderRadius: '4px', ...style }}
        />
    );
}

/**
 * ProductCardSkeleton
 * Loading state for product card
 */
export function ProductCardSkeleton() {
    return (
        <div className="product-card skeleton-card">
            <div className="product-image skeleton"></div>
            <div className="product-info">
                <Skeleton width="80%" height="1rem" style={{ marginBottom: '0.5rem' }} />
                <Skeleton width="40%" height="1.25rem" />
            </div>
        </div>
    );
}

/**
 * GridSkeleton
 * Loading state for product grid
 */
export function GridSkeleton({ count = 8 }) {
    return (
        <div className="product-grid">
            {Array.from({ length: count }).map((_, i) => (
                <ProductCardSkeleton key={i} />
            ))}
        </div>
    );
}

/**
 * DetailSkeleton
 * Loading state for product detail page
 */
export function DetailSkeleton() {
    return (
        <div className="detail-layout">
            <div className="detail-image skeleton"></div>
            <div className="detail-info">
                <Skeleton width="60%" height="2rem" style={{ marginBottom: '1rem' }} />
                <Skeleton width="100%" height="1rem" style={{ marginBottom: '0.5rem' }} />
                <Skeleton width="100%" height="1rem" style={{ marginBottom: '0.5rem' }} />
                <Skeleton width="80%" height="1rem" style={{ marginBottom: '1rem' }} />
                <Skeleton width="30%" height="2rem" />
            </div>
        </div>
    );
}
